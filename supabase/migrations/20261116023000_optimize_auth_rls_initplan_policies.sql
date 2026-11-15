-- Preserve the same ownership rules while allowing Postgres to evaluate auth.uid()
-- once per statement instead of once per row.
drop policy if exists "Users can view own notification preferences" on public.user_notification_preferences;
create policy "Users can view own notification preferences"
on public.user_notification_preferences for select to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert own notification preferences" on public.user_notification_preferences;
create policy "Users can insert own notification preferences"
on public.user_notification_preferences for insert to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update own notification preferences" on public.user_notification_preferences;
create policy "Users can update own notification preferences"
on public.user_notification_preferences for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Authenticated users can send live match chat" on public.live_match_chat;
create policy "Authenticated users can send live match chat"
on public.live_match_chat for insert to authenticated
with check ((select auth.uid()) = user_id);
