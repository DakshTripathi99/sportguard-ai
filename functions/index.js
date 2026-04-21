const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();
// Your functions will go here
exports.helloWorld = functions.https.onRequest((req, res) => {
  res.send('SportGuard AI backend is running!');
});

