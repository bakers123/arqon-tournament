-- Players can edit their own in-game nickname from their ARQON profile.
-- The profile editor updates this field together with the other owner-managed fields.
grant update (game_nick) on table public.profiles to authenticated;
