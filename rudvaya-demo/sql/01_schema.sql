-- ============================================================================
-- Rudvaya AI Lead Automation — DEMO schema (Supabase / PostgreSQL)
-- Run once in the Supabase SQL Editor (Project → SQL Editor → New query).
-- Matches plan §6.1. Two deliberate additions over the plan text, explained
-- inline, to support nodes described elsewhere in the same plan:
--   1. leads.has_active_appointment is NOT a stored column (the plan's WF-02
--      eligibility gate reads it as a derived value) — computed in the WF-02
--      "Load Lead + Config" query instead. No schema change needed, noted
--      here so it isn't mistaken for a missing column.
--   2. Added `updated_at` trigger-free touch via explicit SET in UPDATE
--      statements (already specified in the plan's queries) — no DB trigger
--      added, to keep behaviour fully visible inside the workflow JSON.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Configuration: every workflow reads this table first. No secrets here.
-- ---------------------------------------------------------------------------
create table app_config (
  key text primary key,
  value text not null,
  note text
);

-- ---------------------------------------------------------------------------
-- Verified property facts — the only facts the AI agent may state.
-- ---------------------------------------------------------------------------
create table properties (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  location text,
  configurations text,
  price_range text,
  amenities text,
  faqs text,
  last_verified_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- Leads: one row per unique phone per client. Unique constraint = dedupe.
-- ---------------------------------------------------------------------------
create table leads (
  id uuid primary key default gen_random_uuid(),
  client_id text not null default 'demo',
  name text not null,
  phone_e164 text not null,
  email text,
  source text,
  property_interest text,
  budget text,
  location text,
  consent boolean not null default false,
  consent_source text,
  consent_at timestamptz,
  do_not_contact boolean not null default false,
  status text not null default 'new',
    -- new | contacting | interested | callback | visit_requested |
    -- not_interested | opted_out | review | escalated
  attempt_count int not null default 0,
  is_demo boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (client_id, phone_e164)
);

-- ---------------------------------------------------------------------------
-- Import rejects: every duplicate / invalid CSV row, with reason.
-- ---------------------------------------------------------------------------
create table import_rejects (
  id uuid primary key default gen_random_uuid(),
  raw jsonb,
  reason text,
  created_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- Call attempts: every call, live or simulated. Idempotency key stops
-- double-dialing the same lead for the same reason/attempt.
-- ---------------------------------------------------------------------------
create table call_attempts (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references leads(id) on delete cascade,
  mode text not null check (mode in ('live_bolna','simulated')),
  reason text default 'first_call', -- first_call | callback | manual
  provider_call_id text,            -- Bolna execution_id
  status text not null default 'created',
  poll_count int default 0,
  started_at timestamptz default now(),
  ended_at timestamptz,
  duration_seconds int,
  transcript text,
  summary text,
  classification jsonb,
  recording_url text,
  idempotency_key text unique
);

-- ---------------------------------------------------------------------------
-- Messages: mock WhatsApp outbox/inbox. simulated = true for every demo row.
-- ---------------------------------------------------------------------------
create table messages (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references leads(id) on delete cascade,
  channel text default 'whatsapp',
  direction text check (direction in ('out','in')),
  template_name text,
  body text,
  status text default 'sent', -- sent | delivered | read | received
  simulated boolean not null default true,
  created_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- Follow-up tasks: scheduled callbacks. Claimed with row locks (WF-05).
-- ---------------------------------------------------------------------------
create table followup_tasks (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references leads(id) on delete cascade,
  task_type text default 'callback',
  due_at timestamptz not null,
  status text not null default 'pending', -- pending | processing | done | cancelled
  attempt_count int default 0,
  locked_at timestamptz,
  completed_at timestamptz,
  cancellation_reason text,
  created_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- Appointments: site / office visit requests, staff-confirmed from dashboard.
-- ---------------------------------------------------------------------------
create table appointments (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references leads(id) on delete cascade,
  type text check (type in ('site_visit','office_visit')),
  requested_time_text text,
  scheduled_at timestamptz,
  status text default 'requested', -- requested | confirmed | cancelled | done
  assigned_to text,
  notes text,
  simulated boolean default false,
  created_at timestamptz default now()
);

-- ---------------------------------------------------------------------------
-- Audit events: who did what and why (blocked calls, opt-outs, escalations).
-- ---------------------------------------------------------------------------
create table audit_events (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid,
  actor text,
  event_type text,
  details jsonb,
  created_at timestamptz default now()
);

create index on followup_tasks (status, due_at);
create index on call_attempts (lead_id);
create index on messages (lead_id, created_at);

-- ---------------------------------------------------------------------------
-- Dashboard view: one row of KPIs, read by WF-06 GET /api/stats.
-- ---------------------------------------------------------------------------
create view v_dashboard as
select
  (select count(*) from leads) as total_leads,
  (select count(*) from import_rejects where reason like 'duplicate%') as duplicates,
  (select count(*) from import_rejects where reason not like 'duplicate%') as invalid,
  (select count(*) from call_attempts) as calls_attempted,
  (select count(*) from call_attempts where status='completed') as calls_answered,
  (select count(*) from call_attempts where status in ('no-answer','busy','failed')) as calls_no_answer,
  (select count(*) from leads where status in ('interested','visit_requested')) as interested,
  (select count(*) from leads where status='not_interested') as not_interested,
  (select count(*) from leads where do_not_contact) as opted_out,
  (select count(*) from followup_tasks where status='pending') as pending_callbacks,
  (select count(*) from appointments where type='site_visit') as site_visits,
  (select count(*) from appointments where type='office_visit') as office_visits,
  (select count(*) from call_attempts where mode='live_bolna') as live_calls,
  (select count(*) from call_attempts where mode='simulated') as simulated_calls;
