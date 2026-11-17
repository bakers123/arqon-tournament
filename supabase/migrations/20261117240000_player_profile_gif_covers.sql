-- Allow animated GIFs for player profile covers.
-- Preserve existing bucket visibility, 5 MB limit, and Storage RLS policies.
update storage.buckets
set allowed_mime_types = (
  select array_agg(distinct mime_type order by mime_type)
  from unnest(coalesce(allowed_mime_types, array[]::text[]) || array['image/gif']::text[]) as mime_type
)
where id = 'player-media';
