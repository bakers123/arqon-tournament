-- Replace the SECURITY DEFINER view with a narrowly scoped name-only RPC.
drop view if exists public.player_directory;

create or replace function public.list_public_player_names()
returns table(name text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.name
  from public.players as p
  where p.name is not null and btrim(p.name) <> ''
  order by p.name;
$$;

revoke all on function public.list_public_player_names() from public;
grant execute on function public.list_public_player_names() to anon, authenticated;
