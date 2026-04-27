const express = require('express');
const admin = require('firebase-admin');
const vision = require('@google-cloud/vision');

console.log(" Starting full scan worker...");

// Init Firebase
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const db = admin.firestore();
const visionClient = new vision.ImageAnnotatorClient();

const app = express();
app.use(express.json());

//  AUTH MIDDLEWARE
function requireSecret(req, res, next) {
  const secret = process.env.WORKER_SECRET;

  if (!secret) {
    console.error(" WORKER_SECRET not set");
    return res.status(200).send("OK"); // never fail scheduler
  }

  const authHeader = req.headers['authorization'] || '';

  if (authHeader !== `Bearer ${secret}`) {
    console.warn(" Unauthorized request");
    return res.status(200).send("OK"); // don't fail scheduler
  }

  next();
}

//  Health check
app.get('/', (req, res) => {
  res.send('Worker alive ');
});

//  MAIN ENDPOINT (FIXED)
app.post('/', requireSecret, async (req, res) => {
  console.log(" Scan triggered");

  try {
    const assetsSnap = await db.collection('assets').limit(10).get();

    console.log(` Found ${assetsSnap.size} assets`);

    for (const doc of assetsSnap.docs) {
      try {
        await scanAsset(doc.data());
      } catch (e) {
        console.error(" Asset error:", e.message);
      }
    }

  } catch (err) {
    console.error(' Scan error:', err);
  }

  //  ALWAYS SUCCESS
  return res.status(200).send('OK');
});

//  SCAN LOGIC
async function scanAsset(asset) {
  try {
    console.log(`Scanning asset: ${asset.assetId}`);

    if (!asset.uploadUrl) {
      console.log(" No uploadUrl, skipping");
      return;
    }

    const [result] = await visionClient.annotateImage({
      image: { source: { imageUri: asset.uploadUrl } },
      features: [{ type: 'WEB_DETECTION', maxResults: 10 }],
    });

    const webDetection = result.webDetection;

    if (!webDetection) {
      console.log(" No webDetection");
      return;
    }

    const fullMatches = webDetection.fullMatchingImages || [];
    const partialMatches = webDetection.partialMatchingImages || [];
    const webPages = webDetection.pagesWithMatchingImages || [];

    const seen = new Set();

    const build = (items, score) =>
      items
        .filter(i => i.url && !seen.has(i.url))
        .map(i => {
          seen.add(i.url);
          return { url: i.url, score };
        });

    const matches = [
      ...build(fullMatches, 0.95),
      ...build(partialMatches, 0.75),
      ...build(
        webPages,
        fullMatches.length > 0 ? 0.85 :
          partialMatches.length > 0 ? 0.70 : 0.60
      )
    ].slice(0, 10);

    console.log(` Found ${matches.length} matches`);

    await db.collection('rawMatches').add({
      assetId: asset.assetId,
      orgId: asset.orgId,
      matches,
      scannedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  } catch (err) {
    console.error(` Error scanning ${asset.assetId}:`, err.message);
  }
}

//  START SERVER
const PORT = process.env.PORT || 8080;

app.listen(PORT, '0.0.0.0', () => {
  console.log(` Server running on port ${PORT}`);
});