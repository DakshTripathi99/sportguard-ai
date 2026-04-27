const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const pubsub = require("firebase-functions/v2/pubsub");

const admin = require("firebase-admin");
const { PubSub } = require("@google-cloud/pubsub");
const { GoogleGenerativeAI } = require("@google/generative-ai");

const { fingerprintImage } = require("./fingerprint");
const { fingerprintVideo } = require("./videoFingerprint");

admin.initializeApp();

const db = admin.firestore();
const ps = new PubSub();

exports.onAssetUploaded = onObjectFinalized(
  { region: "us-central1" },
  async (event) => {
    try {
      const object = event.data;
      const filePath = object.name;

      if (!filePath || !filePath.startsWith("assets/")) return;

      const parts = filePath.split("/");
      const orgId = parts[1];

      const assetId = Date.now().toString();

      const bucket = admin.storage().bucket(object.bucket);
      const file = bucket.file(filePath);

      const [url] = await file.getSignedUrl({
        action: "read",
        expires: "03-09-2491",
      });

      await db.collection("assets").doc(assetId).set({
        assetId,
        orgId,
        uploadUrl: url,
        filePath,
        contentType: object.contentType,
        status: "processing",
        hasViolation: false,
        violationCount: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (object.contentType?.startsWith("video/")) {
        const gcsUri = `gs://${object.bucket}/${filePath}`;
        await fingerprintVideo(assetId, gcsUri);
      } else {
        await ps.topic("fingerprint-jobs").publish(
          Buffer.from(JSON.stringify({ assetId, downloadUrl: url }))
        );
      }

    } catch (err) {
      console.error("Upload error:", err.message);
    }
  }
);

exports.processFingerprintJob = pubsub.onMessagePublished(
  {
    topic: "fingerprint-jobs",
    region: "us-central1",
    secrets: ["GEMINI_API_KEY"],
  },
  async (event) => {
    const message = JSON.parse(
      Buffer.from(event.data.message.data, "base64").toString()
    );

    await fingerprintImage(message.assetId, message.downloadUrl);
  }
);

exports.detectAnomalies = onSchedule(
  { schedule: "every 24 hours", secrets: ["GEMINI_API_KEY"] },
  async () => {
    const yesterday = new Date(Date.now() - 86400000);

    const snapshot = await db
      .collection("violations")
      .where("detectedAt", ">=", yesterday)
      .get();

    const counts = {};
    snapshot.forEach(doc => {
      const v = doc.data();
      counts[v.assetId] = (counts[v.assetId] || 0) + 1;
    });

    const genai = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genai.getGenerativeModel({ model: "gemini-2.5-flash" });

    for (const [assetId, count] of Object.entries(counts)) {
      if (count >= 10) {
        const res = await model.generateContent(
          `Asset ${assetId} appeared ${count} times in 24h. Explain briefly.`
        );

        await db.collection("anomalyAlerts").add({
          assetId,
          violationCount: count,
          alertMessage: res.response.text(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    return null;
  }
);

exports.generateViolationReport = onRequest(async (req, res) => {
  const assetId = req.query.assetId;

  const violationsSnap = await db
    .collection("violations")
    .where("assetId", "==", assetId)
    .get();

  const violations = violationsSnap.docs.map(d => d.data());

  const assetDoc = await db.collection("assets").doc(assetId).get();
  const asset = assetDoc.data();

  const genai = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genai.getGenerativeModel({ model: "gemini-2.5-flash" });

  const response = await model.generateContent(`
Generate a legal IP infringement report.

Asset:
${asset?.fingerprintText}

Violations: ${violations.length}

URLs:
${violations.slice(0, 5).map(v => v.matchUrl).join("\n")}
  `);

  res.json({
    assetId,
    totalViolations: violations.length,
    report: response.response.text(),
  });
});
