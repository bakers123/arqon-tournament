create or replace function public.create_arqon_bet_event(p_title text,p_description text,p_starts_at timestamptz,p_live_match_id uuid default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if auth.uid() is null or not exists(select 1 from private.organizer_roles r where r.user_id=auth.uid() and r.role in ('owner','admin')) then
  raise exception 'not_authorized_admin' using errcode='42501';
 end if;
 if p_starts_at is null or p_starts_at<=now() then raise exception 'event_start_must_be_future'; end if;
 if p_live_match_id is not null and not exists(
  select 1 from public.live_matches m where m.id=p_live_match_id and m.status='scheduled' and m.starts_at>now()
 ) then raise exception 'linked_live_match_must_be_scheduled';
 end if;
 insert into public.arqon_bet_events(title,description,starts_at,live_match_id,created_by)
 values(left(btrim(p_title),140),coalesce(left(p_description,1000),''),p_starts_at,p_live_match_id,auth.uid())
 returning id into v_id;
 return v_id;
end $$;