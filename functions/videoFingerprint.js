const videoIntelligence = require("@google-cloud/video-intelligence");
const admin = require("firebase-admin");

const videoClient = new videoIntelligence.VideoIntelligenceServiceClient();
const db = () => admin.firestore();

async function fingerprintVideo(assetId, videoUrl) {
  console.log(" Starting video fingerprint:", assetId);

  try {
    const [operation] = await videoClient.annotateVideo({
      inputUri: videoUrl,
      features: [
        "LABEL_DETECTION",
        "LOGO_RECOGNITION",
        "SHOT_CHANGE_DETECTION",
      ],
    });

    console.log(" Processing video...");

    const [result] = await operation.promise();

    const annotations = result.annotationResults[0];

    const logos =
      annotations.logoRecognitionAnnotations?.map(
        (l) => l.entity.description
      ) || [];

    const labels =
      annotations.segmentLabelAnnotations?.map(
        (l) => l.entity.description
      ) || [];

    const shots = annotations.shotAnnotations || [];

    console.log("Shots:", shots.length);

    //  SAVE RESULT (CRITICAL)
    await db().collection("assets").doc(assetId).update({
      status: "active",
      videoLabels: labels,
      videoLogos: logos,
      shotCount: shots.length,
      fingerprintedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(" Video fingerprint saved:", assetId);

  } catch (err) {
    console.error(" Video fingerprint failed:", err.message);

    await db().collection("assets").doc(assetId).update({
      status: "error",
      errorMessage: err.message,
    });
  }
}

module.exports = { fingerprintVideo };