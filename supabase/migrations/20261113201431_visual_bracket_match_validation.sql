create or replace function public.update_assigned_bracket_match(
  p_bracket_id uuid,p_match_id text,p_maps jsonb,p_status text,p_result_type text default 'normal',p_winner_side integer default null
)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_doc public.bracket_documents%rowtype;
  v_node jsonb;
  v_ordinal bigint;
  v_role text := public.current_organizer_role();
  v_map_count integer;
  v_required_maps integer;
begin
  if v_role not in ('owner','admin','editor','judge') then raise exception 'not authorized' using errcode='42501'; end if;
  if p_bracket_id is null or p_match_id is null or length(btrim(p_match_id))=0 then raise exception 'bracket and match identifiers are required' using errcode='22023'; end if;
  if v_role='judge' and not exists(select 1 from public.bracket_assignments a where a.bracket_id=p_bracket_id
    and a.judge_user_id=(select auth.uid()) and (a.match_id is null or a.match_id=p_match_id)) then
    raise exception 'match is not assigned to this judge' using errcode='42501';
  end if;
  if p_maps is null or jsonb_typeof(p_maps)<>'array' or jsonb_array_length(p_maps)>5 then raise exception 'invalid map results' using errcode='22023'; end if;
  if p_status is null or p_status not in ('pending','live','completed','technical','cancelled') then raise exception 'invalid match status' using errcode='22023'; end if;
  if p_result_type is null or p_result_type not in ('normal','technical_win','technical_loss','disqualified','cancelled') then raise exception 'invalid result type' using errcode='22023'; end if;
  if p_winner_side not in (1,2) and p_winner_side is not null then raise exception 'invalid winner side' using errcode='22023'; end if;
  if p_result_type in ('technical_win','technical_loss','disqualified') and p_winner_side is null then raise exception 'technical result requires an explicit winner' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(p_maps) m(value) where jsonb_typeof(m.value)<>'object'
    or coalesce(m.value->>'map','')='' or coalesce(m.value->>'status','') not in ('not_started','live','completed')
    or (m.value?'score1' and coalesce(m.value->>'score1','')<>'' and (m.value->>'score1') !~ '^[0-9]{1,2}$')
    or (m.value?'score2' and coalesce(m.value->>'score2','')<>'' and (m.value->>'score2') !~ '^[0-9]{1,2}$')) then
    raise exception 'invalid map result fields' using errcode='22023';
  end if;
  select * into v_doc from public.bracket_documents where id=p_bracket_id and status='published' for update;
  if not found or v_doc.published_data is null then raise exception 'published bracket not found' using errcode='P0002'; end if;
  select e.value,e.ordinality into v_node,v_ordinal from jsonb_array_elements(v_doc.published_data->'nodes') with ordinality e(value,ordinality)
    where e.value->>'id'=p_match_id limit 1;
  if v_node is null then raise exception 'match not found' using errcode='P0002'; end if;
  v_required_maps:=case v_node->>'format' when 'BO1' then 1 when 'BO3' then 3 when 'BO5' then 5 else 0 end;
  v_map_count:=jsonb_array_length(p_maps);
  if v_required_maps=0 or v_map_count<>v_required_maps then raise exception 'map count does not match the match format' using errcode='22023'; end if;
  v_node:=v_node||jsonb_build_object('maps',p_maps,'status',p_status,'resultType',p_result_type,'winnerSide',p_winner_side);
  update public.bracket_documents set published_data=jsonb_set(published_data,array['nodes',(v_ordinal-1)::text],v_node,false),
    updated_by=(select auth.uid()),updated_at=now() where id=p_bracket_id;
  insert into public.bracket_audit(bracket_id,match_id,actor_id,action,details)
  values(p_bracket_id,p_match_id,(select auth.uid()),'match_result_updated',
    jsonb_build_object('status',p_status,'resultType',p_result_type,'winnerSide',p_winner_side,'maps',p_maps));
end;
$$;
revoke all on function public.update_assigned_bracket_match(uuid,text,jsonb,text,text,integer) from public,anon;
grant execute on function public.update_assigned_bracket_match(uuid,text,jsonb,text,text,integer) to authenticated;
