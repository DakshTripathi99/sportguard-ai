# í»¡ï¸ SportGuard AI
AI-powered sports IP protection platform that detects unauthorized usage of sports media across the internet.

---

## íº€ Overview
SportGuard AI automatically scans the web to detect where uploaded sports images are being used without permission.

---

## í¿—ï¸ Architecture

- í³± Flutter Frontend â†’ Upload images
- â˜ï¸ Firebase Storage â†’ Stores assets
- âš¡ Cloud Function (onAssetUploaded) â†’ Processes uploads
- í´ Pub/Sub â†’ Triggers async jobs
- í·  Cloud Run Worker â†’ Runs image scanning
- í´ Google Vision API â†’ Reverse image detection
- í·„ï¸ Firestore â†’ Stores assets, matches, analytics
- í´” Firebase Cloud Messaging â†’ Sends alerts
- â° Cloud Scheduler â†’ Automated scans

---

## í´„ Pipeline Flow

1. User uploads image
2. Storage trigger processes asset
3. Metadata stored in Firestore
4. Pub/Sub triggers scan
5. Cloud Run scans image using Vision API
6. Matches stored in `rawMatches`
7. (Optional) Violations created â†’ notifications sent
8. Analytics aggregated periodically

---

## âš™ï¸ Setup

1. Clone repository
2. Install dependencies:
   ```bash
   cd functions
   npm install
