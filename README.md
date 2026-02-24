# LabLens

AI-powered iOS app for scanning lab reports (PDF/photo), extracting biomarkers, generating a health summary, and producing supplement recommendations.

## Application Preview

<p align="left">
  <img src="https://github.com/Dobryev-qa/BrainFlow/blob/main/App_preview/disclaimer.png" width="180"/>
  <img src="https://github.com/Dobryev-qa/BrainFlow/blob/main/App_preview/aboutyou.png" width="180"/>
  <img src="https://github.com/Dobryev-qa/BrainFlow/blob/main/App_preview/scan.png" width="180"/>
  <img src="https://github.com/Dobryev-qa/BrainFlow/blob/main/App_preview/ai.png" width="180"/>
</p>

<p align="left">
  <img src="https://github.com/Dobryev-qa/BrainFlow/blob/main/App_preview/result.png" width="180"/>
  <img src="https://github.com/Dobryev-qa/BrainFlow/blob/main/App_preview/biomarket.png" width="180"/>
  <img src="https://github.com/Dobryev-qa/BrainFlow/blob/main/App_preview/history.png" width="180"/>
  <img src="https://github.com/Dobryev-qa/BrainFlow/blob/main/App_preview/profile.png" width="180"/>
</p>

---

## Features

- PDF and photo lab report scanning
- On-device OCR (Apple Vision)
- Hybrid AI analysis (OCR + vision)
- Biomarker extraction into structured results
- AI-generated summary and supplement recommendations
- Local scan history with detail view
- Profile-based personalization (gender / age / weight)
- Debug export of rendered PDF pages and stitched images

## Stack

- iOS: SwiftUI + SwiftData
- OCR: Apple Vision
- PDF rendering: PDFKit
- Backend: Python (`backend/mock_backend.py`)
- AI provider: OpenRouter (vision + text fallback chain)

## Runtime Feature Flags (iOS)

The app reads these values from `Info.plist` / build config:

- `API_BASE_URL` — backend base URL (`POST /v1/analyze-report`)
- `API_AUTH_TOKEN` — bearer token for app -> backend auth
- `AI_IMAGE_COMPRESSION_QUALITY` — JPEG compression for uploads
- `AI_IMAGE_MAX_DIMENSION` — image resize cap before upload

Defaults are configured in:

- `Config.xcconfig`
- `VibeCheck/FeatureFlags.swift`

## Privacy and Consent

- Profile data (gender, birth date, optional weight) is stored locally (Keychain-backed store)
- Consent is versioned and timestamped locally
- Consent is required before uploads
- Users can delete all local health data from Profile

## Local Development

### 1. Start backend

Run from project root:

```bash
API_AUTH_TOKEN=dev-token \
OPENROUTER_API_KEY=YOUR_OPENROUTER_KEY \
AI_PROVIDER=openrouter \
AI_VISUAL_ONLY_MODE=false \
AI_OCR_ONLY_MODE=false \
OPENROUTER_PRIMARY_MODEL='nvidia/nemotron-nano-12b-v2-vl:free' \
OPENROUTER_FALLBACK_MODEL='qwen/qwen3-vl-30b-a3b-thinking' \
OPENROUTER_FALLBACK_MODEL_2='qwen/qwen3-vl-235b-a22b-thinking' \
OPENROUTER_FALLBACK_MODEL_3='google/gemma-3-27b-it:free' \
python3 backend/mock_backend.py
```

Alternative (from backend directory):

```bash
cd backend
API_AUTH_TOKEN=dev-token \
OPENROUTER_API_KEY=YOUR_OPENROUTER_KEY \
python3 mock_backend.py
```

Health check:

```bash
curl http://127.0.0.1:8080/health
```

Expected response:

```json
{"status":"ok"}
```

### 2. Run iOS app

- Open `VibeCheck.xcodeproj` in Xcode
- Run the `VibeCheck` scheme
- App display name on device/simulator is `LabLens`

## Backend Model Chain (OpenRouter)

Current recommended chain:

1. `nvidia/nemotron-nano-12b-v2-vl:free`
2. `qwen/qwen3-vl-30b-a3b-thinking`
3. `qwen/qwen3-vl-235b-a22b-thinking`
4. `google/gemma-3-27b-it:free` (text-oriented fallback using OCR context)

## Scan Pipeline (Current)

1. User imports PDF or photo
2. PDF pages render to images
3. Pages are stitched into ordered overlapping groups (to preserve cross-page context)
4. OCR runs on-device (Apple Vision)
5. App sends:
   - stitched images
   - `reportText`
   - `reportTextByPage`
   - `stitchedPageGroups`
6. Backend runs hybrid extraction (vision + OCR)
7. Backend may run:
   - completeness retry
   - reconciliation pass (dedupe / missed rows / corrections)
   - final summary + recommendation synthesis pass
8. App renders `Summary`, `Recommendations`, `Biomarkers`

## Debug Output (PDF Rendering / Stitching)

The app can export debug images in the app container:

- `Documents/PDFRenderDebug/...` — raw rendered PDF pages
- `Documents/PDFStitchedDebug/...` — stitched image groups sent to AI

Useful for verifying:

- page order
- stitch grouping
- content loss during render/stitch

## API Quick Checks

```bash
# 401 (missing token)
curl -i -X POST http://127.0.0.1:8080/v1/analyze-report \
  -H 'Content-Type: application/json' \
  -d '{"images":["abc"]}'

# 403 (wrong token)
curl -i -X POST http://127.0.0.1:8080/v1/analyze-report \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer wrong-token' \
  -d '{"images":["abc"]}'

# Valid request (requires backend + OpenRouter key configured)
curl -i -X POST http://127.0.0.1:8080/v1/analyze-report \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer dev-token' \
  -d '{"images":["abc"],"reportText":"CBC: Hemoglobin 13.8 g/dL; Vitamin D 22 ng/mL","profile":{"gender":"woman","ageBand":"30-39"}}'
```

## Known Limitations

- Free vision endpoints can be slow / unstable (timeouts, invalid JSON, incomplete extraction)
- Local development requires backend to be running
- Large PDFs increase latency significantly

## Recommended Production Direction

- Always use hybrid mode (OCR + vision)
- Enable second pass only when needed (low completeness / long reports / many unknowns)
- Enforce page limit (e.g. 8 pages)
- Track extraction metrics (`raw_count`, `deduped_count`, `reconciled_count`, `unknown_count`)

## Security

- Do not commit API keys
- Use environment variables for secrets
- Rotate keys if exposed

## Disclaimer

This app does not provide medical diagnosis or treatment. Results and recommendations are informational only and should be reviewed with a licensed healthcare professional.

