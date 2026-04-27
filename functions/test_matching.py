from google.cloud import aiplatform

# Initialize
aiplatform.init(
    project="sportguard-ai-7a73a",
    location="us-central1"
)

index = aiplatform.MatchingEngineIndex(
    "projects/1010188362147/locations/us-central1/indexes/2722208271443165184"
)

# Create fake vector
fake_vector = [0.1] * 768

#  Correct way (NEW SDK)
index.upsert_datapoints(
    datapoints=[
        {
            "datapoint_id": "test-asset-001",
            "feature_vector": fake_vector,
        }
    ]
)

print("✅ Datapoint inserted! Matching Engine is working.")