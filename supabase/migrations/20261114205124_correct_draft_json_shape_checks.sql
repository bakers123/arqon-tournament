-- Replace unsafe JSON key subtraction checks with explicit object-shape comparison.
create or replace function public.update_player_draft(p_data jsonb)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_old jsonb;
  v_uid text := (select auth.uid())::text;
  v_role text;
  v_other text;
  v_old_arr jsonb;
  v_new_arr jsonb;
  v_other_old jsonb;
  v_other_new jsonb;
  v_added text;
  v_expected_phase text;
  v_total_bans integer;
  v_pool_size integer;
  v_max_bans integer;
begin
  if v_uid is null or jsonb_typeof(p_data) <> 'object' then
    raise exception 'invalid draft payload' using errcode = '22023';
  end if;
  select d.data into v_old from public.drafts d where d.id = 1 for update;
  if v_old is null then raise exception 'draft not found' using errcode = 'P0002'; end if;
  if v_uid = coalesce(v_old->>'p1_captain_uid', v_old->>'p1_uid') then
    v_role := 'p1'; v_other := 'p2';
  elsif v_uid = coalesce(v_old->>'p2_captain_uid', v_old->>'p2_uid') then
    v_role := 'p2'; v_other := 'p1';
  else raise exception 'not an assigned draft captain' using errcode = '42501';
  end if;
  if (p_data - array['first_turn','turn','phase','bans','picks'])
       is distinct from
     (v_old - array['first_turn','turn','phase','bans','picks']) then
    raise exception 'draft metadata is immutable for players' using errcode = '42501';
  end if;
  if jsonb_typeof(v_old->'pool') is distinct from 'array'
     or jsonb_typeof(v_old->'bans') is distinct from 'object'
     or jsonb_build_object('p1',v_old->'bans'->'p1','p2',v_old->'bans'->'p2') is distinct from v_old->'bans'
     or jsonb_typeof(v_old->'bans'->'p1') is distinct from 'array'
     or jsonb_typeof(v_old->'bans'->'p2') is distinct from 'array'
     or jsonb_typeof(v_old->'picks') is distinct from 'object'
     or jsonb_build_object('p1',v_old->'picks'->'p1','p2',v_old->'picks'->'p2') is distinct from v_old->'picks'
     or (jsonb_typeof(v_old->'picks'->'p1') is distinct from 'null'
         and jsonb_typeof(v_old->'picks'->'p1') is distinct from 'string')
     or (jsonb_typeof(v_old->'picks'->'p2') is distinct from 'null'
         and jsonb_typeof(v_old->'picks'->'p2') is distinct from 'string')
     or jsonb_typeof(p_data->'bans') is distinct from 'object'
     or jsonb_build_object('p1',p_data->'bans'->'p1','p2',p_data->'bans'->'p2') is distinct from p_data->'bans'
     or jsonb_typeof(p_data->'bans'->'p1') is distinct from 'array'
     or jsonb_typeof(p_data->'bans'->'p2') is distinct from 'array'
     or jsonb_typeof(p_data->'picks') is distinct from 'object'
     or jsonb_build_object('p1',p_data->'picks'->'p1','p2',p_data->'picks'->'p2') is distinct from p_data->'picks'
     or (jsonb_typeof(p_data->'picks'->'p1') is distinct from 'null'
         and jsonb_typeof(p_data->'picks'->'p1') is distinct from 'string')
     or (jsonb_typeof(p_data->'picks'->'p2') is distinct from 'null'
         and jsonb_typeof(p_data->'picks'->'p2') is distinct from 'string') then
    raise exception 'draft state structure is invalid' using errcode = '22023';
  end if;
  v_pool_size := jsonb_array_length(v_old->'pool');
  v_max_bans := coalesce((v_old->>'maxBans')::integer, 5);
  if v_old->>'phase' = 'coinflip' then
    if p_data->>'first_turn' is null or p_data->>'first_turn' not in ('p1','p2')
       or p_data->>'phase' is distinct from 'ban'
       or p_data->>'turn' is distinct from p_data->>'first_turn'
       or p_data->'bans' is distinct from v_old->'bans'
       or p_data->'picks' is distinct from v_old->'picks' then
      raise exception 'invalid coin toss transition' using errcode = '42501';
    end if;
  elsif v_old->>'phase' = 'ban' then
    if p_data->>'first_turn' is distinct from v_old->>'first_turn'
       or p_data->'picks' is distinct from v_old->'picks' then
      raise exception 'invalid ban transition' using errcode = '42501';
    end if;
    v_old_arr := v_old->'bans'->v_role;
    v_new_arr := p_data->'bans'->v_role;
    v_other_old := v_old->'bans'->v_other;
    v_other_new := p_data->'bans'->v_other;
    if v_other_new is distinct from v_other_old
       or exists (select 1 from jsonb_array_elements(v_new_arr) e(value)
                  where jsonb_typeof(e.value) is distinct from 'string')
       or exists (select 1 from jsonb_array_elements(v_new_arr) e(value)
                  group by e.value having count(*) > 1) then
      raise exception 'invalid ban payload' using errcode = '22023';
    end if;
    if v_old->>'game' = 'cs2' then
      if v_old->>'turn' is distinct from v_role
         or jsonb_array_length(v_new_arr) <> jsonb_array_length(v_old_arr) + 1
         or not (v_new_arr @> v_old_arr) then
        raise exception 'one new map ban is required on your turn' using errcode = '42501';
      end if;
      select e.value into v_added from jsonb_array_elements_text(v_new_arr) e(value)
      where not (v_old_arr ? e.value) limit 1;
      if v_added is null or not (v_old->'pool' ? v_added) then
        raise exception 'map is not in the draft pool' using errcode = '22023';
      end if;
      v_total_bans := jsonb_array_length(v_new_arr) + jsonb_array_length(v_other_new);
      v_expected_phase := case when v_pool_size - v_total_bans <= 1 then 'pick' else 'ban' end;
      if p_data->>'phase' is distinct from v_expected_phase
         or p_data->>'turn' is distinct from v_other then
        raise exception 'invalid CS2 turn transition' using errcode = '42501';
      end if;
    elsif v_old->>'game' = 'dota' then
      if v_old->>'turn' is distinct from v_role then
        raise exception 'not your ban turn' using errcode = '42501';
      end if;
      if jsonb_array_length(v_new_arr) = jsonb_array_length(v_old_arr) + 1
         and jsonb_array_length(v_old_arr) < v_max_bans
         and v_new_arr @> v_old_arr then
        select e.value into v_added from jsonb_array_elements_text(v_new_arr) e(value)
        where not (v_old_arr ? e.value) limit 1;
        if v_added is null or not (v_old->'pool' ? v_added)
           or p_data->>'turn' is distinct from v_old->>'turn'
           or p_data->>'phase' is distinct from 'ban' then
          raise exception 'invalid Dota ban' using errcode = '42501';
        end if;
      elsif v_new_arr is not distinct from v_old_arr
         and jsonb_array_length(v_old_arr) >= v_max_bans
         and p_data->>'turn' = v_other then
        v_expected_phase := case
          when jsonb_array_length(v_old->'bans'->v_other) >= v_max_bans then 'pick'
          else 'ban' end;
        if p_data->>'phase' is distinct from v_expected_phase then
          raise exception 'invalid Dota phase transition' using errcode = '42501';
        end if;
      else raise exception 'invalid Dota ban transition' using errcode = '42501';
      end if;
    else raise exception 'unsupported draft game' using errcode = '22023';
    end if;
  elsif v_old->>'phase' = 'pick' and v_old->>'game' = 'dota' then
    if p_data->>'phase' is distinct from 'pick'
       or p_data->>'turn' is distinct from v_old->>'turn'
       or p_data->>'first_turn' is distinct from v_old->>'first_turn'
       or p_data->'bans' is distinct from v_old->'bans'
       or p_data->'picks'->v_other is distinct from v_old->'picks'->v_other
       or v_old->'picks'->v_role is distinct from 'null'::jsonb
       or jsonb_typeof(p_data->'picks'->v_role) is distinct from 'string' then
      raise exception 'invalid pick transition' using errcode = '42501';
    end if;
    v_added := p_data->'picks'->>v_role;
    if v_added is null or not (v_old->'pool' ? v_added)
       or (v_old->'bans'->'p1' ? v_added)
       or (v_old->'bans'->'p2' ? v_added)
       or (v_old->'picks'->v_other) = to_jsonb(v_added) then
      raise exception 'hero is unavailable' using errcode = '22023';
    end if;
  else raise exception 'draft phase does not allow player changes' using errcode = '42501';
  end if;
  update public.drafts set data = p_data where id = 1;
end;
$function$;
revoke all on function public.update_player_draft(jsonb) from public, anon;
grant execute on function public.update_player_draft(jsonb) to authenticated;
