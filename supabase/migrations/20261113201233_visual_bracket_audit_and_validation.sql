create or replace function public.save_bracket_document(
  p_id uuid, p_title text, p_format text, p_data jsonb, p_publish boolean default false
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_old_data jsonb;
  v_positions jsonb;
  v_edges_changed boolean := false;
  v_old_edges jsonb := '[]'::jsonb;
begin
  if not public.has_organizer_role('editor') then raise exception 'not authorized' using errcode = '42501'; end if;
  if p_title is null or length(btrim(p_title)) not between 1 and 120 then raise exception 'invalid bracket title' using errcode = '22023'; end if;
  if p_format not in ('single','double','round_robin','custom') then raise exception 'invalid bracket format' using errcode = '22023'; end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' or jsonb_typeof(p_data->'nodes') <> 'array'
     or jsonb_typeof(p_data->'edges') <> 'array' or jsonb_typeof(p_data->'sections') <> 'array' then
    raise exception 'invalid bracket document structure' using errcode = '22023';
  end if;
  select data, coalesce(data->'edges','[]'::jsonb) into v_old_data, v_old_edges
  from public.bracket_documents where id = v_id for update;
  v_edges_changed := v_old_data is not null and v_old_edges is distinct from p_data->'edges';
  select coalesce(jsonb_agg(jsonb_build_object('id',new_node.value->>'id','title',new_node.value->>'title',
    'from',jsonb_build_object('x',old_node.value->'x','y',old_node.value->'y'),
    'to',jsonb_build_object('x',new_node.value->'x','y',new_node.value->'y'))),'[]'::jsonb)
  into v_positions
  from jsonb_array_elements(p_data->'nodes') as new_node(value)
  left join jsonb_array_elements(coalesce(v_old_data->'nodes','[]'::jsonb)) as old_node(value)
    on old_node.value->>'id'=new_node.value->>'id'
  where old_node.value is null or old_node.value->'x' is distinct from new_node.value->'x'
     or old_node.value->'y' is distinct from new_node.value->'y';
  insert into public.bracket_documents(id,title,format,status,data,published_data,created_by,updated_by,published_at)
  values(v_id,btrim(p_title),p_format,case when p_publish then 'published' else 'draft' end,p_data,
    case when p_publish then p_data else null end,(select auth.uid()),(select auth.uid()),case when p_publish then now() else null end)
  on conflict(id) do update set title=excluded.title,format=excluded.format,data=excluded.data,
    status=case when p_publish then 'published' else bracket_documents.status end,
    published_data=case when p_publish then excluded.data else bracket_documents.published_data end,
    published_at=case when p_publish then now() else bracket_documents.published_at end,
    updated_by=(select auth.uid()),updated_at=now();
  insert into public.bracket_audit(bracket_id,actor_id,action,details)
  values(v_id,(select auth.uid()),case when p_publish then 'published' else 'saved_draft' end,
    jsonb_build_object('title',btrim(p_title),'format',p_format,'matchCount',jsonb_array_length(p_data->'nodes'),
      'connectionCount',jsonb_array_length(p_data->'edges'),'changedPositions',v_positions,
      'edgesChanged',v_edges_changed,'previousEdges',v_old_edges,'newEdges',p_data->'edges'));
  return v_id;
end;
$$;
create or replace function public.update_assigned_bracket_match(
  p_bracket_id uuid,p_match_id text,p_maps jsonb,p_status text,p_result_type text default 'normal',p_winner_side integer default null
)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_doc public.bracket_documents%rowtype; v_node jsonb; v_ordinal bigint; v_role text := public.current_organizer_role();
begin
  if v_role not in ('owner','admin','editor','judge') then raise exception 'not authorized' using errcode = '42501'; end if;
  if v_role='judge' and not exists(select 1 from public.bracket_assignments a where a.bracket_id=p_bracket_id
    and a.judge_user_id=(select auth.uid()) and (a.match_id is null or a.match_id=p_match_id)) then
    raise exception 'match is not assigned to this judge' using errcode = '42501';
  end if;
  if p_maps is null or jsonb_typeof(p_maps)<>'array' or jsonb_array_length(p_maps)>5 then raise exception 'invalid map results' using errcode='22023'; end if;
  if p_status not in ('pending','live','completed','technical','cancelled') then raise exception 'invalid match status' using errcode='22023'; end if;
  if p_result_type not in ('normal','technical_win','technical_loss','disqualified','cancelled') then raise exception 'invalid result type' using errcode='22023'; end if;
  if p_winner_side not in (1,2) and p_winner_side is not null then raise exception 'invalid winner side' using errcode='22023'; end if;
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
  v_node:=v_node||jsonb_build_object('maps',p_maps,'status',p_status,'resultType',p_result_type,'winnerSide',p_winner_side);
  update public.bracket_documents set published_data=jsonb_set(published_data,array['nodes',(v_ordinal-1)::text],v_node,false),
    updated_by=(select auth.uid()),updated_at=now() where id=p_bracket_id;
  insert into public.bracket_audit(bracket_id,match_id,actor_id,action,details)
  values(p_bracket_id,p_match_id,(select auth.uid()),'match_result_updated',
    jsonb_build_object('status',p_status,'resultType',p_result_type,'winnerSide',p_winner_side,'maps',p_maps));
end;
$$;
revoke all on function public.save_bracket_document(uuid,text,text,jsonb,boolean) from public,anon;
grant execute on function public.save_bracket_document(uuid,text,text,jsonb,boolean) to authenticated;
revoke all on function public.update_assigned_bracket_match(uuid,text,jsonb,text,text,integer) from public,anon;
grant execute on function public.update_assigned_bracket_match(uuid,text,jsonb,text,text,integer) to authenticated;
