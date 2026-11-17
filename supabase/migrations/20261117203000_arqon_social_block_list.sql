-- Extend the community hub with a privacy-aware list of accounts blocked by the current user.
create or replace function public.get_arqon_social_connections(p_section text)
returns table (
  user_id uuid,
  arqon_id bigint,
  display_name text,
  avatar_url text,
  created_at timestamptz,
  request_id bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_section not in ('friends','following','followers','incoming','outgoing','blocked') then
    raise exception 'Invalid social section' using errcode = '22023';
  end if;

  return query
  with connections as (
    select
      case when fr.sender_user_id = v_uid then fr.receiver_user_id else fr.sender_user_id end as connected_user_id,
      fr.created_at, fr.id as request_id
    from public.arqon_friend_requests fr
    where p_section = 'friends' and fr.status = 'accepted'
      and (fr.sender_user_id = v_uid or fr.receiver_user_id = v_uid)

    union all
    select f.followed_user_id, f.created_at, null::bigint
    from public.arqon_follows f
    where p_section = 'following' and f.follower_user_id = v_uid

    union all
    select f.follower_user_id, f.created_at, null::bigint
    from public.arqon_follows f
    where p_section = 'followers' and f.followed_user_id = v_uid

    union all
    select fr.sender_user_id, fr.created_at, fr.id
    from public.arqon_friend_requests fr
    where p_section = 'incoming' and fr.receiver_user_id = v_uid and fr.status = 'pending'

    union all
    select fr.receiver_user_id, fr.created_at, fr.id
    from public.arqon_friend_requests fr
    where p_section = 'outgoing' and fr.sender_user_id = v_uid and fr.status = 'pending'

    union all
    select b.blocked_user_id, b.created_at, null::bigint
    from public.arqon_user_blocks b
    where p_section = 'blocked' and b.blocker_user_id = v_uid
  )
  select c.connected_user_id,
    case when p.is_public then p.arqon_id else null end,
    case when p.is_public
      then coalesce(nullif(p.display_name,''),nullif(p.steam_persona_name,''),'Игрок ARQON')
      else 'Закрытый профиль' end,
    case when p.is_public then coalesce(p.avatar_url,p.steam_avatar_url) else null end,
    c.created_at,c.request_id
  from connections c
  join public.profiles p on p.user_id = c.connected_user_id
  where c.connected_user_id <> v_uid
    and (p_section = 'blocked' or p.is_public = true)
    and (p_section = 'blocked' or not exists (
      select 1 from public.arqon_user_blocks b
      where (b.blocker_user_id = v_uid and b.blocked_user_id = c.connected_user_id)
         or (b.blocker_user_id = c.connected_user_id and b.blocked_user_id = v_uid)
    ))
  order by c.created_at desc
  limit 200;
end;
$$;

revoke all on function public.get_arqon_social_connections(text) from public, anon;
grant execute on function public.get_arqon_social_connections(text) to authenticated;
