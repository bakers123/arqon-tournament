create table if not exists public.telegram_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 chat_id text not null unique, telegram_username text, first_name text,
 linked_at timestamptz not null default now()
);
create table if not exists public.telegram_link_tokens (
 token text primary key, user_id uuid not null references auth.users(id) on delete cascade,
 expires_at timestamptz not null, created_at timestamptz not null default now()
);
alter table public.telegram_accounts enable row level security;
alter table public.telegram_link_tokens enable row level security;
revoke all on public.telegram_accounts,public.telegram_link_tokens from anon,authenticated;
grant select,insert,update,delete on public.telegram_accounts,public.telegram_link_tokens to service_role;
create or replace function public.create_telegram_link_token()
returns table(link_token text,expires_at timestamptz)
language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=auth.uid(); v_token text;
begin
 if v_user is null then raise exception 'not_authenticated'; end if;
 delete from public.telegram_link_tokens where user_id=v_user or expires_at<now();
 v_token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into public.telegram_link_tokens(token,user_id,expires_at) values(v_token,v_user,now()+interval '10 minutes');
 return query select v_token,now()+interval '10 minutes';
end $function$;
create or replace function public.get_telegram_link_status()
returns table(is_linked boolean,telegram_username text,linked_at timestamptz)
language sql stable security definer set search_path=''
as $function$
 select (ta.user_id is not null),ta.telegram_username,ta.linked_at
 from (select auth.uid() as uid) u left join public.telegram_accounts ta on ta.user_id=u.uid
 where u.uid is not null
$function$;
create or replace function public.unlink_telegram_account()
returns boolean language plpgsql security definer set search_path=''
as $function$
begin
 if auth.uid() is null then raise exception 'not_authenticated'; end if;
 delete from public.telegram_accounts where user_id=auth.uid();
 delete from public.telegram_link_tokens where user_id=auth.uid();
 return true;
end $function$;
revoke all on function public.create_telegram_link_token() from public,anon;
revoke all on function public.get_telegram_link_status() from public,anon;
revoke all on function public.unlink_telegram_account() from public,anon;
grant execute on function public.create_telegram_link_token() to authenticated;
grant execute on function public.get_telegram_link_status() to authenticated;
grant execute on function public.unlink_telegram_account() to authenticated;
