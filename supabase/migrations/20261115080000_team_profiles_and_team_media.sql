create table if not exists public.team_profiles (
 team_id text primary key check (char_length(team_id) between 1 and 80),
 team_name text not null check (char_length(team_name) between 1 and 100),
 description text not null default '' check (char_length(description)<=600),
 logo_url text, cover_url text,
 captain_arqon_id bigint references public.profiles(arqon_id) on delete set null,
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id)
);
alter table public.team_profiles enable row level security;
revoke all on public.team_profiles from anon,public;
grant select on public.team_profiles to anon,authenticated;
grant insert,update,delete on public.team_profiles to authenticated;
drop policy if exists team_profiles_public_read on public.team_profiles;
create policy team_profiles_public_read on public.team_profiles for select to anon,authenticated using(true);
drop policy if exists team_profiles_editor_insert on public.team_profiles;
create policy team_profiles_editor_insert on public.team_profiles for insert to authenticated with check(public.has_organizer_role('editor') and updated_by=(select auth.uid()));
drop policy if exists team_profiles_editor_update on public.team_profiles;
create policy team_profiles_editor_update on public.team_profiles for update to authenticated using(public.has_organizer_role('editor')) with check(public.has_organizer_role('editor') and updated_by=(select auth.uid()));
drop policy if exists team_profiles_editor_delete on public.team_profiles;
create policy team_profiles_editor_delete on public.team_profiles for delete to authenticated using(public.has_organizer_role('editor'));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('team-media','team-media',true,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists team_media_public_read on storage.objects;
create policy team_media_public_read on storage.objects for select to anon,authenticated using(bucket_id='team-media');
drop policy if exists team_media_editor_insert on storage.objects;
create policy team_media_editor_insert on storage.objects for insert to authenticated with check(bucket_id='team-media' and public.has_organizer_role('editor'));
drop policy if exists team_media_editor_update on storage.objects;
create policy team_media_editor_update on storage.objects for update to authenticated using(bucket_id='team-media' and public.has_organizer_role('editor')) with check(bucket_id='team-media' and public.has_organizer_role('editor'));
drop policy if exists team_media_editor_delete on storage.objects;
create policy team_media_editor_delete on storage.objects for delete to authenticated using(bucket_id='team-media' and public.has_organizer_role('editor'));
