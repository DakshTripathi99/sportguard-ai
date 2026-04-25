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
    // STEP 1: Vision
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

    const webMatches =
      visionResult.webDetection?.pagesWithMatchingImages || [];

    console.log("🌐 Matches:", webMatches.length);

    // ===============================
    // STEP 2: Fetch image
    // ===============================
    const base64 = await fetchImage(downloadUrl);

    // ===============================
    // STEP 3: Gemini (STRUCTURED)
    // ===============================
    const model = genai.getGenerativeModel({
      model: "gemini-2.5-flash",
    });

    const geminiPrompt = `
You are an expert sports media analyst AI.

Analyze this sports image with extreme precision.

Return ONLY JSON:

{
  "athletes": [{"name": "player name or unknown", "jersey": "number", "team": "team name"}],
  "teams": ["team1", "team2"],
  "logos": ["logo1", "logo2"],
  "sport": "football/basketball/cricket/etc",
  "event": "match/tournament name if identifiable",
  "venue": "stadium name if visible",
  "colors": ["dominant color 1", "dominant color 2"],
  "unique_features": "very specific identifying details"
}
`;

    const response = await model.generateContent([
      {
        inlineData: {
          mimeType: "image/jpeg",
          data: base64,
        },
      },
      geminiPrompt,
    ]);

    let text = response.response.text();
    text = text.replace(/```json|```/g, "").trim();

    let fingerprintData;
    try {
      fingerprintData = JSON.parse(text);
    } catch (err) {
      console.error("❌ JSON parse failed:", text);
      throw new Error("Invalid Gemini JSON");
    }

    console.log("✅ Structured fingerprint ready");

    // ===============================
    // STEP 4: Scoring
    // ===============================
    for (const page of webMatches.slice(0, 5)) {
      try {
        await scoreViolation(
          {
            assetId,
            orgId,
            fingerprintText: JSON.stringify(fingerprintData),
          },
          page.url,
          page.score || 0.5
        );
      } catch (err) {
        console.error("❌ Scoring error:", err.message);
      }
    }

    // ===============================
    // STEP 5: Save
    // ===============================
    await db().collection("assets").doc(assetId).update({
      status: "active",
      fingerprintText: JSON.stringify(fingerprintData),
      fingerprintData: fingerprintData,
      visionLabels: labels,
      fingerprintedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("🎉 DONE:", assetId);

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
// SAFE FETCH
// ===============================
async function fetchImage(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error("Image fetch failed");

  const buffer = await res.buffer();
  if (buffer.length > 5 * 1024 * 1024) {
    throw new Error("Image too large");
  }

  return buffer.toString("base64");
}

module.exports = { fingerprintImage };