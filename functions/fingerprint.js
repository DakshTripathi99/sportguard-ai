const vision = require("@google-cloud/vision");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

const { scoreViolation } = require("./scoring");

const genai = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const visionClient = new vision.ImageAnnotatorClient();

const db = () => admin.firestore();

async function fingerprintImage(assetId, downloadUrl) {
  console.log("🚀 Starting fingerprint:", assetId);

  try {
    // ===============================
    // STEP 0: Fetch asset
    // ===============================
    const assetDoc = await db().collection("assets").doc(assetId).get();
    const assetData = assetDoc.data();

    if (!assetData) throw new Error("Asset not found");

    const orgId = assetData.orgId;

    // ===============================
    // STEP 1: Vision API
    // ===============================
    const [visionResult] = await visionClient.annotateImage({
      image: { source: { imageUri: downloadUrl } },
      features: [
        { type: "LABEL_DETECTION", maxResults: 10 },
        { type: "WEB_DETECTION", maxResults: 10 },
      ],
    });

    const labels =
      visionResult.labelAnnotations?.map((l) => l.description) || [];

    const webDetection = visionResult.webDetection || {};

    // ---------------------------------------------------------------
    // FIX: Use fullMatchingImages + partialMatchingImages for scoring.
    // pagesWithMatchingImages.score is almost always 0 or missing —
    // it is NOT a visual similarity score and must NOT be used as one.
    // ---------------------------------------------------------------
    const fullMatches = webDetection.fullMatchingImages || [];
    const partialMatches = webDetection.partialMatchingImages || [];
    const webPages = webDetection.pagesWithMatchingImages || [];

    console.log(
      `🌐 Vision results — full: ${fullMatches.length}, partial: ${partialMatches.length}, pages: ${webPages.length}`
    );

    // Build a deduplicated, scored match list from the correct fields.
    // Full image matches get score 0.95 (near-certain copy).
    // Partial matches get 0.75 (cropped / reposted variant).
    // Page-only hits (no direct image match) get 0.65 so they still
    // go through AI scoring but sit below the combined-score threshold
    // on their own — Gemini confidence will determine the outcome.
    const seenUrls = new Set();

    const buildMatches = (items, score) =>
      items
        .filter((item) => {
          if (!item.url || seenUrls.has(item.url)) return false;
          seenUrls.add(item.url);
          return true;
        })
        .map((item) => ({ url: item.url, score }));

    const imageMatches = [
      ...buildMatches(fullMatches, 0.95),
      ...buildMatches(partialMatches, 0.75),
    ];

    // For page URLs not already covered by an image match, add them
    // with a score derived from whether any full/partial match existed
    // on this run (if yes, the page is likely hosting the same image).
    const pageScore = fullMatches.length > 0 ? 0.85 : partialMatches.length > 0 ? 0.70 : 0.60;
    const pageOnlyMatches = buildMatches(webPages, pageScore);

    // Combine: image-level matches first (higher signal), then pages.
    // Cap at 10 total to keep costs reasonable.
    const allMatches = [...imageMatches, ...pageOnlyMatches].slice(0, 10);

    console.log(`🎯 Total scored matches to evaluate: ${allMatches.length}`);

    // ===============================
    // STEP 2: Fetch image for Gemini
    // ===============================
    const base64 = await fetchImage(downloadUrl);

    // ===============================
    // STEP 3: Gemini fingerprint
    // ===============================
    const model = genai.getGenerativeModel({ model: "gemini-2.5-flash" });

    const geminiPrompt = `
You are an expert sports media analyst AI.
 
Analyze this sports image with extreme precision.
 
Return ONLY valid JSON with no markdown fences:
 
{
  "athletes": [{"name": "player name or unknown", "jersey": "number or unknown", "team": "team name or unknown"}],
  "teams": ["team1", "team2"],
  "logos": ["logo1", "logo2"],
  "sport": "football/basketball/cricket/etc",
  "event": "match/tournament name if identifiable or unknown",
  "venue": "stadium name if visible or unknown",
  "colors": ["dominant color 1", "dominant color 2"],
  "unique_features": "very specific identifying details including watermarks, scoreboard text, or sponsor boards"
}
`;

    const geminiResponse = await model.generateContent([
      {
        inlineData: {
          mimeType: "image/jpeg",
          data: base64,
        },
      },
      geminiPrompt,
    ]);

    let geminiText = geminiResponse.response.text();
    geminiText = geminiText.replace(/```json|```/g, "").trim();

    let fingerprintData;
    try {
      fingerprintData = JSON.parse(geminiText);
    } catch (err) {
      console.error("❌ Gemini JSON parse failed:", geminiText);
      throw new Error("Invalid Gemini JSON");
    }

    console.log("✅ Structured fingerprint ready");

    // ===============================
    // STEP 4: Score each match
    // ===============================
    let violationCount = 0;

    for (const match of allMatches) {
      try {
        console.log(`🔍 Scoring [score=${match.score}]: ${match.url}`);

        const result = await scoreViolation(
          {
            assetId,
            orgId,
            fingerprintText: JSON.stringify(fingerprintData),
          },
          match.url,
          match.score
        );

        if (result && result.isViolation) {
          violationCount++;
        }
      } catch (err) {
        console.error("❌ Scoring error:", err.message);
      }
    }

    // ===============================
    // STEP 5: Save asset record
    // ===============================
    await db().collection("assets").doc(assetId).update({
      status: "active",
      fingerprintText: JSON.stringify(fingerprintData),
      fingerprintData: fingerprintData,
      visionLabels: labels,
      violationCount,
      hasViolation: violationCount > 0,
      fingerprintedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`🎉 DONE: ${assetId} — violations found: ${violationCount}`);

  } catch (err) {
    console.error("❌ FAILED:", err.message);

    try {
      await db().collection("assets").doc(assetId).update({
        status: "error",
        errorMessage: err.message,
      });
    } catch { }
  }
}

// ===============================
// SAFE IMAGE FETCH
// ===============================
async function fetchImage(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Image fetch failed: ${res.status}`);

  const buffer = await res.buffer();
  if (buffer.length > 5 * 1024 * 1024) {
    throw new Error("Image too large (> 5MB)");
  }

  return buffer.toString("base64");
}

module.exports = { fingerprintImage };