const { GoogleGenerativeAI } = require("@google/generative-ai");
const admin = require("firebase-admin");

const genai = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

// LAZY DB
const db = () => admin.firestore();

// Trusted domains (skip completely)
const WHITELISTED_DOMAINS = [
  "espn.com",
  "fifa.com",
  "bbc.co.uk",
  "uefa.com",
  "nba.com",
  "youtube.com",
  "youtu.be"
];

// Stock / licensed platforms
const STOCK_DOMAINS = [
  "gettyimages.com",
  "shutterstock.com",
  "reuters.com",
  "apnews.com",
];

async function scoreViolation(asset, matchUrl, matchScore) {
  try {
    const domain = new URL(matchUrl).hostname;

    // ===============================
    // STEP 1: Skip trusted domains
    // ===============================
    if (WHITELISTED_DOMAINS.some((w) => domain.includes(w))) {
      console.log("✅ Whitelisted:", domain);
      return null;
    }

    // ===============================
    // STEP 2: Skip licensed platforms
    // ===============================
    if (STOCK_DOMAINS.some((s) => domain.includes(s))) {
      console.log("✅ Licensed platform:", domain);
      return null;
    }

    // ===============================
    // STEP 3: Gemini evaluation (FIXED PROMPT)
    // ===============================
    const model = genai.getGenerativeModel({
      model: "gemini-2.5-flash",
    });

    const prompt = `
You are an AI that detects UNAUTHORIZED use of sports media.

STRICT RULES (FOLLOW CAREFULLY):

- YouTube, Instagram, Facebook → usually NOT violations unless clearly pirated
- Official sports/news platforms (ESPN, BBC, FIFA, UEFA) → NOT violations
- Licensed platforms (Getty, Reuters, Shutterstock) → NOT violations
- Blogs, unknown domains, piracy sites → LIKELY violations

IMPORTANT:
Be CONSERVATIVE.
If unsure → return isUnauthorized = false.

Only mark as violation if HIGH confidence (>0.75).

ORIGINAL IMAGE DATA:
${asset.fingerprintText}

MATCH URL:
${matchUrl}

DOMAIN:
${domain}

SIMILARITY SCORE:
${matchScore}

Return ONLY JSON:

{
  "isUnauthorized": true or false,
  "confidence": number between 0 and 1,
  "reason": "short explanation",
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
      console.error("❌ JSON parse failed:", text);
      return null;
    }

    console.log("🧠 AI Decision:", scoring);

    // ===============================
    // STEP 4: EXTRA SAFETY FILTER (CRITICAL)
    // ===============================
    if (
      (domain.includes("youtube.com") ||
        domain.includes("instagram.com") ||
        domain.includes("facebook.com")) &&
      scoring.confidence < 0.85
    ) {
      console.log("⚠️ Social media filtered:", domain);
      return null;
    }

    // ===============================
    // STEP 5: Save violation
    // ===============================
    if (scoring.isUnauthorized && scoring.confidence > 0.75) {
      await db().collection("violations").add({
        assetId: asset.assetId,
        orgId: asset.orgId,
        matchUrl,
        matchDomain: domain,
        similarityScore: scoring.confidence,
        severity: scoring.severity,
        reason: scoring.reason,
        geminiExplanation: scoring.reason,
        status: "unresolved",
        detectedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log("🚨 Violation saved:", domain);
    }

    return scoring;

  } catch (error) {
    console.error("❌ Scoring failed:", error.message);
    return null;
  }
}

module.exports = { scoreViolation };