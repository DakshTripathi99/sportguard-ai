const express = require('express');
const admin = require('firebase-admin');
const vision = require('@google-cloud/vision');

console.log("��� Starting full scan worker...");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const db = admin.firestore();
const visionClient = new vision.ImageAnnotatorClient();

const app = express();
app.use(express.json());

// health check
app.get('/', (req, res) => {
  res.send('Worker alive ���');
});

// MAIN SCAN ENDPOINT
app.post('/', async (req, res) => {
  try {
    console.log("��� Scan triggered");

    const assetsSnap = await db.collection('assets')
      .limit(10) // keep small for testing
      .get();

    console.log(`��� Found ${assetsSnap.size} assets`);

    for (const doc of assetsSnap.docs) {
      const asset = doc.data();
      await scanAsset(asset);
    }

    res.status(200).send('Scan complete');
  } catch (err) {
    console.error(' Scan error:', err);
    res.status(500).send('Error during scan');
  }
});

async function scanAsset(asset) {
  try {
    console.log(`��� Scanning asset: ${asset.assetId}`);

    if (!asset.uploadUrl) {
      console.log(" No uploadUrl, skipping");
      return;
    }

    const [result] = await visionClient.webDetection(asset.uploadUrl);
    const webDetection = result.webDetection;

    if (!webDetection || !webDetection.pagesWithMatchingImages) {
      console.log(" No matches found");
      return;
    }

    const matches = webDetection.pagesWithMatchingImages.map(page => ({
      url: page.url,
      score: page.score || 0.5,
    }));

    console.log(` Found ${matches.length} matches`);

    await db.collection('rawMatches').add({
      assetId: asset.assetId,
      orgId: asset.orgId,
      matches: matches,
      scannedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  } catch (err) {
    console.error(` Error scanning ${asset.assetId}:`, err);
  }
}

const PORT = process.env.PORT || 8080;

app.listen(PORT, '0.0.0.0', () => {
  console.log(`��� Server running on port ${PORT}`);
});
