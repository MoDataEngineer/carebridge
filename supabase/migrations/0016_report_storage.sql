-- CareBridge — Audit fix H3: lab report FILES gated by the SAME grant logic as
-- rows (Section 10 "File storage security"), enforced at the storage layer.
--
-- Bucket 'reports' is PRIVATE. Object paths are '<test_order_id>/<filename>',
-- so every storage policy can resolve the parent order from the path and reuse
-- the Flow C trust rules:
--   * upload  -> only the partner holding an ACTIVE order-scoped grant
--                (grant closes on report upload => further uploads denied);
--   * read    -> the patient who owns the order, a clinic scope that may view
--                that patient (AC-8 included), or the partner while its grant
--                is still open;
--   * no client update/delete at all.
-- Viewers fetch short-lived signed URLs; creating one requires passing these
-- SELECT policies, so the app layer can never hand out a file RLS would deny.

insert into storage.buckets (id, name, public)
  values ('reports', 'reports', false)
  on conflict (id) do nothing;

-- Parent order id from the object path ('<order_id>/<file>').
-- (storage.foldername(objects.name))[1] is the first folder segment.
-- ALWAYS qualified as objects.name: subqueries joining doctors/patients would
-- otherwise SHADOW `name` with their own column, silently parsing a person's
-- name as the path (found the hard way — see rls_storage.sql).

drop policy if exists reports_upload_partner on storage.objects;
create policy reports_upload_partner on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'reports'
    and public.current_partner_holds_order(((storage.foldername(objects.name))[1])::uuid)
  );

drop policy if exists reports_select_patient on storage.objects;
create policy reports_select_patient on storage.objects
  for select to authenticated
  using (
    bucket_id = 'reports'
    and exists (
      select 1 from test_orders o
      where o.id = ((storage.foldername(objects.name))[1])::uuid
        and o.patient_id = public.current_patient_id()
    )
  );

drop policy if exists reports_select_clinic on storage.objects;
create policy reports_select_clinic on storage.objects
  for select to authenticated
  using (
    bucket_id = 'reports'
    and exists (
      select 1 from test_orders o
      join doctors d on d.id = o.doctor_id
      where o.id = ((storage.foldername(objects.name))[1])::uuid
        and d.clinic_id = public.current_clinic_id()
        and public.current_scope_can_view_patient(o.patient_id)
    )
  );

-- Partner may re-read its own upload only while the grant is still open
-- (it closes the moment carebridge_upload_report records the report).
drop policy if exists reports_select_partner on storage.objects;
create policy reports_select_partner on storage.objects
  for select to authenticated
  using (
    bucket_id = 'reports'
    and public.current_partner_holds_order(((storage.foldername(objects.name))[1])::uuid)
  );
