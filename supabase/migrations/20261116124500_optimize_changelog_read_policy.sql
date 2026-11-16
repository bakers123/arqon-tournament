-- ARQON public changelog: optimize editor/public read policy and support indexes.
-- The created_by index is also applied here so schema history stays reproducible.
create index if not exists changelog_entries_created_by_idx
  on public.changelog_entries (created_by);

drop policy if exists changelog_read_published_or_editor on public.changelog_entries;
create policy changelog_read_published_or_editor
on public.changelog_entries
for select
to anon, authenticated
using (
  (is_published = true and published_at <= now())
  or ((select auth.uid()) is not null and (select public.has_organizer_role('editor')))
);
