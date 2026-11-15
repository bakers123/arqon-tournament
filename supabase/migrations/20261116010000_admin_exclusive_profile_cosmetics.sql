alter table public.profiles
  add column if not exists exclusive_profile_title text,
  add column if not exists exclusive_profile_bg_color text,
  add column if not exists exclusive_avatar_border_color text;

create or replace function public.admin_set_profile_exclusives(
  p_arqon_id bigint,
  p_title text default null,
  p_bg_color text default null,
  p_border_color text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_title text:=nullif(btrim(coalesce(p_title,'')),'');
  v_bg text:=nullif(btrim(coalesce(p_bg_color,'')),'');
  v_border text:=nullif(btrim(coalesce(p_border_color,'')),'');
begin
  if auth.uid() is null or not exists(
    select 1 from private.organizer_roles r
    where r.user_id=auth.uid() and r.role in ('owner','admin')
  ) then
    raise exception 'not_authorized_admin' using errcode='42501';
  end if;
  if p_arqon_id is null or p_arqon_id<1 then raise exception 'Некорректный ARQON ID'; end if;
  if v_title is not null and char_length(v_title)>40 then raise exception 'Титул не должен превышать 40 символов'; end if;
  if v_bg is not null and v_bg !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Цвет фона должен быть в формате #RRGGBB'; end if;
  if v_border is not null and v_border !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Цвет обводки должен быть в формате #RRGGBB'; end if;
  update public.profiles
  set exclusive_profile_title=v_title,
      exclusive_profile_bg_color=v_bg,
      exclusive_avatar_border_color=v_border
  where arqon_id=p_arqon_id;
  if not found then raise exception 'Игрок с таким ARQON ID не найден'; end if;
  return jsonb_build_object('ok',true,'arqon_id',p_arqon_id);
end;
$$;
revoke all on function public.admin_set_profile_exclusives(bigint,text,text,text) from public,anon;
grant execute on function public.admin_set_profile_exclusives(bigint,text,text,text) to authenticated;

drop function if exists public.get_public_arqon_profile(bigint);
create function public.get_public_arqon_profile(p_arqon_id bigint)
returns table(
 arqon_id bigint,display_name text,player_name text,bio text,avatar_url text,cover_url text,steam_id text,
 created_at timestamptz,cs2_faceit_url text,cs2_faceit_elo integer,dota2_profile_url text,dota2_mmr integer,
 equipped_frame_id text,equipped_theme_id text,equipped_title_id text,equipped_badge_id text,
 exclusive_profile_title text,exclusive_profile_bg_color text,exclusive_avatar_border_color text
)
language sql stable security definer set search_path=''
as $$
 select p.arqon_id,
   coalesce(nullif(p.display_name,''),nullif(p.steam_persona_name,''),pl.name,'Игрок ARQON'),
   pl.name,p.bio,coalesce(p.avatar_url,p.steam_avatar_url),p.cover_url,
   case when p.show_steam then p.steam_id else null end,p.created_at,
   p.cs2_faceit_url,p.cs2_faceit_elo,p.dota2_profile_url,p.dota2_mmr,
   p.equipped_frame_id,p.equipped_theme_id,p.equipped_title_id,p.equipped_badge_id,
   p.exclusive_profile_title,p.exclusive_profile_bg_color,p.exclusive_avatar_border_color
 from public.profiles p left join public.players pl on pl.uid=p.user_id::text
 where p.arqon_id=p_arqon_id and p.is_public=true limit 1;
$$;
revoke all on function public.get_public_arqon_profile(bigint) from public;
grant execute on function public.get_public_arqon_profile(bigint) to anon,authenticated;

create or replace function private.guard_profile_exclusive_cosmetics()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.exclusive_profile_title is distinct from old.exclusive_profile_title
     or new.exclusive_profile_bg_color is distinct from old.exclusive_profile_bg_color
     or new.exclusive_avatar_border_color is distinct from old.exclusive_avatar_border_color then
    if auth.uid() is null or not exists(
      select 1 from private.organizer_roles r
      where r.user_id=auth.uid() and r.role in ('owner','admin')
    ) then
      raise exception 'Изменять эксклюзивное оформление может только администрация ARQON'
        using errcode='42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.guard_profile_exclusive_cosmetics() from public,anon,authenticated;
drop trigger if exists guard_profile_exclusive_cosmetics on public.profiles;
create trigger guard_profile_exclusive_cosmetics
before update on public.profiles
for each row execute function private.guard_profile_exclusive_cosmetics();
