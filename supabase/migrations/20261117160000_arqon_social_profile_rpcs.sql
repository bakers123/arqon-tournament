-- ARQON social profile RPCs.
-- These functions expose only public-profile relationship state and the caller's own incoming requests.

create or replace function public.get_arqon_social_profile_state(p_arqon_id bigint)
returns table (
  target_user_id uuid,
  is_following boolean,
  follows_you boolean,
  friend_status text,
  outgoing_request_id bigint,
  incoming_request_id bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with target as (
    select p.user_id
    from public.profiles p
    where p.arqon_id = p_arqon_id
      and p.is_public = true
    limit 1
  ),
  relation_rows as (
    select fr.id, fr.sender_user_id, fr.receiver_user_id, fr.status
    from public.arqon_friend_requests fr
    join target t on (
      (fr.sender_user_id = (select auth.uid()) and fr.receiver_user_id = t.user_id)
      or (fr.sender_user_id = t.user_id and fr.receiver_user_id = (select auth.uid()))
    )
  )
  select
    t.user_id,
    exists (
      select 1 from public.arqon_follows f
      where f.follower_user_id = (select auth.uid())
        and f.followed_user_id = t.user_id
    ),
    exists (
      select 1 from public.arqon_follows f
      where f.follower_user_id = t.user_id
        and f.followed_user_id = (select auth.uid())
    ),
    case
      when exists (select 1 from relation_rows r where r.status = 'accepted') then 'accepted'
      when exists (select 1 from relation_rows r where r.status = 'pending' and r.sender_user_id = (select auth.uid())) then 'outgoing_pending'
      when exists (select 1 from relation_rows r where r.status = 'pending' and r.receiver_user_id = (select auth.uid())) then 'incoming_pending'
      when exists (select 1 from relation_rows r where r.status = 'declined') then 'declined'
      else null
    end,
    (select r.id from relation_rows r where r.status = 'pending' and r.sender_user_id = (select auth.uid()) order by r.created_at desc limit 1),
    (select r.id from relation_rows r where r.status = 'pending' and r.receiver_user_id = (select auth.uid()) order by r.created_at desc limit 1)
  from target t
  where (select auth.uid()) is not null
    and t.user_id <> (select auth.uid());
$$;

create or replace function public.get_arqon_incoming_friend_requests()
returns table (
  request_id bigint,
  sender_arqon_id bigint,
  sender_name text,
  sender_avatar_url text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    fr.id,
    p.arqon_id,
    coalesce(nullif(p.display_name, ''), nullif(p.steam_persona_name, ''), pl.name, 'Игрок ARQON'),
    coalesce(p.avatar_url, p.steam_avatar_url),
    fr.created_at
  from public.arqon_friend_requests fr
  join public.profiles p on p.user_id = fr.sender_user_id
  left join public.players pl on pl.uid = fr.sender_user_id::text
  where fr.receiver_user_id = (select auth.uid())
    and fr.status = 'pending'
    and (select auth.uid()) is not null
  order by fr.created_at desc
  limit 100;
$$;

revoke all on function public.get_arqon_social_profile_state(bigint) from public, anon;
revoke all on function public.get_arqon_incoming_friend_requests() from public, anon;
grant execute on function public.get_arqon_social_profile_state(bigint) to authenticated;
grant execute on function public.get_arqon_incoming_friend_requests() to authenticated;
