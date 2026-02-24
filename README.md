# VibeCheck

## Runtime feature flags

The app reads these flags from `Info.plist` (with defaults from code if missing):

- `API_BASE_URL`: backend base URL used by iOS client (`POST /v1/analyze-report`).
- `API_AUTH_TOKEN`: optional backend bearer token for app-to-backend authorization.
- `AI_IMAGE_COMPRESSION_QUALITY`: JPEG quality for upload payload (range clamped to 0.2...0.95).
- `AI_IMAGE_MAX_DIMENSION`: maximum image side before upload resize (minimum 300).

Current defaults in code are defined in:
`/Users/WorkShop/QA/Xcode/VibeCheck/VibeCheck/FeatureFlags.swift`

## Privacy and consent

- Profile data (gender, birth date, optional weight) is stored in Keychain.
- Consent is versioned and timestamped in local defaults.
- Consent is required before scan upload.
- Users can delete all local health data from Profile.

## Local mock backend

Backend mock files:
- `/Users/WorkShop/QA/Xcode/VibeCheck/backend/mock_backend.py`
- `/Users/WorkShop/QA/Xcode/VibeCheck/backend/docker-compose.yml`

Run with Python:

```bash
API_AUTH_TOKEN=dev-token BACKEND_PORT=8080 python3 /Users/WorkShop/QA/Xcode/VibeCheck/backend/mock_backend.py
```

Optional OpenRouter vision LLM mode (fallback chain):

- Primary: `nvidia/nemotron-nano-12b-v2-vl:free`
- Fallback 1: `qwen/qwen3-vl-30b-a3b-thinking`
- Fallback 2: `qwen/qwen3-vl-235b-a22b-thinking`
- Fallback 3: disabled by default (free `Gemma 3 27B` is often rate-limited upstream)
- Images are sent directly to OpenRouter vision models. OCR text in `reportText` / `ocrText` is optional and improves extraction quality on low-quality scans.

```bash
API_AUTH_TOKEN=dev-token \
OPENROUTER_API_KEY=your_openrouter_key \
OPENROUTER_PRIMARY_MODEL=nvidia/nemotron-nano-12b-v2-vl:free \
OPENROUTER_FALLBACK_MODEL=qwen/qwen3-vl-30b-a3b-thinking \
OPENROUTER_FALLBACK_MODEL_2=qwen/qwen3-vl-235b-a22b-thinking \
OPENROUTER_FALLBACK_MODEL_3='' \
OPENROUTER_MAX_TOKENS=1200 \
python3 /Users/WorkShop/QA/Xcode/VibeCheck/backend/mock_backend.py
```

Run with Docker:

```bash
cd /Users/WorkShop/QA/Xcode/VibeCheck/backend
docker compose up
```

Health check:

```bash
curl http://127.0.0.1:8080/health
```

Auth checks:

```bash
# 401 (no token)
curl -i -X POST http://127.0.0.1:8080/v1/analyze-report \
  -H 'Content-Type: application/json' \
  -d '{"images":["abc"]}'

# 403 (wrong token)
curl -i -X POST http://127.0.0.1:8080/v1/analyze-report \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer wrong-token' \
  -d '{"images":["abc"]}'

# 200 (valid token)
curl -i -X POST http://127.0.0.1:8080/v1/analyze-report \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer dev-token' \
  -d '{"images":["abc"],"profile":{"gender":"woman","ageBand":"30-39"}}'

# 200 via OpenRouter vision models (requires OPENROUTER_API_KEY; OCR text optional but recommended)
curl -i -X POST http://127.0.0.1:8080/v1/analyze-report \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer dev-token' \
  -d '{"images":["abc"],"reportText":"CBC: Hemoglobin 13.8 g/dL; Vitamin D 22 ng/mL","profile":{"gender":"woman","ageBand":"30-39"}}'
```
