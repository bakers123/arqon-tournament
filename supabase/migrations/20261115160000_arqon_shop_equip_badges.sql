-- Allow players to equip ARQON shop badges and show them on public profiles.
alter table public.profiles add column if not exists equipped_badge_id text;

create or replace function public.arqon_shop_equip(p_item_id text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_user uuid; v_arqon_id bigint; v_item public.arqon_shop_items%rowtype;
begin
  v_user:=auth.uid();
  if v_user is null then raise exception 'Войди в аккаунт ARQON'; end if;
  select arqon_id into v_arqon_id from public.profiles where user_id=v_user;
  if v_arqon_id is null then raise exception 'Профиль ARQON не найден'; end if;
  if p_item_id is not null then
    select i.* into v_item from public.arqon_shop_items i
    join public.arqon_shop_inventory inv on inv.item_id=i.id and inv.arqon_id=v_arqon_id
    where i.id=p_item_id and i.is_active=true;
    if not found then raise exception 'Предмет не найден в твоём инвентаре'; end if;
    if v_item.category='frame' then update public.profiles set equipped_frame_id=v_item.id where arqon_id=v_arqon_id;
    elsif v_item.category='theme' then update public.profiles set equipped_theme_id=v_item.id where arqon_id=v_arqon_id;
    elsif v_item.category='title' then update public.profiles set equipped_title_id=v_item.id where arqon_id=v_arqon_id;
    elsif v_item.category='badge' then update public.profiles set equipped_badge_id=v_item.id where arqon_id=v_arqon_id;
    else raise exception 'Этот предмет нельзя экипировать'; end if;
  else
    update public.profiles set equipped_frame_id=null,equipped_theme_id=null,equipped_title_id=null,equipped_badge_id=null where arqon_id=v_arqon_id;
  end if;
  return jsonb_build_object('ok',true);
end;
$function$;

drop function if exists public.get_public_arqon_profile(bigint);
create function public.get_public_arqon_profile(p_arqon_id bigint)
returns table(
 arqon_id bigint,display_name text,player_name text,bio text,avatar_url text,cover_url text,steam_id text,
 created_at timestamptz,cs2_faceit_url text,cs2_faceit_elo integer,dota2_profile_url text,dota2_mmr integer,
 equipped_frame_id text,equipped_theme_id text,equipped_title_id text,equipped_badge_id text
)
language sql stable security definer set search_path=''
as $$
 select p.arqon_id,
   coalesce(nullif(p.display_name,''),nullif(p.steam_persona_name,''),pl.name,'Игрок ARQON'),
   pl.name,p.bio,coalesce(p.avatar_url,p.steam_avatar_url),p.cover_url,
   case when p.show_steam then p.steam_id else null end,p.created_at,
   p.cs2_faceit_url,p.cs2_faceit_elo,p.dota2_profile_url,p.dota2_mmr,
   p.equipped_frame_id,p.equipped_theme_id,p.equipped_title_id,p.equipped_badge_id
 from public.profiles p left join public.players pl on pl.uid=p.user_id::text
 where p.arqon_id=p_arqon_id and p.is_public=true limit 1;
$$;
revoke all on function public.get_public_arqon_profile(bigint) from public;
grant execute on function public.get_public_arqon_profile(bigint) to anon,authenticated;
