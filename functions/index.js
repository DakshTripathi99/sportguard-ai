// ===============================
// IMPORTS
// ===============================
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


// ===============================
//  STORAGE TRIGGER (IMAGE + VIDEO)
// ===============================
exports.onAssetUploaded = onObjectFinalized(
  {
    region: "us-central1",
    memory: "512MiB",
  },
  async (event) => {
    try {
      const object = event.data;
      const filePath = object.name;

      if (!filePath || !filePath.startsWith("assets/")) return;

      const parts = filePath.split("/");
      const orgId = parts[1];
      const fileName = parts[2];

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
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(" Upload detected:", object.contentType);

      // ===============================
      //  VIDEO vs IMAGE ROUTING
      // ===============================
      if (object.contentType && object.contentType.startsWith("video/")) {
        console.log(" Processing VIDEO");

        // Use GCS path (required for Video API)
        const gcsUri = `gs://${object.bucket}/${filePath}`;

        await fingerprintVideo(assetId, gcsUri);

      } else {
        console.log(" Processing IMAGE");

        await ps.topic("fingerprint-jobs").publish(
          Buffer.from(
            JSON.stringify({
              assetId,
              downloadUrl: url,
            })
          )
        );
      }

      console.log(" Pipeline triggered:", assetId);

    } catch (error) {
      console.error(" Upload error:", error.message);
    }
  }
);


// ===============================
//  PUBSUB WORKER (IMAGE)
// ===============================
exports.processFingerprintJob = pubsub.onMessagePublished(
  {
    topic: "fingerprint-jobs",
    region: "us-central1",
    memory: "1GiB",
    timeoutSeconds: 120,
    secrets: ["GEMINI_API_KEY"],
  },
  async (event) => {
    try {
      const message = JSON.parse(
        Buffer.from(event.data.message.data, "base64").toString()
      );

      console.log(" PubSub triggered (IMAGE)");

      await fingerprintImage(message.assetId, message.downloadUrl);

      console.log(" Image processing done");

    } catch (error) {
      console.error(" Fingerprint job error:", error.message);
    }
  }
);


// ===============================
//  ANOMALY DETECTION (CRON)
// ===============================
exports.detectAnomalies = onSchedule(
  {
    schedule: "every 24 hours",
    region: "us-central1",
    secrets: ["GEMINI_API_KEY"],
  },
  async () => {
    try {
      const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);

      const snapshot = await db
        .collection("violations")
        .where("detectedAt", ">=", yesterday)
        .get();

      const counts = {};

      snapshot.forEach((doc) => {
        const v = doc.data();
        counts[v.assetId] = (counts[v.assetId] || 0) + 1;
      });

      const genai = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
      const model = genai.getGenerativeModel({
        model: "gemini-2.5-flash",
      });

      for (const [assetId, count] of Object.entries(counts)) {
        if (count >= 10) {
          const response = await model.generateContent(`
A sports asset (ID: ${assetId}) appeared on ${count} websites in 24 hours.

Explain briefly why this is suspicious and what it indicates.
(2 sentences max)
          `);

          await db.collection("anomalyAlerts").add({
            assetId,
            violationCount: count,
            alertMessage: response.response.text(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          console.log(" Anomaly detected:", assetId);
        }
      }

    } catch (err) {
      console.error(" Anomaly error:", err.message);
    }

    return null;
  }
);


// ===============================
//  REPORT GENERATOR
// ===============================
exports.generateViolationReport = onRequest(
  {
    region: "us-central1",
    secrets: ["GEMINI_API_KEY"],
  },
  async (req, res) => {
    try {
      const assetId = req.query.assetId;

      if (!assetId) {
        res.status(400).send("assetId required");
        return;
      }

      const violationsSnap = await db
        .collection("violations")
        .where("assetId", "==", assetId)
        .get();

      const violations = violationsSnap.docs.map((d) => d.data());

      const assetDoc = await db.collection("assets").doc(assetId).get();
      const asset = assetDoc.data();

      if (!asset) {
        res.status(404).send("Asset not found");
        return;
      }

      const genai = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
      const model = genai.getGenerativeModel({
        model: "gemini-2.5-flash",
      });

      const reportPrompt = `
You are a legal AI assistant.

Generate a professional IP infringement report.

ASSET:
${asset.fingerprintText || "No fingerprint available"}

TOTAL VIOLATIONS: ${violations.length}

TOP URLS:
${violations.slice(0, 5).map(v => v.matchUrl).join("\n")}

Write a 3-paragraph legal report suitable for DMCA/legal action.
      `;

      const response = await model.generateContent(reportPrompt);

      res.json({
        assetId,
        totalViolations: violations.length,
        report: response.response.text(),
      });

    } catch (err) {
      console.error(" Report error:", err.message);
      res.status(500).send("Error generating report");
    }
  }
);


// ===============================
//  MANUAL TEST
// ===============================
exports.triggerManualScan = onRequest(async (req, res) => {
  await ps.topic("fingerprint-jobs").publish(
    Buffer.from(
      JSON.stringify({
        assetId: "manual",
        downloadUrl: "https://via.placeholder.com/300",
      })
    )
  );

  res.json({ success: true });
});