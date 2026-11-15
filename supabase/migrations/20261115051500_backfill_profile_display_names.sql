-- Backfill ARQON profile display names from existing player records.
-- Idempotent: never overwrite a name the user has already chosen.
update public.profiles p
set display_name = left(trim(pl.name), 32),
    updated_at = now()
from public.players pl
where p.user_id::text = pl.uid
  and (p.display_name is null or trim(p.display_name) = '')
  and pl.name is not null
  and trim(pl.name) <> '';
