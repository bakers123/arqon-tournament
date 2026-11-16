create table if not exists private.auth_ip_rate_limits (
  ip_hash text primary key,
  window_started_at timestamptz not null default now(),
  attempts integer not null default 0,
  constraint auth_ip_rate_limits_attempts_nonnegative check (attempts >= 0)
);
alter table private.auth_ip_rate_limits enable row level security;
revoke all on private.auth_ip_rate_limits from public, anon, authenticated;

create or replace function public.consume_auth_ip_attempt(p_ip_hash text)
returns table(allowed boolean, retry_after_seconds integer, attempts integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempts integer;
  v_started timestamptz;
  v_now timestamptz := now();
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service_role required' using errcode = '42501';
  end if;
  if p_ip_hash is null or length(p_ip_hash) <> 64 or p_ip_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid IP hash' using errcode = '22023';
  end if;

  insert into private.auth_ip_rate_limits as limits (ip_hash, window_started_at, attempts)
  values (p_ip_hash, v_now, 1)
  on conflict (ip_hash) do update
    set window_started_at = case
          when limits.window_started_at <= v_now - interval '15 minutes' then v_now
          else limits.window_started_at
        end,
        attempts = case
          when limits.window_started_at <= v_now - interval '15 minutes' then 1
          else limits.attempts + 1
        end
  returning limits.attempts, limits.window_started_at
       into v_attempts, v_started;

  return query
  select v_attempts <= 3,
         greatest(1, ceil(extract(epoch from (v_started + interval '15 minutes' - v_now)))::integer),
         v_attempts;
end;
$$;
revoke all on function public.consume_auth_ip_attempt(text) from public, anon, authenticated;
grant execute on function public.consume_auth_ip_attempt(text) to service_role;