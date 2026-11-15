-- Public-safe player profile fields and lookup by ARQON ID.
-- The public RPC intentionally omits user UUIDs, email addresses and private Steam IDs.

alter table public.profiles
  add column if not exists bio text not null default '',
  add column if not exists avatar_url text,
  add column if not exists cover_url text,
  add column if not exists is_public boolean not null default true,
  add column if not exists show_steam boolean not null default false;

alter table public.profiles
  drop constraint if exists profiles_bio_length_check;
alter table public.profiles
  add constraint profiles_bio_length_check check (char_length(bio) <= 280);

alter table public.profiles
  drop constraint if exists profiles_avatar_url_check;
alter table public.profiles
  add constraint profiles_avatar_url_check
  check (avatar_url is null or (avatar_url like 'https://%' and char_length(avatar_url) <= 2048));

alter table public.profiles
  drop constraint if exists profiles_cover_url_check;
alter table public.profiles
  add constraint profiles_cover_url_check
  check (cover_url is null or (cover_url like 'https://%' and char_length(cover_url) <= 2048));

grant update (display_name, bio, avatar_url, cover_url, is_public, show_steam)
  on public.profiles to authenticated;

create or replace function public.get_public_arqon_profile(p_arqon_id bigint)
returns table (
  arqon_id bigint,
  display_name text,
  player_name text,
  bio text,
  avatar_url text,
  cover_url text,
  steam_id text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.arqon_id,
    coalesce(nullif(p.display_name, ''), pl.name, 'Игрок ARQON') as display_name,
    pl.name as player_name,
    p.bio,
    p.avatar_url,
    p.cover_url,
    case when p.show_steam then p.steam_id else null end as steam_id,
    p.created_at
  from public.profiles p
  left join public.players pl on pl.uid = p.user_id::text
  where p.arqon_id = p_arqon_id
    and p.is_public = true
  limit 1;
$$;

revoke all on function public.get_public_arqon_profile(bigint) from public;
grant execute on function public.get_public_arqon_profile(bigint) to anon, authenticated;
