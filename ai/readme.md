# SportGuard AI — AI/ML Architecture

## Why Gemini 2.5 Flash?

Gemini 2.5 Flash understands sports context — athletes, teams, venues — not just pixel patterns.

This semantic understanding survives cropping, filtering, and recompression. We use `gemini-2.5-flash` throughout the `functions/` pipeline for its balance of speed, cost, and multimodal accuracy on sports imagery.

## Why Vertex AI Matching Engine?

Standard image search only finds exact copies. Vertex AI finds similar embeddings,
meaning even a modified or low-resolution version of a protected image is found.

## Why Cloud Vision API Web Detection?

Cloud Vision scans the entire internet for copies of an image, returning a list of
all websites where that image or very similar images appear.

### Scoring note — pagesWithMatchingImages vs image-level matches

`pagesWithMatchingImages[].score` is **not** a visual similarity score and is almost
always `0` or missing. SportGuard derives match scores from `fullMatchingImages`
(score `0.95`) and `partialMatchingImages` (score `0.75`) instead. Page-only hits
receive a contextual score (`0.60–0.85`) and are confirmed or dismissed by Gemini.