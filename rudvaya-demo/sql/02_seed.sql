-- ============================================================================
-- Rudvaya AI Lead Automation — DEMO seed data
-- Run AFTER 01_schema.sql, once, in the Supabase SQL Editor.
--
-- *** REPLACE BEFORE TESTING ***
--   call_allowlist   -> your + colleague's Bolna-VERIFIED numbers (E.164)
--   bolna_agent_id   -> agent_id copied from the Bolna dashboard
--   openai_model     -> exact model name available to your OpenAI account
-- ============================================================================

insert into app_config (key, value, note) values
  ('demo_mode',              'true',                          'true = only allowlisted numbers can be called'),
  ('call_allowlist',         '+91XXXXXXXXXX,+91YYYYYYYYYY',   'REPLACE: your + colleague verified numbers, comma separated'),
  ('call_mode',              'simulated',                     'live_bolna | simulated — start in simulated until Bolna is verified'),
  ('bolna_agent_id',         'PASTE_AGENT_ID',                'REPLACE: from Bolna dashboard after agent is created'),
  ('openai_model',           'PASTE_MODEL_NAME',              'REPLACE: small current model available to your account'),
  ('callback_delay_minutes','2',                              'demo: 2 | production: 1440 (24h)'),
  ('max_attempts',           '3',                             'max automated call attempts per lead'),
  ('call_window_start',      '00:00',                         'Asia/Kolkata — widened for demo flexibility; set to 10:00 for production-like testing'),
  ('call_window_end',        '23:59',                         'Asia/Kolkata — widened for demo flexibility; set to 19:00 for production-like testing'),
  ('poll_interval_seconds',  '15',                             'WF-03 polling interval'),
  ('poll_max',               '40',                             'give up after 40 polls (10 min)');

insert into properties (name, location, configurations, price_range, amenities, faqs)
values (
  'Aranya Heights (fictional demo project)',
  'Gangapur Road area, Nashik (fictional)',
  '2 BHK (approx. 950 sq ft), 3 BHK (approx. 1,350 sq ft)',
  '2 BHK from Rs 58 lakh, 3 BHK from Rs 82 lakh (demo figures)',
  'Clubhouse, swimming pool, children''s play area, 24x7 security, covered parking',
  'Possession: December 2027 (demo). Site visits: daily 10am-6pm. Home loan tie-ups: available (demo).'
);
