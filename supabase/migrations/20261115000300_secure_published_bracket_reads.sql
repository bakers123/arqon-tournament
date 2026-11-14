-- Keep unpublished bracket working data private while preserving public bracket rendering.
-- Public clients receive only the published snapshot; organizers use a gated editor view.

create or replace view public.published_bracket_documents
with (security_barrier = true)
as
select id, title, format, status, published_data, published_at, updated_at
from public.bracket_documents
where status = 'published' and published_data is not null;

create or replace view public.organizer_bracket_documents
with (security_barrier = true)
as
select id, title, format, status, data, published_data, published_at, updated_at
from public.bracket_documents
where public.has_organizer_role('editor');

revoke select on table public.bracket_documents from anon, authenticated;
grant select on table public.published_bracket_documents to anon, authenticated;
grant select on table public.organizer_bracket_documents to authenticated;
