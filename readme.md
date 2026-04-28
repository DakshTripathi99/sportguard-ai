# SportGuard AI:

	AI-powered sports IP protection platform — automatically detects, tracks, and reports unauthorized use of your sports media assets across the web.
	>  Note: The Video Fingerprinting feature is currently under development and is not available in the demo.
---

# What It Does:

	SportGuard AI helps sports organizations protect their digital assets (images, videos, broadcast clips) from unauthorized distribution. When an 	asset is uploaded, the system automatically fingerprints it, scans the web for matches, scores potential violations using AI, and generates legal-	grade infringement reports — all without manual intervention.
---

# Architecture Overview:

```
	Flutter App (Web/Android/iOS/Windows)
	        │
	        ▼
	Firebase Storage ──► Cloud Function: onAssetUploaded
	                                   │
	               ┌──────────────┴────────────────┐
	               ▼                               ▼
	     Pub/Sub: fingerprint-jobs       Video Fingerprint (N/A in demo)
	               │
	               ▼
	     Cloud Function: processFingerprintJob
	                  │
	     ┌─────────┴──────────┐
	     ▼                    ▼
	Cloud Vision API      Gemini 2.5 Flash
	(Web Detection)       (AI Scoring + Reports)
	     │
	     ▼
	Firestore: violations / assets / anomalyAlerts
	               │
	               ▼
	     Cloud Run Worker (full scan)
	               │
	               ▼
	     Scheduled: detectAnomalies (every 24h)
```
---

# AI & ML Stack:

Component                  |Technology			                |Why
---------		   |----------           			|---
Image Understanding	   |Gemini 2.5 Flash (Vision)			|Semantic sports context — understands athletes, teams, venues, not just pixels.
			   |						|Survives cropping, filtering, recompression.
Web Presence Detection	   |Cloud Vision API (Web Detection)	  	|Scans the entire web for copies and near-copies of a protected image
Text Embeddings	  Vertex   |AI `text-embedding-004`	     		|Enables semantic similarity matching for fingerprint text
Anomaly Detection	   |Gemini 2.5 Flash			        |Explains unusual spikes in violation counts using natural language
Report Generation	   |Gemini 2.5 Flash	                        |Produces AI-generated legal IP infringement reports

# Why Gemini for Image Understanding?
	Standard image hashing only finds exact copies. Gemini understands sports context — it recognizes athletes, venues, and branded content — so even 	modified, filtered, or low-resolution reposts are detected and correctly scored.
# Why Cloud Vision Web Detection?
	Cloud Vision indexes the open web and returns all pages where a matching image appears, with confidence levels. This gives SportGuard a broad net 	across social media, news sites, and e-commerce platforms.
---

# Project Structure
	```
	sportguard-ai/
	├──ai/
	│   ├── test_gemini.py
	│   └── test_vision.py
	├── lib/                        # Flutter app (Dart)
	│   ├── main.dart
	│   ├── firebase\_options.dart
	│   └── screens/
	│       ├── dashboard\_screen.dart
	│       ├── upload\_screen.dart
	│       ├── analytics\_screen.dart
	│       ├── assets\_violations\_screen.dart
	│       ├── violation\_detail\_screen.dart
	│       └── ...
	├── functions/                  # Firebase Cloud Functions (Node.js)
	│   ├── index.js                # Function entrypoints
	│   ├── fingerprint.js          # Image fingerprinting pipeline
	│   ├── videoFingerprint.js     # Video fingerprinting (not in demo)
	│   ├── scoring.js              # AI violation scoring + domain whitelists
	│   └── embedding.js            # Vertex AI text embedding
	├── cloud\_run\_worker/         # Cloud Run scan worker (Express + Node.js)
	│   ├── server.js
	│   └── Dockerfile
	├── firestore.rules             # Firestore security rules
	├── storage.rules               # Firebase Storage security rules
	├── firebase.json
	└── pubspec.yaml                # Flutter dependencies
	```
---

# Core Pipelines:

 1. Asset Upload & Fingerprinting
	When an asset is uploaded to Firebase Storage under `assets/{orgId}/`:
	`onAssetUploaded` Cloud Function triggers
	Asset metadata is written to Firestore with `status: "processing"`
	For images: a Pub/Sub message is published to `fingerprint-jobs`
	For videos: routed to `fingerprintVideo` (not available in demo)
	`processFingerprintJob` picks up the message and runs the full fingerprint pipeline
 2. Violation Scoring
	`fingerprint.js` + `scoring.js` implement a multi-signal scoring system:
	Full image matches → score `0.95` (near-certain copy)
	Partial matches → score `0.75` (cropped / reposted variant)
	Page-only hits → score `0.65` (flagged for Gemini review)
	Domain whitelists skip AI scoring for known legitimate sources (ESPN, BBC, FIFA, Getty, Reuters, etc.)
	Social platforms (Facebook, Twitter, Instagram) require higher combined confidence before a violation is saved
 3. Scheduled Anomaly Detection
	Every 24 hours, `detectAnomalies` runs:
	Queries all violations from the last 24 hours
	Assets with 10+ violations trigger a Gemini-generated alert
	Alerts are stored in `anomalyAlerts` collection
 4. Cloud Run Full Scan Worker
	A separate Express server deployed on Cloud Run handles bulk scanning:
	Uses Cloud Vision `webDetection` per asset
	Writes raw matches to `rawMatches` Firestore collection
	Triggered on-demand or via Cloud Scheduler
 5. Violation Report Generation
	`generateViolationReport` HTTP endpoint:
	Accepts `?assetId=...`
	Fetches asset fingerprint text + all violation URLs from Firestore
	Passes to Gemini to generate a structured legal IP infringement report
	Returns JSON with total count + report text
---

# Security:

 #Endpoint Protection
	The Cloud Run scan endpoint is protected via a shared secret (`SCAN\_SECRET`) passed in request headers
	Unauthorized requests are rejected with `401`
	In production, endpoints can be further locked down to internal services (Cloud Scheduler, Cloud Tasks) using IAM / OIDC authentication

 # API Key Handling

 Key                                  |Location                 |Notes
 ---                                  |--------                 |-----
 Firebase Web/Android/iOS (AIza...)   |Client-side config       |Safe to expose -- access is enforced by Firebase Security Rules and Auth            
 GEMINI_API_KEY                       |NOT in repo              |Managed via Firebase Secret Manager, injected as env var in Cloud Functions

 #Firestore Security Rules
	All Firestore reads and writes require authenticated users (`request.auth != null`). Rules are defined in `firestore.rules` and can be extended per-	collection for role-based access.

---

# Flutter App:

The frontend is a cross-platform Flutter app targeting Web, Android, iOS, and Windows.

 # Key screens:
	Dashboard — violations, upload asset, analytics
	Upload — upload asset available locally on your system with real-time status
	Violations — list of all violations
	Violation Detail — per-violation breakdown with match URL, confidence score, AI report, and an option to resolve the violation 
	Analytics — overview of total number of violations, assets protected, high severity violations, and resolved violations, including a graph showing 	the total violations over a week and a resolution rate progress-bar

 # Firebase packages used:
	`firebase\_core`, `firebase\_auth`, `cloud\_firestore`, `firebase\_storage`, `firebase\_messaging`
---

# Getting Started:
 # Prerequisites
	Flutter SDK `^3.11.5`
	Node.js `18+`
	Firebase CLI (`npm install -g firebase-tools`)
	A Firebase project with Firestore, Storage, Auth, and Functions enabled
 1. Clone & Install
 	```bash
	git clone https://github.com/your-org/sportguard-ai.git
	cd sportguard-ai

	Flutter dependencies
	flutter pub get

	Cloud Functions dependencies
	cd functions \&\& npm install \&\& cd ..

	Cloud Run worker dependencies
	cd cloud\_run\_worker \&\& npm install \&\& cd ..
 	```

2. Firebase Setup
	```bash
	firebase login
	firebase use --add   # select your project
	```
	Set the Gemini API key securely:
 	```bash
	firebase functions:secrets:set GEMINI\_API\_KEY
	```
	Set the Cloud Run scan secret:
 	```bash
	firebase functions:secrets:set SCAN\_SECRET
 	```
3. Pre-Deploy
	```bash
	# Fetch and download all dependencies
	flutter pub get

	# Generate a production-ready version of the flutter application 
	flutter build web --release

	# Sync the latest flutter web build to the public folder for firebase hosting
	rm -rf public/* 
	cp -r build/web/* public/
	```
4. Deploy
	```bash
	# Deploy Cloud Functions
	firebase deploy --only functions

	# Deploy Firestore rules
	firebase deploy --only firestore:rules

	# Deploy Storage rules
	firebase deploy --only storage

	# Flutter web build
	flutter build web
	firebase deploy --only hosting
	```
5. Run Locally (Flutter)
	```bash
	flutter run -d chrome   # web
	flutter run             # connected device
	```
---
# Demo Limitations

Feature	Status
	Image upload & fingerprinting	 Available
	Web violation detection		 Available
	AI violation scoring		 Available
	Anomaly detection		 Available
	Violation report generation	 Available
	Video fingerprinting	         Not available in demo

	Video fingerprinting (`videoFingerprint.js`) is implemented in the codebase but is not active in the current demo environment. Full video IP 	protection is planned for a future release.
---
# License
	Ananya Apoorva. Daksh Kumar Tripathi. Krishna Singh. All rights reserved.