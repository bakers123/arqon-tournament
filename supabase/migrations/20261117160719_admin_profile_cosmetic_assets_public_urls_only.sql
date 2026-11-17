-- Public buckets serve known object URLs directly; do not grant object listing through storage.objects.
drop policy if exists "Admins read profile cosmetic assets" on storage.objects;
