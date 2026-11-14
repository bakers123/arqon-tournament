-- Enforce team avatar upload constraints at the Storage service layer.
-- The frontend already accepts JPG, PNG and WebP up to 5 MiB.
UPDATE storage.buckets
SET file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp']::text[],
    updated_at = now()
WHERE id = 'team-avatars';
