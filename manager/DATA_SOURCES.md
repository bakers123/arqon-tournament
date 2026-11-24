# ARQON Esports Manager — live backend and data imports

## Runtime
- Telegram Mini App: `/manager/`
- Telegram launcher: inline Web App button in the existing `@arqon_esports_bot` main menu.
- Supabase Edge Function: `manager-api` (manual Telegram WebApp initData HMAC validation; JWT verification is disabled because the function validates Telegram's signed initData itself).
- Database: `manager_*` tables in the existing ARQON Supabase project.

## Security
- Mini App sends Telegram `WebApp.initData`; it never sends an owner/user id.
- Edge Function validates Telegram's HMAC and auth_date, then resolves the linked account through `telegram_accounts.chat_id`.
- An ARQON account must be linked to Telegram before creating a game club.
- Economy, contracts, training and match results are performed by server-side RPC functions. Client-supplied balances, rewards, scores and winners are ignored.
- The RPCs are revoked from anon/authenticated and granted only to service_role.
- All manager tables have RLS enabled. Pro catalogue data is read-only; private club data is owner-readable.

## Game database
- `manager_disciplines`: discipline roster sizes and role definitions.
- `manager_pro_teams`: real esports organizations, ranking source, rank and dated snapshot.
- `manager_pro_players`: real professional player handles and roster membership snapshots.
- `manager_clubs`, `manager_contracts`, `manager_wallet_ledger`: user organization and economy.
- `manager_training_sessions`, `manager_matches`: training and server-simulated matches.
- `manager_rank_snapshots`: requested ranking size, imported coverage, source and freshness status.

## Current imported coverage (2026-11-24)
- CS2: 8/100 teams; 40 player records. Current HLTV top 8 snapshot (23 Nov 2026).
- Dota 2: 10/50 teams; 20 player records. OpenDota Elo/ScoreCyber top 10 (23 Nov 2026); four rosters sourced separately.
- VALORANT: 8/50 teams; 40 player records. Eight 2026 Champions teams and their event rosters.
- League of Legends: 30/30 teams; 50 player records. Official LoL Esports GPR top-30 team catalogue; ten Worlds 2026 team rosters captured as historical snapshots.

**Important:** ranking imports are intentionally marked partial where the full requested list has not yet been verified. The player OVR/POT fields are ARQON game-balance attributes, not official HLTV/VLR/Riot player ratings. LoL Worlds 2026 rosters are historical snapshots; offseason transfers after Worlds need a separate update. Do not silently present stale roster data as current.

## Data sources
- CS2 HLTV ranking + roster snapshot: https://pley.gg/cs2/world-rankings-cs2/
- Dota 2 ranking: https://scorecyber.ru/dota2/rating/
- Dota 2 roster snapshots: https://statsdota.com/en/teams
- VALORANT event roster snapshots: https://www.vlr.gg/event/2766/valorant-champions-2026
- VALORANT ranking directory: https://www.vlr.gg/rankings
- League of Legends official Global Power Rankings: https://lolesports.com/en-GB/gpr/2026/current
- LoL Worlds 2026 roster cross-check: https://www.riftvanta.com/en/teams

## Next data-import milestone
Complete CS2 100, Dota 2 50 and VALORANT 50 from a single dated ranking source per discipline, then import and verify every team's current starting roster. Keep historical snapshots instead of overwriting transfer history. After that, add scheduled refreshes and player/team detail pages.
