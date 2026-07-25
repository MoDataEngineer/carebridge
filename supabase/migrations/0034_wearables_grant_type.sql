-- CareBridge — Wearables epic (D14), Phase 12: add the 'wearable' grant scope.
--
-- ISOLATED in its own migration ON PURPOSE. Postgres forbids using a newly
-- added enum value later in the SAME transaction ("unsafe use of new value").
-- Supabase runs each migration file in its own transaction, so the tables,
-- helper and policies that reference 'wearable' live in 0035 — which runs after
-- this one has committed.
--
-- The wearable scope is a SEPARATE, revocable, patient-initiated consent
-- (CLAUDE.md §15): a plain clinical 'standing' grant must never confer vitals
-- access, and clinic admins do NOT auto-inherit it (no AC-8 for wearables).

alter type grant_type add value if not exists 'wearable';
