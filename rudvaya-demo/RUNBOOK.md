# RUNBOOK — Demo scripts

## Before the meeting

- **Day before:** open the Supabase dashboard once (wakes a paused free
  project), check your Bolna credit balance, run TESTS.md #1, #6, #9, #10.
- **One hour before:** start n8n (`n8n start` with
  `GENERIC_TIMEZONE=Asia/Kolkata`), reset demo data (README.md §6), disable
  laptop sleep, keep the phone charged with the ringer on (not silent).
- Check `app_config.call_window_start` / `call_window_end` covers the
  meeting time (demo seed widens this to all-day; narrow it back only if
  you want to rehearse the production-like window).
- Have the browser simulator ready as a backup tab, and ideally a screen
  recording of one successful live-call run as a last resort.

---

## 5-minute script

| Time | Show | Say |
|---|---|---|
| 0:00 | Dashboard (empty) | "Leads arrive from Meta ads, CRM exports and walk-in registers, often duplicated." |
| 0:30 | Upload `data/sample_leads.csv` | "20 rows in. The system caught 2 duplicates and 4 bad entries automatically, including one without consent." |
| 1:15 | Click "Call now" on a lead whose number you swapped to your verified number | "The AI calls right away. It introduces itself as an AI assistant." Phone rings; answer on speaker. |
| 1:30 | Live (or simulated) conversation | Play an interested buyer: ask the 3 BHK price, then agree to a Saturday visit. |
| 2:45 | Dashboard updates | "Transcript classified: interested, 3 BHK, visit requested. The appointment is waiting for staff confirmation." Click Confirm. |
| 3:15 | Call another lead, let it go unanswered (or simulate no-answer) | "No answer, so a WhatsApp follow-up goes out and a callback is scheduled." Show the mock inbox (SIMULATED label). |
| 3:50 | Type reply "Can I come Sunday?" in the mock inbox | "The reply is understood and turned into a site-visit request." |
| 4:20 | Call a third lead, say "don't call me" mid-call | "The agent apologises, ends the call, and the number is suppressed everywhere." |
| 4:45 | KPI row | "Live calls are real; WhatsApp is simulated today and connects to the official API in the pilot." |

---

## 15-minute version adds

- **Angry-customer call** — demonstrate tone handling: agent stays calm,
  apologises once, offers a human callback, never argues.
- **Busy customer asking for a 6pm callback** — show the scheduled
  `followup_tasks` row and, if time allows, let WF-05 actually dial it.
- **Open the n8n editor** and walk through WF-02 (eligibility gate) and
  WF-03 (polling + classification) visually — this is usually the part
  that builds the most client confidence, since they can see the
  consent/do-not-contact/allowlist checks happening in plain sight.
- **Production roadmap slide:** telecom 140-series registration, Bolna
  paid plan + Indian number + KYC, Meta WhatsApp Cloud API swap, hosted
  n8n with HTTPS, DPDP Act data-retention policy — all listed in the
  source plan §16. Mention this is Rudvaya's path from demo to pilot, not
  something switched on today.
- **Costing table** (plan §11.2): roughly ₹10,000–15,000/month indicative
  for 1,000 leads in production, dominated by voice-minute cost.

---

## If something breaks mid-demo

| What breaks | Do this |
|---|---|
| Bolna call doesn't connect | Retry once, then switch to the browser simulator tab — same classification pipeline, same dashboard outcome. |
| OpenAI returns an error | The lead goes to `review` status automatically (never a silent failure) — explain this is the safety behaviour, then re-run the call once billing/quota is confirmed fixed. |
| Supabase looks frozen / dashboard won't load | The free project may have paused — open supabase.com once in a second tab to wake it, then refresh the dashboard. |
| n8n window got closed | Re-run `n8n start` from PowerShell; workflows stay Active, no need to re-import. |
