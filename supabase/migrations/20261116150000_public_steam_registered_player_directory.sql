-- Public directory for self-registered Steam accounts that are not linked to
-- an organizer-created roster entry. Never expose Steam IDs, auth UUIDs or email.
create or replace function public.list_public_steam_registered_profiles()
returns table (
  arqon_id bigint,
  display_name text,
  steam_persona_name text,
  avatar_url text,
  steam_avatar_url text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    pr.arqon_id,
    coalesce(nullif(btrim(pr.display_name), ''), nullif(btrim(pr.steam_persona_name), ''), 'Игрок ARQON #' || pr.arqon_id::text) as display_name,
    pr.steam_persona_name,
    pr.avatar_url,
    pr.steam_avatar_url,
    pr.created_at
  from public.profiles pr
  where pr.is_public = true
    and pr.steam_id is not null
    and btrim(pr.steam_id) <> ''
    and not exists (
      select 1
      from public.players pl
      where pl.uid = pr.user_id::text
    )
  order by pr.created_at desc, pr.arqon_id;
$$;

revoke all on function public.list_public_steam_registered_profiles() from public;
grant execute on function public.list_public_steam_registered_profiles() to anon, authenticated;
