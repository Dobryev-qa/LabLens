# VibeCheck Delivery Checklist

Дата обновления: 2026-02-22
Владелец: Team Mobile + Team Backend
Статус проекта: In Progress

## Как пользоваться
- Отмечайте пункты только после фактической проверки.
- Не переходите к следующей фазе, пока текущая не закрыта.
- Все scope changes фиксируйте в разделе `Change Log`.

---

## Phase 1 — Stabilize iOS
Статус: [~]

- [ ] Удалены ключи из кода/репозитория (`Config.xcconfig`, `Info.plist`, git history).
- [ ] API ключ ротирован.
- [x] В iOS оставлен только `API_BASE_URL` (+ app auth strategy, без LLM key).
- [ ] Debug и Release сборки проходят локально.
- [x] Убраны `print` с потенциально чувствительными данными.
- [ ] Основные флоу стабильны: History / Scan / Profile.

Критерий завершения фазы:
- [ ] Все пункты закрыты и подтверждены на устройстве/симуляторе.

---

## Phase 2 — Backend API Contract
Статус: [ ]

- [ ] Зафиксирован endpoint: `POST /v1/analyze-report`.
- [ ] Зафиксированы `request/response/error` схемы.
- [ ] Поля профиля минимизированы (age band, gender, optional weight band).
- [ ] Единая модель ошибок: `code`, `message`, `retryable`.
- [ ] Версия API (`v1`) зафиксирована.
- [ ] Добавлены примеры success/failure payload.

Критерий завершения фазы:
- [ ] Контракт подписан mobile/backend и не меняется без changelog.

---

## Phase 3 — Local Backend (Mock First)
Статус: [~]

- [ ] `docker compose up` поднимает backend одной командой.
- [x] Режим `MOCK=true` возвращает стабильные фикстуры.
- [ ] Валидируется входной payload (формат, размер, required fields).
- [x] Есть `/health` и readiness endpoint.
- [ ] Логи backend без PII.

Критерий завершения фазы:
- [x] Mobile может стабильно тестировать UI через локальный mock backend.

---

## Phase 4 — iOS Integration with Backend
Статус: [ ]

- [ ] iOS ходит только в backend (нет прямого обращения к LLM provider).
- [ ] Добавлены timeout + retry/backoff + cancel.
- [ ] Ошибки backend корректно маппятся в UI states.
- [ ] Проверены PDF кейсы: 1 / 8 / 20 страниц.
- [ ] Legacy direct-LLM код выключен или удален.

Критерий завершения фазы:
- [ ] End-to-end сценарий анализа проходит через backend.

---

## Phase 5 — Privacy & Security Hardening
Статус: [ ]

- [ ] Consent version + timestamp проверяются перед каждым analyze.
- [ ] Delete All Data удаляет: профиль, историю, consent, prompt flags.
- [ ] На backend: rate limit, auth, payload limits.
- [ ] Секреты только в secret manager / CI vars.
- [ ] Пройден threat checklist (key exposure, abuse, log leaks).

Критерий завершения фазы:
- [ ] Privacy flow воспроизводимо проходит QA-проверку.

---

## Phase 6 — Test Pack
Статус: [ ]

- [ ] Unit: profile/consent/repository/parser.
- [ ] Integration: iOS -> backend(mock) end-to-end.
- [ ] UI tests: onboarding -> scan -> history -> delete data.
- [ ] Regression: invalid JSON / timeout / 429 / 500.
- [ ] Сформирован test report (pass rate + known issues).

Критерий завершения фазы:
- [ ] Тестовый пакет green или согласован список блокеров.

---

## Phase 7 — Staging
Статус: [ ]

- [ ] Отдельный staging backend + staging secrets.
- [ ] TestFlight build подключен к staging.
- [ ] Пройден smoke checklist.
- [ ] Снимаются метрики: latency, success_rate, invalid_json_rate.
- [ ] Проверен rollback plan.

Критерий завершения фазы:
- [ ] Staging готов к production gate review.

---

## Phase 8 — Production Launch
Статус: [ ]

- [ ] CI/CD green (build, tests, secret scan).
- [ ] Production deploy выполнен с мониторингом.
- [ ] Пост-релизный мониторинг 48 часов закрыт.
- [ ] Incident playbook и on-call подтверждены.
- [ ] Release notes и known limitations опубликованы.

Критерий завершения фазы:
- [ ] Проект переведен в режим поддержки.

---

## Daily Status (короткий)
Заполнять ежедневно:
- Done: удален hardcoded ключ из `Config.xcconfig`; `print(...)` заменены на `OSLog`; iOS переведен на backend API (`API_BASE_URL`) вместо прямого OpenRouter; добавлен app-to-backend bearer auth (`API_AUTH_TOKEN`) и обработка 401/403; поднят локальный mock backend и проверены сценарии 401/403/200.
- Next: ротация ключа и чистка git history; подключение backend проверки токена в staging; закрыть оставшиеся пункты Phase 3/4/6.
- Blockers: ключ ранее утек в git history и требует ротации/очистки истории; нет staging backend с прод-auth политикой.
- Owner: Codex (Lead iOS)
- Date: 2026-02-22

---

## Change Log
Формат записи:
- YYYY-MM-DD — [Scope Added/Removed/Changed] — описание — инициатор — согласовано кем.

Примеры:
- 2026-02-22 — [Added] Добавлен локальный mock backend режим — Backend Lead — Mobile Lead.
- 2026-02-23 — [Changed] Ограничен размер PDF upload до N MB — Security — Product.
- 2026-02-22 — [Changed] Удален hardcoded `OPENROUTER_API_KEY` из `Config.xcconfig`, runtime-`print` заменены на `OSLog` — Codex — Product.
- 2026-02-22 — [Changed] iOS `AIService` переведен с прямого OpenRouter на backend endpoint `POST /v1/analyze-report`, добавлен `API_BASE_URL` — Codex — Product.
- 2026-02-22 — [Changed] Добавлен app-to-backend auth (`Authorization: Bearer <API_AUTH_TOKEN>`) и явная обработка backend 401/403 в `AIService` — Codex — Product.
- 2026-02-22 — [Added] Поднят локальный mock backend (`/v1/analyze-report`, `/health`) с auth-check и проверены e2e сценарии 401/403/200 — Codex — Product.
