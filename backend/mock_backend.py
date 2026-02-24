#!/usr/bin/env python3
import json
import os
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.getenv("BACKEND_HOST", "127.0.0.1")
PORT = int(os.getenv("BACKEND_PORT", "8080"))
REQUIRE_AUTH = os.getenv("API_REQUIRE_AUTH", "true").lower() == "true"
AUTH_TOKEN = os.getenv("API_AUTH_TOKEN", "dev-token")
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()
OPENROUTER_URL = os.getenv("OPENROUTER_URL", "https://openrouter.ai/api/v1/chat/completions")
OPENROUTER_PRIMARY_MODEL = os.getenv("OPENROUTER_PRIMARY_MODEL", "nvidia/nemotron-nano-12b-v2-vl:free")
OPENROUTER_FALLBACK_MODEL = os.getenv("OPENROUTER_FALLBACK_MODEL", "qwen/qwen3-vl-30b-a3b-thinking")
OPENROUTER_FALLBACK_MODEL_2 = os.getenv("OPENROUTER_FALLBACK_MODEL_2", "qwen/qwen3-vl-235b-a22b-thinking")
# Text fallback (uses OCR text as primary source if vision models fail).
OPENROUTER_FALLBACK_MODEL_3 = os.getenv("OPENROUTER_FALLBACK_MODEL_3", "google/gemma-3-27b-it:free")
OPENROUTER_APP_NAME = os.getenv("OPENROUTER_APP_NAME", "LabLens")
OPENROUTER_APP_URL = os.getenv("OPENROUTER_APP_URL", "https://example.com")
OPENROUTER_MAX_TOKENS = int(os.getenv("OPENROUTER_MAX_TOKENS", "2400"))
OPENROUTER_TIMEOUT_SECONDS = int(os.getenv("OPENROUTER_TIMEOUT_SECONDS", "180"))
OPENROUTER_PAGE_BATCH_SIZE = max(1, int(os.getenv("OPENROUTER_PAGE_BATCH_SIZE", "2")))
OPENROUTER_MIN_BIOMARKERS_PER_IMAGE_HINT = max(1, int(os.getenv("OPENROUTER_MIN_BIOMARKERS_PER_IMAGE_HINT", "2")))
OPENROUTER_ENABLE_RECONCILIATION = os.getenv("OPENROUTER_ENABLE_RECONCILIATION", "true").lower() == "true"
AI_OCR_ONLY_MODE = os.getenv("AI_OCR_ONLY_MODE", "false").lower() == "true"
AI_VISUAL_ONLY_MODE = os.getenv("AI_VISUAL_ONLY_MODE", "false").lower() == "true"

AI_PROVIDER = os.getenv("AI_PROVIDER", "openrouter").strip().lower()  # openrouter | qwen
QWEN_API_KEY = os.getenv("QWEN_API_KEY", os.getenv("DASHSCOPE_API_KEY", "")).strip()
QWEN_URL = os.getenv(
    "QWEN_URL",
    "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
)
QWEN_PRIMARY_MODEL = os.getenv("QWEN_PRIMARY_MODEL", "qwen-vl-max-latest").strip()
QWEN_FALLBACK_MODEL = os.getenv("QWEN_FALLBACK_MODEL", "qwen-vl-plus-latest").strip()
QWEN_FALLBACK_MODEL_2 = os.getenv("QWEN_FALLBACK_MODEL_2", "qwen2.5-vl-72b-instruct").strip()
QWEN_FALLBACK_MODEL_3 = os.getenv("QWEN_FALLBACK_MODEL_3", "").strip()


def _extract_report_text(payload: dict) -> str:
    for key in ("reportText", "report_text", "ocrText", "ocr_text"):
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _extract_report_text_by_page(payload: dict) -> list[dict]:
    for key in ("reportTextByPage", "report_text_by_page", "ocrTextByPage", "ocr_text_by_page"):
        value = payload.get(key)
        if not isinstance(value, list):
            continue
        pages = []
        for item in value:
            if not isinstance(item, dict):
                continue
            try:
                page = int(item.get("page"))
            except Exception:
                continue
            text = item.get("text")
            if page <= 0 or not isinstance(text, str) or not text.strip():
                continue
            pages.append({"page": page, "text": text.strip()})
        if pages:
            pages.sort(key=lambda x: x["page"])
            return pages
    return []


def _extract_stitched_page_groups(payload: dict) -> list[list[int]]:
    for key in ("stitchedPageGroups", "stitched_page_groups", "pageGroups", "page_groups"):
        value = payload.get(key)
        if not isinstance(value, list):
            continue
        groups = []
        for group in value:
            if not isinstance(group, list):
                continue
            ints = []
            for p in group:
                try:
                    v = int(p)
                except Exception:
                    continue
                if v > 0:
                    ints.append(v)
            if ints:
                groups.append(sorted(set(ints)))
        if groups:
            return groups
    return []


def _mock_analysis_response() -> dict:
    return {
        "biomarkers": [
            {
                "name": "Hemoglobin",
                "value": "13.8 g/dL",
                "status": "Optimal",
                "explanation": "Hemoglobin is within the expected range.",
            },
            {
                "name": "Vitamin D",
                "value": "22 ng/mL",
                "status": "Low",
                "explanation": "Vitamin D is below optimal range.",
            },
        ],
        "recommendations": [
            {
                "name": "Vitamin D3",
                "protocol": "2000 IU daily with breakfast for 12 weeks",
                "reason": "Support low vitamin D level.",
            }
        ],
        "summary": "Key markers were extracted. One marker needs attention.",
        "disclaimer": "DISCLAIMER: This is not medical advice. Consult a healthcare provider before use.",
    }


def _openrouter_prompt(payload: dict, report_text: str, *, page_numbers: list[int] | None = None, total_pages: int | None = None) -> str:
    profile = payload.get("profile") if isinstance(payload.get("profile"), dict) else {}
    safe_profile = {
        "gender": profile.get("gender"),
        "ageBand": profile.get("ageBand"),
        "weightBand": profile.get("weightBand"),
    }
    page_context = ""
    if page_numbers:
        page_context = (
            "Image pages are provided in ORDER. "
            f"This request contains pages {page_numbers} "
            + (f"out of {total_pages}. " if total_pages else ". ")
            + "Preserve page order and do not mix the beginning and the end of the report.\n"
        )

    ocr_guidance = (
        "2) OCR text is the PRIMARY source for names/values/units/ranges. Images are SECONDARY and should be used to validate layout and recover missed rows.\n"
        if not AI_VISUAL_ONLY_MODE else
        "2) OCR is disabled for this run. Use only the provided images and page ordering.\n"
    )
    ocr_payload_text = report_text if (report_text and not AI_VISUAL_ONLY_MODE) else "[OCR disabled or unavailable]"

    return (
        "You are a medical lab report extraction assistant. Extract data exhaustively, not selectively. "
        "Return ONLY valid JSON with this schema: "
        "{\"biomarkers\":[{\"name\":\"string\",\"value\":\"string\",\"status\":\"Optimal|High|Low|Unknown\",\"explanation\":\"string\"}],"
        "\"recommendations\":[{\"name\":\"string\",\"protocol\":\"string\",\"reason\":\"string\"}],"
        "\"summary\":\"string\",\"disclaimer\":\"string\"}. "
        "Do not include markdown fences.\n"
        "Rules:\n"
        "1) Extract ALL visible lab rows/test results, including normal values (do not return only abnormal values).\n"
        f"{ocr_guidance}"
        "3) Preserve on-page reading order and page order.\n"
        "4) If a test name appears on one page and its value/reference range continues on the next page, combine them into one biomarker entry.\n"
        "5) If the same biomarker appears multiple times for different dates/panels, keep separate entries and mention date/panel/page in explanation.\n"
        "6) If a row is partially unreadable but identifiable, include it with status=Unknown and explain what is missing.\n"
        "7) Do not invent values, units, or ranges.\n"
        "8) Do not emit duplicates caused by overlapping stitched page groups. Merge exact duplicates.\n"
        "9) Keep explanations short and factual.\n"
        "10) Summary must mention extraction coverage (e.g., full/partial) and any unreadable sections.\n\n"
        f"User profile context: {json.dumps(safe_profile, ensure_ascii=False)}\n"
        f"{page_context}"
        f"Report text (OCR): {ocr_payload_text}\n"
    )


def _openrouter_user_content(
    payload: dict,
    report_text: str,
    *,
    images_override: list[str] | None = None,
    page_numbers: list[int] | None = None,
    total_pages: int | None = None,
) -> list[dict]:
    content: list[dict] = [{
        "type": "text",
        "text": _openrouter_prompt(payload, report_text, page_numbers=page_numbers, total_pages=total_pages),
    }]
    if AI_OCR_ONLY_MODE:
        return content
    images = images_override if images_override is not None else payload.get("images", [])
    stitched_groups = _extract_stitched_page_groups(payload)
    if isinstance(images, list):
        for idx, encoded in enumerate(images):
            if not isinstance(encoded, str) or not encoded.strip():
                continue
            page_label = None
            if page_numbers and idx < len(page_numbers):
                page_label = page_numbers[idx]
            elif images_override is None:
                page_label = idx + 1
            if page_label is not None:
                group_text = ""
                if idx < len(stitched_groups):
                    group_text = f" (covers raw pages {stitched_groups[idx]})"
                content.append({
                    "type": "text",
                    "text": (f"Image group {page_label}" + (f" of {total_pages}" if total_pages else "")) + group_text,
                })
            # App uploads JPEG base64; pass as data URL for vision models.
            content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{encoded.strip()}"},
            })
    return content


def _coerce_openrouter_json(content) -> dict:
    if isinstance(content, str):
        text = content.strip()
    elif isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text" and isinstance(item.get("text"), str):
                parts.append(item["text"])
            elif isinstance(item, dict) and isinstance(item.get("text"), str):
                parts.append(item["text"])
        text = "".join(parts).strip()
    else:
        raise ValueError("Unsupported content format")

    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:].strip()

    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise ValueError("Model output is not an object")
    return parsed


def _active_provider_api_key() -> str:
    return QWEN_API_KEY if AI_PROVIDER == "qwen" else OPENROUTER_API_KEY


def _active_provider_url() -> str:
    return QWEN_URL if AI_PROVIDER == "qwen" else OPENROUTER_URL


def _active_provider_model_chain() -> list[str]:
    if AI_PROVIDER == "qwen":
        chain = [QWEN_PRIMARY_MODEL, QWEN_FALLBACK_MODEL, QWEN_FALLBACK_MODEL_2, QWEN_FALLBACK_MODEL_3]
    else:
        chain = [
            OPENROUTER_PRIMARY_MODEL,
            OPENROUTER_FALLBACK_MODEL,
            OPENROUTER_FALLBACK_MODEL_2,
            OPENROUTER_FALLBACK_MODEL_3,
        ]
    return [m for m in chain if isinstance(m, str) and m.strip()]


def _active_provider_model_chain_for_mode() -> list[str]:
    chain = _active_provider_model_chain()
    if not AI_OCR_ONLY_MODE:
        return chain
    text_first = []
    for model in chain:
        lower = model.lower()
        if "gemma" in lower or ("vl" not in lower and "vision" not in lower):
            text_first.append(model)
    for model in chain:
        if model not in text_first:
            text_first.append(model)
    return text_first


def _call_openrouter_model(
    model: str,
    payload: dict,
    report_text: str,
    *,
    images_override: list[str] | None = None,
    page_numbers: list[int] | None = None,
    total_pages: int | None = None,
    prompt_override: str | None = None,
    user_content_override: list[dict] | None = None,
) -> dict:
    user_content = user_content_override if user_content_override is not None else _openrouter_user_content(
        payload,
        report_text,
        images_override=images_override,
        page_numbers=page_numbers,
        total_pages=total_pages,
    )
    if prompt_override is not None:
        user_content = [{"type": "text", "text": prompt_override}] + [c for c in user_content if c.get("type") == "image_url"]

    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": "Return strictly valid JSON only."},
            {"role": "user", "content": user_content},
        ],
        "temperature": 0.1,
        "max_tokens": OPENROUTER_MAX_TOKENS,
    }
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(_active_provider_url(), data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"Bearer {_active_provider_api_key()}")
    if AI_PROVIDER == "openrouter":
        req.add_header("HTTP-Referer", OPENROUTER_APP_URL)
        req.add_header("X-Title", OPENROUTER_APP_NAME)

    with urllib.request.urlopen(req, timeout=OPENROUTER_TIMEOUT_SECONDS) as resp:
        raw = resp.read()
        parsed = json.loads(raw.decode("utf-8"))

    choices = parsed.get("choices")
    if not isinstance(choices, list) or not choices:
        raise ValueError("OpenRouter response has no choices")
    message = choices[0].get("message") if isinstance(choices[0], dict) else None
    if not isinstance(message, dict):
        raise ValueError("OpenRouter response missing message")
    return _coerce_openrouter_json(message.get("content"))


def _normalize_ai_output(result: dict) -> dict:
    biomarkers = result.get("biomarkers")
    recommendations = result.get("recommendations")
    summary = result.get("summary")
    disclaimer = result.get("disclaimer")
    if not isinstance(biomarkers, list) or not isinstance(recommendations, list) or not isinstance(summary, str):
        raise ValueError("LLM output missing required fields")

    normalized_biomarkers = []
    for item in biomarkers:
        if not isinstance(item, dict):
            continue
        normalized_biomarkers.append({
            "name": str(item.get("name", "")).strip() or "Unknown",
            "value": str(item.get("value", "")).strip() or "N/A",
            "status": str(item.get("status", "Unknown")).strip() or "Unknown",
            "explanation": str(item.get("explanation", "")).strip() or "No explanation provided.",
        })

    normalized_recommendations = []
    for item in recommendations:
        if not isinstance(item, dict):
            continue
        normalized_recommendations.append({
            "name": str(item.get("name", "")).strip() or "Recommendation",
            "protocol": str(item.get("protocol", item.get("protocolText", ""))).strip() or "No protocol provided.",
            "reason": str(item.get("reason", "")).strip() or "No reason provided.",
        })

    normalized = {
        "biomarkers": normalized_biomarkers,
        "recommendations": normalized_recommendations,
        "summary": summary.strip(),
        "disclaimer": str(disclaimer or "DISCLAIMER: This is not medical advice. Consult a healthcare provider before use.").strip(),
    }
    return _dedupe_normalized_output(normalized)


def _dedupe_normalized_output(normalized: dict) -> dict:
    biomarkers = normalized.get("biomarkers", []) if isinstance(normalized.get("biomarkers"), list) else []
    recommendations = normalized.get("recommendations", []) if isinstance(normalized.get("recommendations"), list) else []

    deduped_biomarkers = []
    seen_biomarkers = {}
    for item in biomarkers:
        if not isinstance(item, dict):
            continue
        key = (
            str(item.get("name", "")).strip().lower(),
            str(item.get("value", "")).strip().lower(),
        )
        if key in seen_biomarkers:
            existing = seen_biomarkers[key]
            if len(str(item.get("explanation", ""))) > len(str(existing.get("explanation", ""))):
                existing["explanation"] = item.get("explanation", existing.get("explanation", ""))
            # Prefer a specific status if previous is Unknown.
            if str(existing.get("status", "")).strip().lower() == "unknown" and str(item.get("status", "")).strip():
                existing["status"] = item.get("status")
            continue
        clone = dict(item)
        seen_biomarkers[key] = clone
        deduped_biomarkers.append(clone)

    deduped_recommendations = []
    seen_recos = set()
    for item in recommendations:
        if not isinstance(item, dict):
            continue
        key = (
            str(item.get("name", "")).strip().lower(),
            str(item.get("protocol", "")).strip().lower(),
        )
        if key in seen_recos:
            continue
        seen_recos.add(key)
        deduped_recommendations.append(dict(item))

    normalized["biomarkers"] = deduped_biomarkers
    normalized["recommendations"] = deduped_recommendations
    return normalized


def _merge_normalized_outputs(chunks: list[dict]) -> dict:
    if not chunks:
        raise ValueError("No chunk outputs to merge")

    seen_biomarkers = set()
    merged_biomarkers = []
    for chunk in chunks:
        for item in chunk.get("biomarkers", []):
            key = (
                str(item.get("name", "")).strip().lower(),
                str(item.get("value", "")).strip().lower(),
                str(item.get("status", "")).strip().lower(),
            )
            if key in seen_biomarkers:
                continue
            seen_biomarkers.add(key)
            merged_biomarkers.append(item)

    seen_recos = set()
    merged_recommendations = []
    for chunk in chunks:
        for item in chunk.get("recommendations", []):
            key = (
                str(item.get("name", "")).strip().lower(),
                str(item.get("protocol", "")).strip().lower(),
            )
            if key in seen_recos:
                continue
            seen_recos.add(key)
            merged_recommendations.append(item)

    # Keep the latest chunk summary if available; prepend note about multi-page batching.
    last_summary = next((c.get("summary", "").strip() for c in reversed(chunks) if isinstance(c.get("summary"), str) and c.get("summary").strip()), "")
    summary = f"Analyzed report pages in order across {len(chunks)} batch(es)." + (f" {last_summary}" if last_summary else "")

    disclaimer = next(
        (c.get("disclaimer", "").strip() for c in chunks if isinstance(c.get("disclaimer"), str) and c.get("disclaimer").strip()),
        "DISCLAIMER: This is not medical advice. Consult a healthcare provider before use.",
    )

    return _dedupe_normalized_output({
        "biomarkers": merged_biomarkers,
        "recommendations": merged_recommendations,
        "summary": summary,
        "disclaimer": disclaimer,
    })


def _is_suspiciously_incomplete(normalized: dict, image_count: int) -> bool:
    biomarkers = normalized.get("biomarkers", []) if isinstance(normalized, dict) else []
    if not isinstance(biomarkers, list):
        return True
    # Heuristic only: many lab pages contain multiple rows. If a multi-image batch returns
    # too few markers, retry with smaller chunks to reduce model omissions.
    if image_count >= 2 and len(biomarkers) < (OPENROUTER_MIN_BIOMARKERS_PER_IMAGE_HINT * image_count):
        return True
    return False


def _raw_pages_covered_by_image_indices(payload: dict, image_indices_1based: list[int]) -> list[int]:
    groups = _extract_stitched_page_groups(payload)
    covered = []
    if groups:
        for img_idx in image_indices_1based:
            if 1 <= img_idx <= len(groups):
                covered.extend(groups[img_idx - 1])
    else:
        covered.extend(image_indices_1based)
    return sorted(set(int(p) for p in covered if int(p) > 0))


def _report_text_subset_for_images(payload: dict, image_indices_1based: list[int]) -> str:
    by_page = _extract_report_text_by_page(payload)
    if by_page:
        target_pages = set(_raw_pages_covered_by_image_indices(payload, image_indices_1based))
        parts = [f"[Page {item['page']}]\n{item['text']}" for item in by_page if item["page"] in target_pages]
        if parts:
            return "\n\n".join(parts)
    return _extract_report_text(payload)


def _reconciliation_prompt(extracted_json: dict, report_text: str, *, page_numbers: list[int] | None = None, total_pages: int | None = None) -> str:
    page_context = ""
    if page_numbers:
        page_context = f"Current batch image groups (ordered): {page_numbers}" + (f" out of {total_pages}" if total_pages else "") + ".\n"
    return (
        "You are a strict medical lab report reconciliation assistant.\n"
        "Task: compare OCR text + images against the existing extracted JSON and return a corrected FINAL JSON.\n"
        "Return ONLY valid JSON in the same schema.\n"
        "Rules:\n"
        "1) Add rows that were missed.\n"
        "2) Remove exact duplicates caused by overlap/page stitching.\n"
        "3) Fix wrong values/units/status if OCR clearly supports a correction.\n"
        "4) Do not invent rows or values.\n"
        "5) Preserve order as much as possible.\n\n"
        f"{page_context}"
        f"OCR text:\n{report_text}\n\n"
        f"Existing extracted JSON:\n{json.dumps(extracted_json, ensure_ascii=False)}\n"
    )


def _recommendation_synthesis_prompt(extracted_json: dict, report_text: str) -> str:
    return (
        "You are a medical functional-health assistant.\n"
        "Task: Using the extracted lab biomarkers, generate:\n"
        "1) a concise health summary (what likely needs attention), and\n"
        "2) supplement recommendations with explicit protocol details.\n"
        "Return ONLY valid JSON in the SAME schema as input/output:\n"
        "{\"biomarkers\":[...],\"recommendations\":[{\"name\":\"string\",\"protocol\":\"string\",\"reason\":\"string\"}],\"summary\":\"string\",\"disclaimer\":\"string\"}\n"
        "Rules:\n"
        "1) Keep biomarkers unchanged unless obvious duplicate cleanup is needed.\n"
        "2) Recommendations should be INFERRED from biomarkers; they do NOT need to exist in the PDF.\n"
        "3) Each recommendation protocol must include dose, frequency, timing, and duration when possible.\n"
        "4) Use practical plain language. Example protocol format: '2000 IU once daily with breakfast for 8-12 weeks'.\n"
        "5) If evidence is insufficient for a precise protocol, say so and provide a conservative suggestion.\n"
        "6) Avoid dangerous/medical-prescription advice; keep supplement-level guidance only.\n"
        "7) Summary should explain what the labs suggest and mention if extraction appears partial.\n"
        "8) Do not invent lab values.\n\n"
        f"OCR text (context, may be partial):\n{report_text or '[OCR unavailable]'}\n\n"
        f"Extracted JSON:\n{json.dumps(extracted_json, ensure_ascii=False)}\n"
    )


def maybe_generate_with_openrouter(payload: dict) -> tuple[dict | None, str | None]:
    provider_label = "Qwen" if AI_PROVIDER == "qwen" else "OpenRouter"
    if not _active_provider_api_key():
        missing_key_name = "QWEN_API_KEY" if AI_PROVIDER == "qwen" else "OPENROUTER_API_KEY"
        return None, f"{provider_label} disabled (missing {missing_key_name})"

    report_text = "" if AI_VISUAL_ONLY_MODE else _extract_report_text(payload)

    model_chain = _active_provider_model_chain_for_mode()

    images = payload.get("images", [])
    if not isinstance(images, list):
        images = []
    if AI_OCR_ONLY_MODE and not (report_text.strip() or _extract_report_text_by_page(payload)):
        return None, f"{provider_label} OCR-only mode enabled but no OCR text was provided"

    def run_model_chain_for_images(images_subset: list[str], page_numbers: list[int], total_pages: int) -> tuple[dict | None, str | None]:
        report_text_subset = "" if AI_VISUAL_ONLY_MODE else _report_text_subset_for_images(payload, page_numbers)
        errors_local = []
        for model in model_chain:
            try:
                raw = _call_openrouter_model(
                    model,
                    payload,
                    report_text_subset or report_text,
                    images_override=images_subset,
                    page_numbers=page_numbers,
                    total_pages=total_pages,
                )
                normalized = _normalize_ai_output(raw)
                return normalized, model
            except urllib.error.HTTPError as e:
                try:
                    body = e.read().decode("utf-8", errors="replace")
                except Exception:
                    body = "<unreadable>"
                errors_local.append(f"{model}: HTTP {e.code} {body[:300]}")
            except Exception as e:
                errors_local.append(f"{model}: {e}")
        return None, " | ".join(errors_local)

    def run_reconciliation_chain_for_images(
        images_subset: list[str],
        page_numbers: list[int],
        total_pages: int,
        extracted: dict,
    ) -> tuple[dict | None, str | None]:
        if AI_VISUAL_ONLY_MODE or not OPENROUTER_ENABLE_RECONCILIATION:
            return extracted, None
        recon_models = []
        if OPENROUTER_FALLBACK_MODEL:
            recon_models.append(OPENROUTER_FALLBACK_MODEL)
        if OPENROUTER_FALLBACK_MODEL_2 and OPENROUTER_FALLBACK_MODEL_2 not in recon_models:
            recon_models.append(OPENROUTER_FALLBACK_MODEL_2)
        if OPENROUTER_PRIMARY_MODEL and OPENROUTER_PRIMARY_MODEL not in recon_models:
            recon_models.append(OPENROUTER_PRIMARY_MODEL)
        recon_models = [m for m in recon_models if m]

        report_text_subset = _report_text_subset_for_images(payload, page_numbers) if not AI_VISUAL_ONLY_MODE else ""
        prompt = _reconciliation_prompt(extracted, report_text_subset, page_numbers=page_numbers, total_pages=total_pages)
        errors_local = []
        for model in recon_models:
            try:
                raw = _call_openrouter_model(
                    model,
                    payload,
                    report_text_subset,
                    images_override=images_subset,
                    page_numbers=page_numbers,
                    total_pages=total_pages,
                    prompt_override=prompt,
                )
                normalized = _normalize_ai_output(raw)
                return normalized, model
            except urllib.error.HTTPError as e:
                try:
                    body = e.read().decode("utf-8", errors="replace")
                except Exception:
                    body = "<unreadable>"
                errors_local.append(f"{model}: HTTP {e.code} {body[:300]}")
            except Exception as e:
                errors_local.append(f"{model}: {e}")
        return extracted, " | ".join(errors_local) if errors_local else None

    def run_summary_recommendation_synthesis(extracted: dict) -> tuple[dict, str | None]:
        # Final pass improves summary/recommendation quality and dosing detail using full extracted biomarkers.
        report_text_full = "" if AI_VISUAL_ONLY_MODE else (_extract_report_text(payload) or "")
        prompt = _recommendation_synthesis_prompt(extracted, report_text_full)
        synth_models = _active_provider_model_chain_for_mode()
        errors_local = []
        for model in synth_models:
            try:
                raw = _call_openrouter_model(
                    model,
                    payload,
                    report_text_full,
                    images_override=[],
                    page_numbers=[],
                    total_pages=0,
                    prompt_override=prompt,
                )
                normalized = _normalize_ai_output(raw)
                # Keep extracted biomarkers as source of truth; only take synthesized summary/recommendations/disclaimer.
                extracted["recommendations"] = normalized.get("recommendations", extracted.get("recommendations", []))
                extracted["summary"] = normalized.get("summary", extracted.get("summary", ""))
                extracted["disclaimer"] = normalized.get("disclaimer", extracted.get("disclaimer", ""))
                return _dedupe_normalized_output(extracted), model
            except urllib.error.HTTPError as e:
                try:
                    body = e.read().decode("utf-8", errors="replace")
                except Exception:
                    body = "<unreadable>"
                errors_local.append(f"{model}: HTTP {e.code} {body[:220]}")
            except Exception as e:
                errors_local.append(f"{model}: {e}")
        return extracted, (" | ".join(errors_local) if errors_local else None)

    def run_with_completeness_retry(images_subset: list[str], page_numbers: list[int], total_pages: int) -> tuple[dict | None, str | None]:
        normalized, model_or_error = run_model_chain_for_images(images_subset, page_numbers, total_pages)
        if normalized is None:
            return None, model_or_error
        if len(images_subset) <= 1 or not _is_suspiciously_incomplete(normalized, len(images_subset)):
            reconciled, recon_meta = run_reconciliation_chain_for_images(images_subset, page_numbers, total_pages, normalized)
            if recon_meta:
                return reconciled, f"{model_or_error} | reconciliation:{recon_meta}"
            return reconciled, model_or_error

        print(
            "mock-backend: completeness retry triggered for pages "
            f"{page_numbers}; biomarkers={len(normalized.get('biomarkers', []))}"
        )
        retry_chunks = []
        retry_models = []
        for i, img in enumerate(images_subset):
            single_page = [page_numbers[i]]
            single_normalized, single_model = run_model_chain_for_images([img], single_page, total_pages)
            if single_normalized is None:
                # Keep original batch result if single-page retries are worse/unavailable.
                reconciled, recon_meta = run_reconciliation_chain_for_images(images_subset, page_numbers, total_pages, normalized)
                if recon_meta:
                    return reconciled, f"{model_or_error} | reconciliation:{recon_meta}"
                return reconciled, model_or_error
            retry_chunks.append(single_normalized)
            retry_models.append(single_model)

        merged_retry = _merge_normalized_outputs(retry_chunks)
        reconciled, recon_meta = run_reconciliation_chain_for_images(images_subset, page_numbers, total_pages, merged_retry)
        meta = f"{model_or_error} (completeness-retry via {' -> '.join(retry_models)})"
        if recon_meta:
            meta += f" | reconciliation:{recon_meta}"
        return reconciled, meta

    if not AI_OCR_ONLY_MODE and len(images) > OPENROUTER_PAGE_BATCH_SIZE:
        chunk_results = []
        model_hits = []
        chunk_errors = []
        total_pages = len(images)
        for start in range(0, total_pages, OPENROUTER_PAGE_BATCH_SIZE):
            end = min(start + OPENROUTER_PAGE_BATCH_SIZE, total_pages)
            subset = images[start:end]
            page_numbers = list(range(start + 1, end + 1))
            print(f"mock-backend: analyzing page batch {page_numbers} of total_pages={total_pages}")
            normalized, model_or_error = run_with_completeness_retry(subset, page_numbers, total_pages)
            if normalized is None:
                chunk_errors.append(f"pages {page_numbers}: {model_or_error}")
                return None, f"{provider_label} batch mode failed. " + " | ".join(chunk_errors)
            chunk_results.append(normalized)
            model_hits.append(model_or_error)
        merged = _merge_normalized_outputs(chunk_results)
        merged, synth_meta = run_summary_recommendation_synthesis(merged)
        meta = f"{provider_label} batch success (ordered pages) via {' -> '.join(model_hits)}"
        if synth_meta:
            meta += f" | summary/reco:{synth_meta}"
        return merged, meta

    errors = []
    normalized, model_or_error = run_with_completeness_retry(images, list(range(1, len(images) + 1)), len(images))
    if normalized is not None:
        normalized, synth_meta = run_summary_recommendation_synthesis(normalized)
        meta = f"{provider_label} success via {model_or_error}"
        if synth_meta:
            meta += f" | summary/reco:{synth_meta}"
        return normalized, meta
    errors.append(model_or_error)

    return None, f"{provider_label} failed. " + " | ".join(errors)


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


class Handler(BaseHTTPRequestHandler):
    server_version = "VibeCheckMock/1.0"

    def log_message(self, fmt: str, *args) -> None:
        # keep logs minimal and without payload/PII
        print("mock-backend:", fmt % args)

    def do_GET(self):
        if self.path == "/health":
            return json_response(self, 200, {"status": "ok"})
        return json_response(self, 404, {"code": "not_found", "message": "Not found", "retryable": False})

    def do_POST(self):
        if self.path != "/v1/analyze-report":
            return json_response(self, 404, {"code": "not_found", "message": "Not found", "retryable": False})

        if REQUIRE_AUTH:
            auth_header = self.headers.get("Authorization", "")
            if not auth_header.startswith("Bearer "):
                return json_response(self, 401, {
                    "code": "unauthorized",
                    "message": "Missing bearer token",
                    "retryable": False,
                })
            token = auth_header.replace("Bearer ", "", 1).strip()
            if token != AUTH_TOKEN:
                return json_response(self, 403, {
                    "code": "forbidden",
                    "message": "Token is invalid",
                    "retryable": False,
                })

        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            payload = json.loads(raw.decode("utf-8") if raw else "{}")
        except Exception:
            return json_response(self, 400, {
                "code": "invalid_json",
                "message": "Request JSON is invalid",
                "retryable": False,
            })

        images = payload.get("images", [])
        if not isinstance(images, list) or len(images) == 0:
            return json_response(self, 400, {
                "code": "invalid_request",
                "message": "images must be a non-empty array",
                "retryable": False,
            })

        response, mode_msg = maybe_generate_with_openrouter(payload)
        if mode_msg:
            print("mock-backend:", mode_msg)
        if response is None:
            return json_response(self, 502, {
                "code": "ai_provider_failed",
                "message": mode_msg or "AI provider failed",
                "retryable": True,
            })
        return json_response(self, 200, response)


def main() -> None:
    print(f"mock-backend: starting on http://{HOST}:{PORT} (auth={'on' if REQUIRE_AUTH else 'off'})")
    print(f"mock-backend: ai_provider={AI_PROVIDER}")
    print(f"mock-backend: ai_mode={'visual-only' if AI_VISUAL_ONLY_MODE else ('ocr-only' if AI_OCR_ONLY_MODE else 'hybrid')}")
    if AI_PROVIDER == "qwen":
        print(f"mock-backend: primary_model={QWEN_PRIMARY_MODEL}")
        print(f"mock-backend: fallback_model={QWEN_FALLBACK_MODEL}")
        print(f"mock-backend: fallback_model_2={QWEN_FALLBACK_MODEL_2}")
        print(f"mock-backend: fallback_model_3={QWEN_FALLBACK_MODEL_3}")
    else:
        print(f"mock-backend: primary_model={OPENROUTER_PRIMARY_MODEL}")
        print(f"mock-backend: fallback_model={OPENROUTER_FALLBACK_MODEL}")
        print(f"mock-backend: fallback_model_2={OPENROUTER_FALLBACK_MODEL_2}")
        print(f"mock-backend: fallback_model_3={OPENROUTER_FALLBACK_MODEL_3}")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
