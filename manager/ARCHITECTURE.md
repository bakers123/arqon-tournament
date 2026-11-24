# ARQON Esports Manager — architecture v0.1

## Product
Telegram Mini App game: the Telegram bot is the launcher/notification channel; the Mini App is the full game UI. Multi-discipline manager with PvE and PvP.

## Repository layout
- `/manager/index.html` — responsive Telegram Mini App prototype (vanilla JS, no build step).
- Future: `/manager/assets/` — icons, portraits, team logos.
- Live Supabase Edge Function: `manager-api` — validates Telegram WebApp initData, resolves the linked ARQON user, and runs trusted game commands.
- Future: `/supabase/migrations/*_esports_manager.sql` — normalized game data.

## Core modules
1. Identity: Telegram initData validation on a trusted server; link Telegram user to Supabase auth user. Never trust initDataUnsafe or a client-supplied Telegram ID for authorization.
2. Organization: one owner can manage one or more clubs according to game rules; club name/tag/logo, reputation, level, balance.
3. Disciplines: CS2, Dota 2, VALORANT, League of Legends; discipline metadata defines roster size and role templates.
4. Players: generated/scouted athletes, attributes, potential, form, fatigue, morale, contract, wage, role, discipline.
5. Contracts/transfers: atomic signing, release, buyout, salary debit, transfer history.
6. Training: scheduled actions, cost, fatigue and attribute progression.
7. Match engine: deterministic server-side simulation using player skill, role fit, chemistry, form, fatigue, tactics and controlled randomness. Persist match inputs and result for audit/replay.
8. Competition: PvE seasons, divisions, tournaments and brackets; PvP matchmaking and ranked seasons.
9. Economy: ledger-based currency transactions; never trust client balance or reward values.
10. Notifications: Telegram bot sends match, transfer, contract and tournament events.

## Supabase data model (planned)
- manager_clubs(id, owner_user_id, name, tag, logo_url, balance, reputation, level, created_at)
- manager_club_disciplines(id, club_id, discipline_id, enabled)
- manager_disciplines(id, slug, title, roster_size, roles jsonb)
- manager_players(id, discipline_id, nickname, real_name, age, rating, potential, attributes jsonb, form, fatigue, morale, generated_seed)
- manager_contracts(id, club_id, player_id, role, salary_weekly, signed_at, expires_at, status)
- manager_training_sessions(id, club_id, discipline_id, training_type, cost, created_at, result jsonb)
- manager_matches(id, discipline_id, home_club_id, away_club_id, status, seed, input_snapshot jsonb, result jsonb, played_at)
- manager_tournaments(id, discipline_id, title, season_id, format, status, prize_pool)
- manager_tournament_entries(id, tournament_id, club_id, seed, status)
- manager_wallet_ledger(id, club_id, amount, reason, reference_id, created_at)
- manager_notifications(id, user_id, type, payload jsonb, read_at, created_at)

## Implemented backend
- Telegram WebApp HMAC authentication and linked-account lookup.
- Server-side club creation, player signing, training, match simulation and club rename.
- Per-contract player progression: rating bonus, form, fatigue and morale.
- One active contract per pro player; five-player roster limit per discipline.
- Training cooldown: once per discipline per server day.
- Server-side wallet ledger and rewards.

## Security rules
- All game-changing operations run through trusted Edge Functions or narrowly scoped RPCs.
- Validate Telegram WebApp initData server-side, including auth_date freshness and HMAC signature.
- Derive owner from verified Telegram-to-Supabase link; never accept owner_user_id from browser.
- RLS enabled on every exposed table. Owners may read their clubs/contracts; no client direct writes to balances, match results, contracts, or player progression.
- Use atomic transactions for signing, wages, training and match rewards. Use an append-only wallet ledger.
- PvP match result is computed server-side; do not accept a winner or score from the client.
- Rate-limit club creation, scouting and match simulation.

## Current prototype scope (build 0.2)
- Dashboard, four discipline tabs, player market, sign player, roster view, training action, PvE match simulation, facility upgrades.
- In Telegram, club state, contracts, progression, training, transfers and match outcomes are stored in Supabase. Local browser mode remains only as a non-authoritative preview when opened outside Telegram.
- Before public launch: finish the full requested team/player catalogue imports, add transfer market detail pages, salary cycles, scouting, facilities, season/tournament brackets, PvP matchmaking and notifications.
