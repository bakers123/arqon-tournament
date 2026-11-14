-- Add per-user, server-side throttling for access-code redemption.
create table if not exists private.player_code_attempts (
  user_id uuid primary key,
  window_started_at timestamptz not null,
  attempts integer not null default 0 check (attempts >= 0),
  blocked_until timestamptz
);
alter table private.player_code_attempts enable row level security;
revoke all on table private.player_code_attempts from public, anon, authenticated;

-- Access codes are consumed only through privileged, authorization-checked RPCs.
revoke all on table public.access_codes from public, anon, authenticated;
revoke all on function public.redeem_player_access_code(text, uuid) from public, anon, authenticated;

create or replace function public.redeem_player_access_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_attempts integer;
  v_blocked_until timestamptz;
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_player_name text;
  v_existing_uid text;
  v_uid_name text;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  insert into private.player_code_attempts(user_id, window_started_at, attempts, blocked_until)
  values (v_uid, v_now, 1, null)
  on conflict (user_id) do update
  set window_started_at = case
        when private.player_code_attempts.window_started_at < v_now - interval '15 minutes'
          then v_now else private.player_code_attempts.window_started_at end,
      attempts = case
        when private.player_code_attempts.window_started_at < v_now - interval '15 minutes'
          then 1 else private.player_code_attempts.attempts + 1 end,
      blocked_until = case
        when private.player_code_attempts.window_started_at < v_now - interval '15 minutes'
          then null
        when private.player_code_attempts.attempts + 1 >= 8
          then v_now + interval '15 minutes'
        else private.player_code_attempts.blocked_until end
  returning attempts, blocked_until into v_attempts, v_blocked_until;

  if v_attempts >= 8 or v_blocked_until > v_now then
    return jsonb_build_object(
      'ok', false,
      'error', 'rate_limited',
      'retry_after_seconds', greatest(1, ceil(extract(epoch from (coalesce(v_blocked_until, v_now + interval '15 minutes') - v_now)))::integer)
    );
  end if;

  if v_code !~ '^[A-Z0-9]{6,12}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  select ac.player_name into v_player_name
  from public.access_codes ac where ac.code = v_code for update;
  if v_player_name is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  select p.name into v_uid_name
  from public.players p where p.uid = v_uid::text for update;

  if v_uid_name is not null and v_uid_name <> v_player_name then
    return jsonb_build_object('ok', false, 'error', 'session_already_linked');
  end if;

  if v_uid_name is null then
    select p.uid into v_existing_uid
    from public.players p where p.name = v_player_name
    order by p.uid limit 1 for update;

    if v_existing_uid is not null then
      update public.players set uid = v_uid::text where uid = v_existing_uid;
    else
      insert into public.players(uid, name) values (v_uid::text, v_player_name);
    end if;
  end if;

  delete from public.access_codes where code = v_code;
  return jsonb_build_object('ok', true, 'player_name', v_player_name);
end;
$function$;

revoke all on function public.redeem_player_access_code(text) from public, anon;
grant execute on function public.redeem_player_access_code(text) to authenticated;

-- Keep public SELECT policies, but separate organizer writes to prevent
-- overlapping permissive SELECT policies on these public-read tables.
do $$
declare t text;
begin
  foreach t in array array['league_data','news','results','schedule','sponsors','tournament'] loop
    execute format('drop policy if exists %I on public.%I', t || '_organizer_write', t);
    execute format('drop policy if exists %I on public.%I', t || '_organizer_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_organizer_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_organizer_delete', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.has_organizer_role(''editor''))', t || '_organizer_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.has_organizer_role(''editor'')) with check (public.has_organizer_role(''editor''))', t || '_organizer_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.has_organizer_role(''editor''))', t || '_organizer_delete', t);
  end loop;
end $$;
