-- Allow administrators to upload animated GIF assets for exclusive profile backgrounds and avatar borders.
update storage.buckets
set allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif']
where id = 'admin-profile-cosmetics';
