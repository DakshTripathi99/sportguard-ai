const { GoogleGenerativeAI } = require("@google/generative-ai");
const admin = require("firebase-admin");

const genai = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

const db = () => admin.firestore();

// ---------------------------------------------------------------
// Domains that are always legitimate — skip AI scoring entirely.
// ---------------------------------------------------------------
const WHITELISTED_DOMAINS = [
  "espn.com",
  "fifa.com",
  "bbc.co.uk",
  "bbc.com",
  "uefa.com",
  "nba.com",
  "youtube.com",
  "youtu.be",
  "icc-cricket.com",
  "bcci.tv",
  "iplt20.com",
  "premierleague.com",
  "skysports.com",
  "cricket.com.au",
];

// ---------------------------------------------------------------
// Licensed stock/wire agencies — never violations.
// ---------------------------------------------------------------
const STOCK_DOMAINS = [
  "gettyimages.com",
  "shutterstock.com",
  "reuters.com",
  "apnews.com",
  "istockphoto.com",
  "alamy.com",
  "imago-images.de",
];

// ---------------------------------------------------------------
// Social platforms need higher combined confidence before saving.
// ---------------------------------------------------------------
const SOCIAL_DOMAINS = [
  "facebook.com",
  "instagram.com",
  "twitter.com",
  "x.com",
  "threads.net",
  "tiktok.com",
];

async function scoreViolation(asset, matchUrl, matchScore) {
  try {
    // --- Parse domain safely ---
    let domain;
    try {
      domain = new URL(matchUrl).hostname.replace(/^www\./, "");
    } catch {
      console.warn(" Invalid URL, skipping:", matchUrl);
      return null;
    }

    // --- Gate 1: Whitelisted domains ---
    if (WHITELISTED_DOMAINS.some((w) => domain.includes(w))) {
      console.log("Whitelisted:", domain);
      return null;
    }

    // --- Gate 2: Licensed stock agencies ---
    if (STOCK_DOMAINS.some((s) => domain.includes(s))) {
      console.log(" Licensed stock platform:", domain);
      return null;
    }

    const isSocial = SOCIAL_DOMAINS.some((s) => domain.includes(s));

    // ---------------------------------------------------------------
    // Gate 3: Vision score pre-filter.
    // matchScore here is set by fingerprint.js from the correct Vision
    // API fields (fullMatchingImages = 0.95, partial = 0.75, page = 0.60-0.85).
    // We only skip if the score is genuinely too low to be meaningful.
    // ---------------------------------------------------------------
    if (matchScore < 0.55) {
      console.log(` Skipped low similarity [${matchScore}]:`, domain);
      return null;
    }

    // ---------------------------------------------------------------
    // AI scoring via Gemini
    // ---------------------------------------------------------------
    const model = genai.getGenerativeModel({ model: "gemini-2.5-flash" });

    const prompt = `
You are an AI that detects UNAUTHORIZED use of sports media content.
 
CLASSIFICATION RULES:
- Official stock platforms (Getty, Shutterstock, Reuters, AP, Alamy) → NOT a violation
- Official team, league, or governing body websites → NOT a violation
- Major licensed sports broadcasters (ESPN, BBC Sport, Sky Sports, Willow TV) → NOT a violation
- Official social accounts of teams/leagues/players → NOT a violation (confidence ≤ 0.4)
- Unknown or unofficial websites reposting sports content without clear attribution → violation (confidence 0.85+)
- Random blogs, aggregators, or piracy sites → violation (confidence 0.90+)
- Social media accounts that are clearly unofficial fan pages reposting copyrighted content → violation (confidence 0.80+)
- News websites that are NOT major outlets (local blogs, tabloids) using the image without a license → violation (confidence 0.75+)
 
CONTEXT:
Original image fingerprint (athlete, team, logos, event):
${asset.fingerprintText}
 
URL where this image was found:
${matchUrl}
 
Domain:
${domain}
 
Vision API similarity score (0 to 1, higher = stronger visual match):
${matchScore}
 
Return ONLY valid JSON with no markdown fences or extra text:
{
  "isUnauthorized": true or false,
  "confidence": <number 0.0 to 1.0>,
  "reason": "<one short sentence>",
  "severity": "low" or "medium" or "high"
}
`;

    const response = await model.generateContent(prompt);
    let text = response.response.text();
    text = text.replace(/```json|```/g, "").trim();

    let scoring;
    try {
      scoring = JSON.parse(text);
    } catch (err) {
      console.error(" Gemini JSON parse failed:", text);
      return null;
    }

    console.log(` AI Decision [${domain}]:`, scoring);

    // ---------------------------------------------------------------
    // Combined score = blend of Vision similarity + Gemini confidence.
    // Vision score tells us HOW SIMILAR the image is visually.
    // Gemini confidence tells us HOW LIKELY it is unauthorized.
    // Both signals are needed to avoid false positives.
    // ---------------------------------------------------------------
    const combinedScore = matchScore * 0.45 + scoring.confidence * 0.55;

    // Social platforms need a higher bar to reduce noise.
    const threshold = isSocial ? 0.78 : 0.65;

    console.log(
      ` Scores — vision: ${matchScore}, ai: ${scoring.confidence}, combined: ${combinedScore.toFixed(3)}, threshold: ${threshold}`
    );

    if (!scoring.isUnauthorized || combinedScore < threshold) {
      console.log(` Below threshold or not unauthorized — skipping:`, domain);
      return { isViolation: false, ...scoring };
    }

    // ---------------------------------------------------------------
    // Save violation
    // ---------------------------------------------------------------
    await db().collection("violations").add({
      assetId: asset.assetId,
      orgId: asset.orgId,
      matchUrl,
      matchDomain: domain,
      visionScore: matchScore,
      similarityScore: parseFloat(combinedScore.toFixed(3)),
      aiConfidence: scoring.confidence,
      severity: scoring.severity,
      reason: scoring.reason,
      geminiExplanation: scoring.reason,
      isSocialMedia: isSocial,
      status: "unresolved",
      detectedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(" Violation saved:", domain, `(combined: ${combinedScore.toFixed(3)})`);

    return { isViolation: true, ...scoring, combinedScore };

  } catch (error) {
    console.error(" Scoring failed:", error.message);
    return null;
  }
}

module.exports = { scoreViolation };