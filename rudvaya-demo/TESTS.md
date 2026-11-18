# TESTS — Rudvaya AI Lead Automation Demo

Run these in order after completing README.md steps 1–5. Mark each row's
**Result** column PASS or FAIL as you go (edit this file directly). Reset
demo data (`README.md` §6) before Test 1 and before any full re-run.

| # | Test | How to run it | Expected database / UI result | Result |
|---|------|----------------|-------------------------------|--------|
| 1 | Import sample CSV | Open WF-01's Form Trigger production URL, upload `data/sample_leads.csv` | Import report shows 14 created, 0 updated, 2 duplicates in file, 4 invalid. `select count(*) from leads;` = 14. `select reason, count(*) from import_rejects group by reason;` shows `duplicate_in_file` (2), `invalid_phone` (2), `missing_consent` (1), `missing_name` (1) | |
| 2 | Re-import the same CSV | Upload `data/sample_leads.csv` again | Report shows 0 created, 14 updated. `select count(*) from leads;` still 14. No `do_not_contact` flag changed. | |
| 3 | Call a non-allowlisted lead | Dashboard → "Call now" on any lead whose number is not in `app_config.call_allowlist` | Toast shows "Blocked: not_in_demo_allowlist". `select * from audit_events where event_type='call_blocked' order by created_at desc limit 1;` shows the block reason. No Bolna call placed. | |
| 4 | Call a lead with consent = no | Not reachable via UI (rejected at import). Manual DB check: `insert into leads (name, phone_e164, consent) values ('Test NoConsent', '+910000000001', false);` then call `/webhook/start-call` with that lead's id via `data/test_payloads/start-call.json` | Response `{ "ok": false, "blocked_reason": "no_consent" }` | |
| 5 | Double-click Call now | Click "Call now" twice quickly on the same lead | `select count(*) from call_attempts where lead_id = '<id>' and reason='manual';` = 1. Second click's response should be `blocked_reason: "call_already_in_progress"` (or the UI shows one call in flight). | |
| 6 | Interested call, agree to Saturday visit | Live or simulated call; play an interested buyer, agree to a Saturday site visit | `leads.status = 'visit_requested'`. New row in `appointments` with `type='site_visit'`, `requested_time_text` mentioning Saturday. A `visit_ack` message appears in the mock inbox. | |
| 7 | Busy: "call me at 6 pm" | Play a busy customer who asks for a 6pm callback | `followup_tasks` row with `due_at` around 18:00 IST (or the AI's parsed time) and status `pending`. A `callback_ack` message appears in the mock inbox. | |
| 8 | Angry customer | Play an angry/frustrated customer | Agent stays calm, offers a human callback, does not argue. `call_attempts.classification->>'customer_sentiment'` is `angry` or `frustrated`. No pressure tactics in transcript. | |
| 9 | "Don't call me again" | Say "stop calling me" / "remove my number" mid-call | `leads.do_not_contact = true`. Any `pending` `followup_tasks` for that lead flip to `cancelled` with `cancellation_reason = 'opt_out'`. A later `/start-call` for this lead returns `blocked_reason: "do_not_contact"`. | |
| 10 | Reject the call (no answer) | Let a call ring out / simulate no-answer | `call_attempts.status` matches Bolna's no-answer status. `leads.status = 'callback'`. A `missed_call` message (SIMULATED) appears in the mock inbox. `followup_tasks` has a pending row due in ~2 minutes. Wait ~2 min and confirm WF-05 dials again exactly once (check `call_attempts` for a second row with `reason='callback'`). | |
| 11 | Reply "STOP" in mock inbox | Open `/webhook/whatsapp`, select a lead, type `STOP`, send | `leads.do_not_contact = true` and any pending callback for that lead is cancelled before it fires. Inbox shows an `optout_ack` auto-reply. | |
| 12 | Malformed AI output | Temporarily break parsing: in `Validate JSON` (WF-03) or `Validate Reply JSON` (WF-04), force `errors.push('forced_test')` and run a call/reply through | `leads.status = 'review'`. `audit_events` has an `invalid_ai_output` row. No appointment/callback/opt-out side effects were taken. Revert the code change after this test. | |
| 13 | Outside calling window | Temporarily set `call_window_start`/`call_window_end` to exclude the current time (`update app_config set value = '23:58' where key='call_window_start';`), then try Call now | `blocked_reason: "outside_call_window"`. Revert the config value afterward. | |
| 14 | Dashboard counts | Compare `/webhook/api/stats` JSON against `select * from v_dashboard;` run directly in Supabase | All numbers match exactly. `live_calls` + `simulated_calls` columns separate LIVE from SIMULATED call counts; dashboard activity feed badges agree. | |
| 15 | Secret check | Search every file in this folder for your actual API keys/passwords | No match. (`Select-String -Path .\workflows\*.json,.\pages\*.html,.\README.md -Pattern "sk-|AIza|postgres://.*:.*@"` should return nothing real — only placeholder text.) | |

## Notes on tests 12 and 13

These two intentionally mutate the system to prove a failure path works.
Always revert the change immediately after confirming the result, so the
demo-mode safety nets (calling window, AI validation) are back in their
normal state before you move on or rehearse.
