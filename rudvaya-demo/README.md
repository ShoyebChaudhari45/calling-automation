# Rudvaya AI Lead Automation — Demo Build

This is a runnable DEMO (not production) of the plan in
`Rudvaya_AI_Lead_Automation_Demo_Build_Plan.pdf`. Phone calls can be real
(via your Bolna trial, to verified numbers only); WhatsApp is always
simulated; everything else runs on your Windows laptop plus a free Supabase
Postgres project.

**Status at hand-off:** Node.js and n8n (v2.22.6) are installed and running
on this machine, and the `n8n-nodes-bolna` community node is installed. The
Supabase project and Bolna agent do not exist yet. Where a value couldn't be
verified without your own accounts, it's marked **TODO** with a sticky
note in the workflow JSON — fix those once you can see the real thing.
Several things that were originally guessed have since been **confirmed**
against the installed `n8n-nodes-bolna` v0.1.2 source and Bolna's public API
docs (see "Resolved since initial build" below) — WF-02 and WF-03 were
updated accordingly and no longer carry TODOs for those specific items.

---

## 0. What's in this folder

```
rudvaya-demo/
  sql/01_schema.sql           -- run first in Supabase SQL Editor
  sql/02_seed.sql             -- run second; REPLACE 3 values before testing
  workflows/WF-01 ... WF-07   -- import into n8n, one file each
  pages/dashboard.html        -- served by WF-06 at /webhook/dashboard
  pages/whatsapp.html         -- served by WF-04 at /webhook/whatsapp
  pages/simulator.html        -- served by WF-07 at /webhook/simulator
  data/sample_leads.csv       -- 20 fictional leads, built-in test cases
  data/test_payloads/*.json   -- example bodies for every POST webhook
  TESTS.md                    -- the 15 tests from the plan, PASS/FAIL table
  RUNBOOK.md                  -- 5-minute and 15-minute demo scripts
```

---

## 1. Install Node.js and n8n

```powershell
node -v                         # confirm Node.js LTS is installed; if missing, get it from nodejs.org
npm install n8n -g              # installs n8n globally (a few minutes)
$env:GENERIC_TIMEZONE = "Asia/Kolkata"
n8n start
```

Open http://localhost:5678 and create the owner account. **Keep this
PowerShell window open** — closing it stops n8n. To make the timezone
permanent: Windows Settings → "Edit environment variables for your account"
→ add `GENERIC_TIMEZONE` = `Asia/Kolkata`.

Run `n8n --version` and note the result — some node parameter names in the
imported workflows (Form Trigger, Switch, Execute Workflow) differ slightly
between n8n releases. Every workflow JSON has a sticky note flagging the
specific nodes to double-check against your version.

### Install the Bolna community node

In n8n: **Settings → Community Nodes → Install** → enter
`n8n-nodes-bolna` → accept the risk prompt → Install → restart n8n if asked.

---

## 2. Create the Supabase project and run the SQL

1. supabase.com → New project, name `rudvaya-demo`, region Mumbai
   (ap-south-1) if offered. Save the database password somewhere safe.
2. Once the project is ready: **SQL Editor → New query** → paste the full
   contents of `sql/01_schema.sql` → Run.
3. New query again → paste `sql/02_seed.sql` → **before running**, edit
   these three lines in that file:
   - `call_allowlist` → your phone + a colleague's phone, both in E.164
     format (e.g. `+919812345678`), comma-separated — these are the ONLY
     numbers demo_mode will allow Bolna to call.
   - `bolna_agent_id` → fill in once you've created the Bolna agent (step 4).
   - `openai_model` → fill in once you've confirmed a model name available
     to your OpenAI account.
   Then Run.
4. **Project → Connect → Session pooler** — copy host, port, database
   name, user. (The session pooler works over IPv4; the direct connection
   may need IPv6, which most home/office networks don't have.)

### Create the n8n Postgres credential

In n8n: **Credentials → New → Postgres**. Name it `Rudvaya Supabase Postgres`
(the workflow JSON files reference this exact name as a label — the
underlying credential ID will differ per install, which is why every
Postgres node says `REPLACE_WITH_YOUR_CREDENTIAL_ID` and must be
re-selected from the dropdown after import). Fill in host/port/database/
user/password from the Session pooler, enable SSL, click **Test**.

---

## 3. Create the OpenAI credential

1. platform.openai.com → create a project `rudvaya-demo` → create an API
   key → set a monthly budget limit (e.g. $5).
2. In n8n: **Credentials → New → OpenAi**. Name it `Rudvaya OpenAI`, paste
   the key.
3. In the OpenAI dashboard, confirm which chat-completion model your
   account can use, and put that exact string into
   `app_config.openai_model` (Supabase SQL Editor):
   ```sql
   update app_config set value = 'YOUR_MODEL_NAME' where key = 'openai_model';
   ```

---

## 4. Create the Bolna account and agent

1. bolna.ai → sign up, confirm the $5 trial credit.
2. **Verify** your mobile number and a colleague's in the Bolna dashboard —
   trial accounts can only call verified numbers.
3. **Developers → API Keys** → copy the key.
4. In n8n: **Credentials → New → Bolna API** (added by the community node).
   Name it `Rudvaya Bolna API`, paste the key. This one credential is used
   everywhere Bolna is called — WF-02's "Bolna: Make Call" node AND WF-03's
   "Get Execution" node (confirmed from the installed node's source: it
   sends `Authorization: Bearer <apiKey>` automatically). No separate
   Header Auth credential is needed.
5. Create an agent named **Aranya Heights Assistant**, paste the prompt
   below (also in the plan §8.1) into its system prompt field, pick a
   Hindi/English-capable voice, set max call duration ≈ 5 minutes.

   <details><summary>Bolna agent prompt (click to expand)</summary>

   ```
   ROLE
   You are Priya, an AI voice assistant calling on behalf of the sales team of
   {property_name}. You are speaking to {lead_name}, who enquired about this
   project. You are an AI assistant and you must say so at the start of the call.

   LANGUAGE
   Start in simple English. If the customer speaks Hindi, Marathi or Hinglish,
   switch to that language. Short sentences. One question at a time.

   OPENING (say exactly this idea, naturally)
   "Hello {lead_name}, this is Priya, an AI assistant calling from the
   {property_name} team about your recent enquiry. Is this a good time to talk
   for two minutes?"
   - If NO or busy: ask when would be a better time, confirm it, thank them, end.

   GOALS (in order, stop as soon as the customer wants to stop)
   1. Confirm interest in {property_name}.
   2. Understand need: 2 BHK or 3 BHK, rough budget, purchase timeline.
   3. Answer questions ONLY from the VERIFIED FACTS below.
   4. Offer a site visit or an office meeting and capture a preferred day/time.
   5. Close politely and say a team member will confirm on WhatsApp.

   VERIFIED FACTS (the only facts you may state)
   {property_facts}
   If asked anything not covered here, say you will have a team member call
   back with exact details. Never guess numbers.

   HOW TO HANDLE THE CUSTOMER
   - Interested: be warm, ask one qualifying question, offer a visit.
   - Busy: ask for a callback time, confirm it, end quickly.
   - Confused: explain simply, check understanding, slow down.
   - Angry or frustrated: stay calm, apologise once, do not argue or defend,
     offer a human callback, end the call if they ask.
   - Not interested: thank them and end. Do not push.
   - Complaint, legal or safety issue: stop selling, say a senior team member
     will call back, end.
   - "Stop calling", "don't call", "remove my number": acknowledge and end
     immediately.

   NEVER
   - Pretend to be human. Pressure, threaten, or create false urgency.
   - Promise discounts, availability, approvals or returns.
   - Ask for Aadhaar, PAN, bank or payment details.
   - Make assumptions about religion, caste, community, gender or family.

   Keep the whole call under 4 minutes.
   ```
   </details>

6. Test it from the Bolna dashboard ("Speak to your agent" / test call to
   your own phone). Copy the **agent_id**:
   ```sql
   update app_config set value = 'YOUR_AGENT_ID' where key = 'bolna_agent_id';
   ```

---

## 5. Import and wire up the workflows

For each file in `workflows/`, in n8n: **Workflows → Import from File**.
Credentials are never stored in the exported JSON (by design, per n8n and
per the plan's safety rule), so after each import:

1. Open every node whose `notes` field says **CREDENTIAL REQUIRED** and pick
   your credential from the dropdown (the JSON's `REPLACE_WITH_YOUR_CREDENTIAL_ID`
   placeholders are just labels — n8n will show you the real list).
2. Open the sticky note at the top-left of the canvas — it lists exactly
   what to fix in that workflow.
3. **File path nodes** (`Read Dashboard Page`, `Read WhatsApp Page`,
   `Read Simulator Page`): replace `C:\REPLACE\...` with this folder's real
   absolute path, e.g. `D:\automation\rudvaya-demo\pages\dashboard.html`.
4. **Cross-workflow references**: several `Execute Workflow` nodes say
   `REPLACE_WITH_WF0X_WORKFLOW_ID` — once ALL seven workflows are imported
   and saved, open each `Execute Workflow` node and pick the target
   workflow from the dropdown (n8n resolves the id for you). Import order
   matters less than wiring order here — import all seven first, *then*
   go back and fix every cross-reference.
5. Toggle each workflow to **Active** (top-right switch). Production
   webhook URLs (`/webhook/...`) only resolve while a workflow is Active;
   the editor's "Test URL" (`/webhook-test/...`) only fires once per click
   from the editor and is not what the HTML pages use.

Recommended build/test order (matches the plan): **SQL → WF-01 → WF-06 →
WF-02 → WF-03 → WF-04 → WF-05 → WF-07**. Test each one per the matching
section of `TESTS.md` before moving to the next — most failures are a
credential not selected or a workflow not yet Active.

---

## 6. Everyday use

- **Start n8n:** open PowerShell, `$env:GENERIC_TIMEZONE = "Asia/Kolkata"`
  then `n8n start`. Leave the window open.
- **Dashboard:** http://localhost:5678/webhook/dashboard
- **Mock WhatsApp inbox:** http://localhost:5678/webhook/whatsapp
- **Upload leads:** open WF-01 in the n8n editor, click the "Upload Leads
  CSV" node, copy its **Production URL**, open that URL in a browser, pick
  `data/sample_leads.csv`.
- **Call simulator:** opens automatically from the dashboard's "Call now"
  button when `app_config.call_mode = 'simulated'`.

### Switching between live and simulated calls

```sql
-- go live (only allowlisted numbers will actually ring, per demo_mode)
update app_config set value = 'live_bolna' where key = 'call_mode';

-- back to the safe browser fallback
update app_config set value = 'simulated' where key = 'call_mode';
```

### Reset demo data (keep config and property facts)

```sql
truncate table audit_events, appointments, followup_tasks, messages,
  call_attempts, import_rejects, leads restart identity cascade;
```

Run this in the Supabase SQL Editor before every rehearsal. It does **not**
touch `app_config` or `properties`, so your allowlist/model/agent settings
survive a reset.

---

## 7. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `n8n` command not found | Re-run `npm install n8n -g`; if it still fails, try `npx n8n` once as a smoke test, or check for a corporate proxy blocking npm. |
| Postgres credential "Test" fails | Supabase free projects pause after inactivity — open the Supabase dashboard once to wake it, then retry. Also confirm you used the **Session pooler** host/port, not the direct connection. |
| Dashboard/inbox/simulator page is blank or 404 | Workflow not Active, or the `Read ... Page` node's file path wasn't updated to this machine's real path. |
| `/webhook/...` URL returns "workflow not registered" | The workflow is not Active, or n8n was restarted after you last activated it — toggle Active again. |
| Call blocked with `not_in_demo_allowlist` | Expected while `demo_mode = true` and the number isn't in `call_allowlist` — this is the safety net, not a bug. |
| Bolna call never completes / WF-03 loops forever | Check the `Get Execution` node's URL/auth against Bolna's current API reference (marked TODO in WF-03) — the path or status strings this build guessed may not match. Inspect one real response in the n8n execution log and adjust `Check Finished`'s field names. |
| OpenAI node/HTTP Request returns 401/429 | Credential not selected, or the OpenAI project has no billing/credit — add a small prepaid top-up. |
| Classification always goes to "review" | Open the `Classify Call` or `Classify Reply` execution in n8n and inspect the raw OpenAI response — the parsing code expects `choices[0].message.content` to be a JSON object; a non-JSON model response (wrong model name, or `response_format` unsupported by that model) will fail validation by design. |
| Microphone doesn't work in the simulator | Chrome blocks mic access on non-HTTPS origins except `localhost` — make sure you're opening `http://localhost:5678/...`, not a LAN IP. Text input always works as a fallback. |

---

## Credentials checklist (create once in n8n → Credentials)

| Name | Type | Used by |
|---|---|---|
| Rudvaya Supabase Postgres | Postgres | every workflow except WF-07's HTTP-only nodes |
| Rudvaya OpenAI | OpenAi | WF-03 Classify Call, WF-04 Classify Reply, WF-07 Agent Reply |
| Rudvaya Bolna API | Bolna API (community node credential) | WF-02 Bolna: Make Call, WF-03 Get Execution |

## What's free vs paid, live vs simulated

- **Free:** n8n, Node.js, Chrome, Supabase free tier, Bolna's $5 signup
  credit, the dashboard/inbox/simulator pages (served by n8n, no external
  host).
- **Paid (small, demo-only):** OpenAI usage (expect well under ₹100 for the
  whole build + demo) and possibly a one-time OpenAI prepaid top-up
  (commonly $5 / ≈ ₹450) if your account has no balance yet.
- **Paid, production only, NOT built here:** real WhatsApp (Meta Cloud
  API), an Indian 140-series number for promotional calling, TRAI
  registration, a hosted n8n server with HTTPS.
- **LIVE:** any call placed through `Bolna: Make Call` when
  `app_config.call_mode = 'live_bolna'` and the number is on the allowlist.
- **SIMULATED, always:** every WhatsApp message (`messages.simulated =
  true` on every row, no exception), and every call attempt with
  `call_attempts.mode = 'simulated'` run through the browser simulator.

## Resolved since initial build

These were originally marked TODO/best-guess; they're now confirmed against
the installed `n8n-nodes-bolna` v0.1.2 source and Bolna's public API docs,
and WF-02/WF-03 were updated to match:

- **WF-03 "Get Execution"** is now the actual Bolna node (resource=call,
  operation=get) instead of a raw HTTP Request — it calls `GET
  /executions/{executionId}` with `Authorization: Bearer <key>` handled
  automatically by the `Rudvaya Bolna API` credential.
- **Terminal call statuses** (`Check Finished` in WF-03): confirmed full
  list is `scheduled, queued, rescheduled, initiated, ringing, in-progress`
  (in-flight) vs. `call-disconnected, completed, balance-low, busy,
  no-answer, canceled, failed, stopped, error` (terminal).
- **Get Execution response fields**: `status`, `transcript`, `summary`,
  `conversation_duration`, `telephony_data.duration`,
  `telephony_data.recording_url` — all confirmed from Bolna's live docs.
- **WF-02 "Bolna: Make Call"** parameters (`agentId`, `recipientPhoneNumber`,
  `additionalFields.userData`) were already correct; confirmed byte-for-byte
  against the installed node's source.
- **POST /call response field for the new call's id**: confirmed as
  `execution_id` (not `id`) — `Save Execution ID` and `Start Result Poller`
  in WF-02 were updated accordingly.
- No separate Header Auth credential is needed for WF-03 — it reuses
  `Rudvaya Bolna API`.

## Open TODOs (do not demo until resolved)

1. Confirm your n8n version's exact Form Trigger / Form completion node
   behaviour (WF-01) — some n8n releases handle the "completion page"
   directly on the Form Trigger node instead of a separate `n8n-nodes-base.form`
   node.
2. After importing all seven workflows, go back and fill in every
   `REPLACE_WITH_WF0X_WORKFLOW_ID` and `REPLACE_WITH_THIS_WORKFLOWS_OWN_ID`
   placeholder in the `Execute Workflow` nodes.
3. Replace the three `C:\REPLACE\...` file paths for the dashboard,
   WhatsApp inbox and simulator pages.
4. Run every test in `TESTS.md` and record PASS/FAIL before the first
   rehearsal.
