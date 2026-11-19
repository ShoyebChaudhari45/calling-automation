# Explaining the demo, node by node

This is your prep sheet for walking a client through the system. It's
organized the same way the n8n editor is — one section per workflow (WF-01
through WF-07) — so you can have this open on a second screen and click
through each workflow in the editor while reading the matching section here.

**The one-sentence pitch:** every lead goes through the same four steps —
cleaned on the way in, only called if it's safe and allowed, listened to
and understood by AI after the call, and automatically followed up on —
with a human able to see and override any of it from the dashboard.

---

## WF-01 · Lead Intake, Validation & Deduplication

**What to say:** "This is the front door. Whatever list a client uploads —
Meta ad exports, a CRM dump, a walk-in register — never arrives clean.
This workflow catches the mess automatically, before anything is called."

**Walking through the nodes:**

| Node | What it does, in plain terms |
|---|---|
| Upload Leads CSV | The upload form. Anyone can drag a CSV here. |
| Read CSV | Turns the file into rows n8n can work with. |
| Normalize & Validate | The real work: turns every phone number into one consistent format (`+91...`), and checks each row has a name, a valid Indian mobile number, and recorded consent. Also catches the same number appearing twice *within the same file* — common when a lead fills a form twice. |
| Valid & consented? | A fork in the road: clean rows go one way, problem rows go the other. |
| Upsert Lead | Clean rows get saved. If the same phone number already exists for this client, it's treated as an update, not a second lead — **this is the database-level dedupe**, via a unique constraint on phone number, not just app logic. |
| Log Rejected | Problem rows get logged with the *reason* (missing consent, bad number, duplicate, missing name) — nothing silently disappears. |
| Build Summary | Counts everything up. |
| Show Import Report | What the presenter sees: "Imported 14 new, 0 already existed, 2 duplicates, 4 invalid." |

**The client-reassuring line:** "Nothing gets called just because it's in a
spreadsheet. If there's no recorded consent, it's rejected right here —
before it's even a 'lead' in our system."

---

## WF-02 · Contact Eligibility & Call Dispatch

**What to say:** "This is the compliance gate. Every single call — whether
triggered by a staff member clicking a button, or an automatic callback —
passes through the exact same six checks before anything dials."

**The six checks (say these out loud, they're the trust-builder):**
1. Did the lead actually consent?
2. Have they asked not to be contacted (do-not-contact)?
3. Have we already tried the maximum number of times?
4. Is it within allowed calling hours?
5. Do they already have an appointment booked (don't re-pitch someone who's already converted)?
6. **Demo-only:** is this number on the safety allowlist? (This is what stops a real customer being accidentally called during a demo — in production this check is removed once the client has proper telecom registration.)

**Walking through the nodes:**

| Node | What it does |
|---|---|
| Start Call Request / Called by WF-05 | Two doors into the same workflow: a person clicking "Call now" on the dashboard, or the automatic callback scheduler (WF-05). Either way, same rules apply. |
| Load Lead + Config | Pulls the lead's record plus every setting from `app_config` in one go — nothing about calling behaviour is hard-coded in the workflow itself. |
| Eligibility Gate | The six checks above, run in code. |
| Eligible? | Branch: pass → dial it; fail → log why and stop. |
| Create Call Attempt | Writes a row to the database *before* dialing, with a unique "idempotency key" — this is what makes it impossible to accidentally double-dial the same lead (e.g. a nervous double-click on "Call now"). |
| Call Mode | Reads one setting (`live_bolna` vs `simulated`) to decide whether to actually ring a phone or open the browser fallback. |
| Bolna: Make Call | The actual API call to Bolna that rings the phone and hands the conversation to the AI voice agent. |
| Save Execution ID | Stores Bolna's call ID so the next workflow (WF-03) knows which call to check on. |
| Start Result Poller | Hands off to WF-03 in the background — the webhook responds immediately instead of making the dashboard wait for the whole call to finish. |

**The client-reassuring line:** "If any one of those six checks fails, the
call simply never happens, and we log exactly why. There's no path in this
system where a blocked lead gets called anyway."

---

## WF-03 · Call Result Polling & AI Classification

**What to say:** "Once the call ends, this is where the AI 'understands'
what happened — but we never let the AI take an action directly. Its
answer is checked against a strict format first."

**Walking through the nodes:**

| Node | What it does |
|---|---|
| Poller Start | Kicked off by WF-02 right after a call is dialed (or by WF-07 for a browser-simulated call). |
| Mode Router | Live calls go check on Bolna every 15 seconds; simulated calls already have their transcript, so they skip straight to classification. |
| Wait 15s → Get Execution → Check Finished | The polling loop: ask Bolna "is this call done yet?" every 15 seconds, for up to 10 minutes, until it gets a final status. |
| Outcome Check / Answered? | Did the person actually speak, or did the call go unanswered / busy / failed? |
| *(no answer branch)* Mark No Answer → Schedule Callback → Send Missed-Call Message | If nobody picked up: log it, schedule a retry in a few minutes (production: 24 hours), and send a "we tried to reach you" WhatsApp message. |
| Load Facts + Model | Pulls the verified property facts and which AI model to use — so the AI is graded against the *same facts the agent was told to use on the call*, and the model name is a setting, not hard-coded. |
| Classify Call | Sends the transcript to OpenAI with a strict instruction: "return exactly this JSON shape — lead status, sentiment, budget, whether they want a visit, whether they opted out — nothing else." |
| **Validate JSON** | **This is the safety net.** Code checks every field the AI returned against an allowed list. If the AI's answer doesn't match the expected shape (wrong field, missing value, garbled output), the lead is marked "review" and nothing else happens automatically — a human looks at it. |
| Save Result | Only runs for *validated* output — writes the transcript, AI summary, and classification to the database. |
| Route Action → A–F | Six possible outcomes, checked in this priority order: opted out → escalation needed → visit requested → callback needed → generally interested → not interested. Each one triggers the right follow-up (cancel future contact, flag for a human, book an appointment, schedule a callback, send a brochure, or just close it out). |

**The client-reassuring line:** "If the AI ever returns something we don't
recognize — a glitch, an unusual answer — nothing automatic happens. It
goes to a 'needs review' queue instead of guessing."

---

## WF-04 · WhatsApp Follow-up (Mock) & Inbound Replies

**What to say:** "Today this is a mock inbox — every message is clearly
labelled SIMULATED and nothing leaves this laptop. In production, this
exact same logic sends through Meta's official WhatsApp Business API; only
the 'send' and 'receive' nodes change, not the decision logic."

**Walking through the nodes (two paths):**

**Path A — sending a message** (triggered by WF-03 or WF-05): load the
lead → check they haven't opted out → fill in a template (missed-call,
brochure, visit confirmation, callback confirmation, opt-out confirmation)
→ write it to the mock outbox → simulate a delivery tick a few seconds
later.

**Path B — a customer replies** (typed into the mock inbox page): save the
inbound message → classify intent with AI (interested / wants a callback /
wants a site visit / not interested / opt-out / complaint) → validate that
classification the same way WF-03 does → act accordingly (cancel contact
and confirm opt-out, book the requested visit, schedule the callback, flag
a complaint for a human, or do nothing if the AI wasn't confident).

**The client-reassuring line:** "Reply 'STOP' in the mock inbox right now
and I'll show you — the opt-out takes effect immediately, and any pending
callback for that lead gets cancelled before it can fire."

---

## WF-05 · Callback Scheduler

**What to say:** "This is the workflow nothing to look at run — it just
quietly ticks over every minute making sure promised callbacks actually
happen, without ever double-dialing anyone."

**Walking through the nodes:**

| Node | What it does |
|---|---|
| Every Minute | The trigger — runs on a schedule, no human involved. |
| Claim Due Tasks | Picks up to 5 callbacks that are overdue, using a database row-lock (`FOR UPDATE SKIP LOCKED`) — **this is what guarantees a callback is claimed by exactly one run**, even if something else is also checking at the same moment. |
| Re-check Lead / Still Eligible? | Before redialing, re-checks everything: has the customer opted out since the callback was scheduled? Replied already? Already got an appointment? Hit the attempt limit? |
| Dial Again | If still eligible, hands off to WF-02 — which runs its own full eligibility gate *again*. Two independent safety checks, not one. |
| Close Task | Marks the callback done (or cancelled, with the reason) either way. |

**The client-reassuring line:** "A scheduled callback isn't a standing
permission to keep calling — it's checked for eligibility twice: once
here, once in the dispatch workflow itself."

---

## WF-06 · Dashboard & Data API

**What to say:** "This workflow doesn't make any decisions — it's purely
the window into everything the other six are doing. Every chart, every
list, every button on the dashboard is one webhook in here."

It serves the dashboard page itself, the KPI numbers, the lead list
(click any row for the full transcript/recording/AI classification), the
appointments list with its "Confirm" button, and the live activity feed —
plus the "Call now" button's POST request, which is really just talking to
WF-02.

**The client-reassuring line:** "Everything you're looking at right now is
reading live from the same database every other workflow writes to —
there's no separate reporting layer that could drift out of sync."

---

## WF-07 · Browser Call Simulator (fallback)

**What to say:** "This exists for two reasons: a safe way to demo the
*exact same AI conversation logic* without placing a real phone call, and
a fallback if the Bolna trial credit or network ever fails mid-demo."

It serves a page with a "SIMULATED — BROWSER DEMO, NOT A PHONE CALL" banner
that stays on screen the whole time, uses the browser's microphone (or a
text box if the browser doesn't support speech), and feeds each turn to
the *same* OpenAI prompt the real Bolna agent uses — then, on "End call",
sends the transcript down the *exact same* classification path as a real
call (WF-03). Nothing about the decision-making differs; only the audio
path does.

---

## Pre-demo checklist (do this every time, takes 2 minutes)

1. Double-click `start-n8n.bat` — the dashboard opens automatically once
   n8n is ready.
2. Open the Bolna dashboard and check the credit balance hasn't run out.
3. Confirm `app_config.call_allowlist` contains the number(s) you're
   actually going to call today (Supabase SQL Editor: `select * from
   app_config where key = 'call_allowlist';`).
4. If you want a clean slate: run the reset SQL in README.md §6 ("Reset
   demo data") before the client arrives.
5. Have the simulator tab (`http://localhost:5678/webhook/simulator`)
   ready as backup in case the live call doesn't connect.

See `RUNBOOK.md` for the minute-by-minute 5-minute and 15-minute scripts,
and README.md for the full technical reference (every node's exact
parameters, credentials, and the bugs found/fixed while getting this
running).
