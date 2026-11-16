drop policy if exists team_requests_read_self_or_admin on public.team_membership_requests;
create policy team_requests_read_self_or_admin
on public.team_membership_requests
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.current_organizer_role() = any (array['admin','owner'])
  or exists (
    select 1
    from public.team_profiles tp
    join public.profiles captain on captain.arqon_id = tp.captain_arqon_id
    where tp.team_id = team_membership_requests.team_id
      and captain.user_id = (select auth.uid())
  )
);

drop policy if exists team_requests_update_self_or_admin on public.team_membership_requests;
create policy team_requests_update_self_or_admin
on public.team_membership_requests
for update to authenticated
using (
  (user_id = (select auth.uid()) and status = 'pending')
  or public.current_organizer_role() = any (array['admin','owner'])
  or exists (
    select 1
    from public.team_profiles tp
    join public.profiles captain on captain.arqon_id = tp.captain_arqon_id
    where tp.team_id = team_membership_requests.team_id
      and captain.user_id = (select auth.uid())
  )
)
with check (
  (user_id = (select auth.uid()) and status = 'withdrawn' and reviewed_at is null and reviewed_by is null)
  or (
    public.current_organizer_role() = any (array['admin','owner'])
    and status = any (array['accepted','rejected','pending'])
  )
  or (
    status = any (array['accepted','rejected'])
    and reviewed_by = (select auth.uid())
    and reviewed_at is not null
    and exists (
      select 1
      from public.team_profiles tp
      join public.profiles captain on captain.arqon_id = tp.captain_arqon_id
      where tp.team_id = team_membership_requests.team_id
        and captain.user_id = (select auth.uid())
    )
  )
);