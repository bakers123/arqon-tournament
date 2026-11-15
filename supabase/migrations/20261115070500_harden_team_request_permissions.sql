-- Restrict player updates to request status fields; immutable identity and team fields cannot be changed.
revoke update on public.team_membership_requests from authenticated;
grant update (status, reviewed_at, reviewed_by) on public.team_membership_requests to authenticated;

drop policy if exists team_requests_insert_self on public.team_membership_requests;
create policy team_requests_insert_self on public.team_membership_requests
for insert to authenticated
with check (
  user_id=(select auth.uid())
  and arqon_id=(select p.arqon_id from public.profiles p where p.user_id=(select auth.uid()))
  and player_name=coalesce(
    (select nullif(p.display_name,'') from public.profiles p where p.user_id=(select auth.uid())),
    'Игрок ARQON #'||(select p.arqon_id::text from public.profiles p where p.user_id=(select auth.uid()))
  )
  and status='pending'
  and reviewed_at is null
  and reviewed_by is null
);
