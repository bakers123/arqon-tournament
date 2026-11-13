create or replace function public.save_bracket_document(
  p_id uuid,p_title text,p_format text,p_data jsonb,p_publish boolean default false
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid := coalesce(p_id,gen_random_uuid());
  v_old_data jsonb;
  v_positions jsonb;
  v_edges_changed boolean := false;
  v_old_edges jsonb := '[]'::jsonb;
begin
  if not public.has_organizer_role('editor') then raise exception 'not authorized' using errcode='42501'; end if;
  if p_title is null or length(btrim(p_title)) not between 1 and 120 then raise exception 'invalid bracket title' using errcode='22023'; end if;
  if p_format is null or p_format not in ('single','double','round_robin','custom') then raise exception 'invalid bracket format' using errcode='22023'; end if;
  if p_data is null or jsonb_typeof(p_data) is distinct from 'object'
    or jsonb_typeof(p_data->'nodes') is distinct from 'array'
    or jsonb_typeof(p_data->'edges') is distinct from 'array'
    or jsonb_typeof(p_data->'sections') is distinct from 'array' then
    raise exception 'invalid bracket document structure' using errcode='22023';
  end if;
  select data,coalesce(data->'edges','[]'::jsonb) into v_old_data,v_old_edges
  from public.bracket_documents where id=v_id for update;
  v_edges_changed:=v_old_edges is distinct from p_data->'edges';
  select coalesce(jsonb_agg(jsonb_build_object('id',new_node.value->>'id','title',new_node.value->>'title',
    'from',jsonb_build_object('x',old_node.value->'x','y',old_node.value->'y'),
    'to',jsonb_build_object('x',new_node.value->'x','y',new_node.value->'y'))),'[]'::jsonb)
  into v_positions from jsonb_array_elements(p_data->'nodes') as new_node(value)
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
revoke all on function public.save_bracket_document(uuid,text,text,jsonb,boolean) from public,anon;
grant execute on function public.save_bracket_document(uuid,text,text,jsonb,boolean) to authenticated;
