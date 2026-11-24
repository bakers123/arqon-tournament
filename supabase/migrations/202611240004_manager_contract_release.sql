-- Server-side player contract release. Only manager-api service_role may execute.
create or replace function public.manager_release_player(p_user_id uuid, p_contract_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_club public.manager_clubs;
  v_contract public.manager_contracts;
  v_player_name text;
begin
  if p_user_id is null or p_contract_id is null then raise exception 'invalid_request'; end if;
  select * into v_club from public.manager_clubs where owner_user_id=p_user_id for update;
  if not found then raise exception 'club_not_found'; end if;
  select * into v_contract from public.manager_contracts
    where id=p_contract_id and club_id=v_club.id and status='active' for update;
  if not found then raise exception 'active_contract_not_found'; end if;
  select nickname into v_player_name from public.manager_pro_players where id=v_contract.pro_player_id;
  update public.manager_contracts set status='released', expires_at=now()
    where id=v_contract.id;
  return jsonb_build_object('ok',true,'player',v_player_name,'contract_id',v_contract.id);
end;
$$;
revoke execute on function public.manager_release_player(uuid,uuid) from public, anon, authenticated;
grant execute on function public.manager_release_player(uuid,uuid) to service_role;
