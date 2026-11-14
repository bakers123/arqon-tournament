-- Prevent public and non-organizer users from reading unpublished bracket working data.
-- Public/judges read only the published snapshot; organizers load working data via a guarded RPC.

drop view if exists public.organizer_bracket_documents;
drop view if exists public.published_bracket_documents;

revoke select on table public.bracket_documents from anon, authenticated;
grant select (id, title, format, status, published_data, published_at, updated_at)
  on table public.bracket_documents to anon, authenticated;

drop policy if exists bracket_documents_editor_all on public.bracket_documents;
drop policy if exists bracket_documents_public_published_read on public.bracket_documents;

create policy bracket_documents_public_published_read
  on public.bracket_documents for select to anon
  using (status = 'published' and published_data is not null);

create policy bracket_documents_authenticated_read
  on public.bracket_documents for select to authenticated
  using (
    public.has_organizer_role('editor')
    or (status = 'published' and published_data is not null)
  );

create policy bracket_documents_editor_insert
  on public.bracket_documents for insert to authenticated
  with check (public.has_organizer_role('editor'));

create policy bracket_documents_editor_update
  on public.bracket_documents for update to authenticated
  using (public.has_organizer_role('editor'))
  with check (public.has_organizer_role('editor'));

create policy bracket_documents_editor_delete
  on public.bracket_documents for delete to authenticated
  using (public.has_organizer_role('editor'));

drop policy if exists bracket_assignments_editor_all on public.bracket_assignments;
drop policy if exists bracket_assignments_judge_read_own on public.bracket_assignments;

create policy bracket_assignments_authenticated_read
  on public.bracket_assignments for select to authenticated
  using (
    public.has_organizer_role('editor')
    or judge_user_id = (select auth.uid())
  );

create policy bracket_assignments_editor_insert
  on public.bracket_assignments for insert to authenticated
  with check (public.has_organizer_role('editor'));

create policy bracket_assignments_editor_update
  on public.bracket_assignments for update to authenticated
  using (public.has_organizer_role('editor'))
  with check (public.has_organizer_role('editor'));

create policy bracket_assignments_editor_delete
  on public.bracket_assignments for delete to authenticated
  using (public.has_organizer_role('editor'));

drop policy if exists bracket_audit_editor_read on public.bracket_audit;
drop policy if exists bracket_audit_judge_read_own on public.bracket_audit;

create policy bracket_audit_authenticated_read
  on public.bracket_audit for select to authenticated
  using (
    public.has_organizer_role('editor')
    or actor_id = (select auth.uid())
  );

create view public.published_bracket_documents
with (security_invoker = true, security_barrier = true)
as
select id, title, format, status, published_data, published_at, updated_at
from public.bracket_documents
where status = 'published' and published_data is not null;

grant select on public.published_bracket_documents to anon, authenticated;

create or replace function public.list_organizer_bracket_documents()
returns table (
  id uuid,
  title text,
  format text,
  status text,
  data jsonb,
  published_data jsonb,
  published_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not public.has_organizer_role('editor') then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return query
  select d.id, d.title, d.format, d.status, d.data, d.published_data,
         d.published_at, d.updated_at
  from public.bracket_documents d
  order by d.updated_at desc;
end;
$function$;

revoke all on function public.list_organizer_bracket_documents() from public, anon;
grant execute on function public.list_organizer_bracket_documents() to authenticated;
