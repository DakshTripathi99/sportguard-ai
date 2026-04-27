const { PredictionServiceClient } = require("@google-cloud/aiplatform");

const client = new PredictionServiceClient({
  apiEndpoint: "us-central1-aiplatform.googleapis.com",
});

async function getTextEmbedding(text) {
  const endpoint = `projects/sportguard-ai-7a73a/locations/us-central1/publishers/google/models/text-embedding-004`;

  const request = {
    endpoint,
    instances: [
      {
        content: text, //  THIS IS CRITICAL
      },
    ],
  };

  const [response] = await client.predict(request);

  const embedding = response.predictions[0].embeddings.values;

  console.log("Embedding size:", embedding.length);

  return embedding;
}

module.exports = { getTextEmbedding };
