const videoIntelligence = require("@google-cloud/video-intelligence");

const videoClient = new videoIntelligence.VideoIntelligenceServiceClient();

async function fingerprintVideo(assetId, videoUrl) {
  console.log("í¾¥ Video fingerprint:", assetId);

  const [operation] = await videoClient.annotateVideo({
    inputUri: videoUrl,
    features: [
      "LABEL_DETECTION",
      "LOGO_RECOGNITION",
      "SHOT_CHANGE_DETECTION",
    ],
  });

  console.log("â³ Processing video...");
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

  console.log("í¾¬ Shots:", shots.length);

  return { logos, labels, shotCount: shots.length };
}

module.exports = { fingerprintVideo };
