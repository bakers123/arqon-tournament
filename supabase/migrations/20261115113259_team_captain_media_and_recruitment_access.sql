
drop policy if exists team_media_captain_insert on storage.objects;
create policy team_media_captain_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='team-media'
  and exists (
    select 1 from public.team_profiles tp
    join public.profiles p on p.arqon_id=tp.captain_arqon_id
    where tp.team_id=(storage.foldername(name))[1]
      and p.user_id=(select auth.uid())
  )
);

drop policy if exists team_media_captain_update on storage.objects;
create policy team_media_captain_update on storage.objects
for update to authenticated
using (
  bucket_id='team-media'
  and exists (
    select 1 from public.team_profiles tp
    join public.profiles p on p.arqon_id=tp.captain_arqon_id
    where tp.team_id=(storage.foldername(name))[1]
      and p.user_id=(select auth.uid())
  )
)
with check (
  bucket_id='team-media'
  and exists (
    select 1 from public.team_profiles tp
    join public.profiles p on p.arqon_id=tp.captain_arqon_id
    where tp.team_id=(storage.foldername(name))[1]
      and p.user_id=(select auth.uid())
  )
);

drop policy if exists team_media_captain_delete on storage.objects;
create policy team_media_captain_delete on storage.objects
for delete to authenticated
using (
  bucket_id='team-media'
  and exists (
    select 1 from public.team_profiles tp
    join public.profiles p on p.arqon_id=tp.captain_arqon_id
    where tp.team_id=(storage.foldername(name))[1]
      and p.user_id=(select auth.uid())
  )
);

drop policy if exists recruitment_request_captain_read on public.team_recruitment_requests;
create policy recruitment_request_captain_read on public.team_recruitment_requests
for select to authenticated
using (
  user_id=(select auth.uid())
  or public.has_organizer_role('editor')
  or exists (
    select 1 from public.team_profiles tp
    join public.profiles captain on captain.arqon_id=tp.captain_arqon_id
    where tp.team_id=team_recruitment_requests.team_id
      and captain.user_id=(select auth.uid())
  )
);

drop policy if exists recruitment_request_captain_update on public.team_recruitment_requests;
create policy recruitment_request_captain_update on public.team_recruitment_requests
for update to authenticated
using (
  public.has_organizer_role('editor')
  or exists (
    select 1 from public.team_profiles tp
    join public.profiles captain on captain.arqon_id=tp.captain_arqon_id
    where tp.team_id=team_recruitment_requests.team_id
      and captain.user_id=(select auth.uid())
  )
)
with check (
  status = any(array['accepted','rejected'])
  and reviewed_by=(select auth.uid())
  and (
    public.has_organizer_role('editor')
    or exists (
      select 1 from public.team_profiles tp
      join public.profiles captain on captain.arqon_id=tp.captain_arqon_id
      where tp.team_id=team_recruitment_requests.team_id
        and captain.user_id=(select auth.uid())
    )
  )
);
