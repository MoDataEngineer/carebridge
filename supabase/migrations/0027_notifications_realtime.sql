-- Ayulekha — live notification feed (Gap B, founder 2026-07-18).
--
-- The patient app now streams the notifications table (unread bell badge +
-- arrival chime). Realtime only emits for tables in the supabase_realtime
-- publication — appointments was added in the queue phase; notifications
-- joins it here. RLS still scopes every event to the patient's own rows.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table notifications;
  end if;
end $$;
