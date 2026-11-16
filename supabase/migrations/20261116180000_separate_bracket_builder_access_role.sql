-- Separate bracket-builder access from general ARQON organizer privileges.
alter table private.organizer_roles drop constraint if exists organizer_roles_role_check;
alter table private.organizer_roles add constraint organizer_roles_role_check
  check (role in ('owner','admin','editor','judge','bracket_editor'));

create or replace function public.has_bracket_service_access()
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(public.current_organizer_role() in ('owner','admin','editor','bracket_editor'), false);
$$;
revoke all on function public.has_bracket_service_access() from public, anon;
grant execute on function public.has_bracket_service_access() to authenticated;

CREATE OR REPLACE FUNCTION public.list_organizer_bracket_documents()
 RETURNS TABLE(id uuid, title text, format text, status text, data jsonb, published_data jsonb, published_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not public.has_bracket_service_access() then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  return query
  select d.id, d.title, d.format, d.status, d.data, d.published_data,
         d.published_at, d.updated_at
  from public.bracket_documents d
  order by d.updated_at desc;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_bracket_document(p_id uuid, p_title text, p_format text, p_data jsonb, p_publish boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_old_data jsonb;
  v_positions jsonb;
  v_edges_changed boolean := false;
  v_old_edges jsonb := '[]'::jsonb;
begin
  if not public.has_bracket_service_access() then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if p_title is null or length(btrim(p_title)) not between 1 and 120 then
    raise exception 'invalid bracket title' using errcode = '22023';
  end if;
  if p_format is null or p_format not in ('single','double','round_robin','custom') then
    raise exception 'invalid bracket format' using errcode = '22023';
  end if;
  if p_data is null or jsonb_typeof(p_data) is distinct from 'object'
     or jsonb_typeof(p_data->'nodes') is distinct from 'array'
     or jsonb_typeof(p_data->'edges') is distinct from 'array'
     or jsonb_typeof(p_data->'sections') is distinct from 'array' then
    raise exception 'invalid bracket document structure' using errcode = '22023';
  end if;
  select data, coalesce(data->'edges','[]'::jsonb)
    into v_old_data, v_old_edges
  from public.bracket_documents where id = v_id for update;
  v_edges_changed := v_old_edges is distinct from p_data->'edges';
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', new_node.value->>'id','title', new_node.value->>'title',
      'from', jsonb_build_object('x', old_node.value->'x', 'y', old_node.value->'y'),
      'to', jsonb_build_object('x', new_node.value->'x', 'y', new_node.value->'y')
    )), '[]'::jsonb)
  into v_positions
  from jsonb_array_elements(p_data->'nodes') as new_node(value)
  left join jsonb_array_elements(coalesce(v_old_data->'nodes','[]'::jsonb)) as old_node(value)
    on old_node.value->>'id' = new_node.value->>'id'
  where old_node.value is null
     or old_node.value->'x' is distinct from new_node.value->'x'
     or old_node.value->'y' is distinct from new_node.value->'y';
  insert into public.bracket_documents
    (id, title, format, status, data, published_data, created_by, updated_by, published_at)
  values
    (v_id, btrim(p_title), p_format,
     case when p_publish then 'published' else 'draft' end,
     p_data, case when p_publish then p_data else null end,
     (select auth.uid()), (select auth.uid()),
     case when p_publish then now() else null end)
  on conflict (id) do update set
    title = excluded.title, format = excluded.format, data = excluded.data,
    status = case when p_publish then 'published' else bracket_documents.status end,
    published_data = case when p_publish then excluded.data else bracket_documents.published_data end,
    published_at = case when p_publish then now() else bracket_documents.published_at end,
    updated_by = (select auth.uid()), updated_at = now();
  insert into public.bracket_audit(bracket_id, actor_id, action, details)
  values (v_id, (select auth.uid()),
    case when p_publish then 'published' else 'saved_draft' end,
    jsonb_build_object(
      'title', btrim(p_title), 'format', p_format,
      'matchCount', jsonb_array_length(p_data->'nodes'),
      'connectionCount', jsonb_array_length(p_data->'edges'),
      'changedPositions', v_positions, 'edgesChanged', v_edges_changed,
      'previousEdges', v_old_edges, 'newEdges', p_data->'edges'
    ));
  return v_id;
end;
$function$;

drop policy if exists bracket_assignments_authenticated_read on public.bracket_assignments;
create policy bracket_assignments_authenticated_read on public.bracket_assignments for select to authenticated
using (public.has_bracket_service_access() or judge_user_id = (select auth.uid()));

drop policy if exists bracket_audit_authenticated_read on public.bracket_audit;
create policy bracket_audit_authenticated_read on public.bracket_audit for select to authenticated
using (public.has_bracket_service_access() or actor_id = (select auth.uid()));

drop policy if exists bracket_documents_authenticated_read on public.bracket_documents;
create policy bracket_documents_authenticated_read on public.bracket_documents for select to authenticated
using (public.has_bracket_service_access() or (status = 'published' and published_data is not null));

drop policy if exists bracket_judges_editor_read on public.bracket_judges;
create policy bracket_judges_editor_read on public.bracket_judges for select to authenticated
using (public.has_bracket_service_access());

create or replace function public.set_service_access(p_user_id uuid, p_allowed boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare existing_role text;
begin
  if coalesce(public.current_organizer_role(), '') <> 'owner' then
    raise exception 'owner role required' using errcode = '42501';
  end if;
  if p_user_id is null or p_allowed is null then
    raise exception 'user and access decision are required' using errcode = '22023';
  end if;
  if p_user_id = (select auth.uid()) then
    raise exception 'the owner cannot change their own access here' using errcode = '42501';
  end if;
  select r.role into existing_role from private.organizer_roles r where r.user_id = p_user_id;
  if existing_role in ('owner','admin','editor','judge') then
    raise exception 'this account has a separate organizer or judge role' using errcode = '22023';
  end if;
  if p_allowed then
    insert into private.organizer_roles(user_id, role) values (p_user_id, 'bracket_editor')
    on conflict (user_id) do nothing;
  else
    delete from private.organizer_roles where user_id = p_user_id and role = 'bracket_editor';
  end if;
end;
$$;
revoke all on function public.set_service_access(uuid, boolean) from public, anon;
grant execute on function public.set_service_access(uuid, boolean) to authenticated;
comment on function public.has_bracket_service_access() is
  'Allows owner/admin/editor and explicitly approved bracket_editor accounts to use bracket builder without granting general admin privileges.';
