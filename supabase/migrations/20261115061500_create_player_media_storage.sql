-- Public profile media bucket: public reads, owner-only writes.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('player-media','player-media',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Public player media read" on storage.objects;
create policy "Public player media read"
on storage.objects for select to anon, authenticated
using (bucket_id = 'player-media');

drop policy if exists "Players upload own media" on storage.objects;
create policy "Players upload own media"
on storage.objects for insert to authenticated
with check (bucket_id = 'player-media' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "Players update own media" on storage.objects;
create policy "Players update own media"
on storage.objects for update to authenticated
using (bucket_id = 'player-media' and (storage.foldername(name))[1] = (select auth.uid())::text)
with check (bucket_id = 'player-media' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "Players delete own media" on storage.objects;
create policy "Players delete own media"
on storage.objects for delete to authenticated
using (bucket_id = 'player-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
