const { onRequest } = require("firebase-functions/v2/https");

exports.helloWorld = onRequest((req, res) => {
  res.send("SportGuard AI backend is alive íº€");
});
