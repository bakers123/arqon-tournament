# ARQON Broadcast Bridge (CS2 GSI)

This local bridge receives Counter-Strike 2 Game State Integration (GSI) updates and forwards spectator data to the ARQON HUD over WebSocket.

## Requirements
- Windows PC running CS2 in spectator/GOTV observer mode
- OBS Studio on the same PC
- Node.js 18 or newer

## Install
1. Copy `gamestate_integration_arqon.cfg` into:
   `...Steam\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg\`
2. Open a terminal in this folder and run:
   `npm install`
3. Start the bridge:
   `npm start`
4. Keep the terminal open while streaming.
5. In OBS add a **Browser Source** with URL:
   `http://127.0.0.1:3001/broadcast/?match=YOUR_MATCH_ID&ct=1&mode=full`
   Set width 1920 and height 1080. The page background is transparent.

## How to select sides
- `ct=1`: ARQON match Team 1 is on CT; Team 2 is on T.
- `ct=2`: ARQON match Team 2 is on CT; Team 1 is on T.
- `mode=full`: player panels with HP, armor, weapon, ammo and K/D.
- `mode=compact`: scoreboard only.

The Live Center creates this URL for the selected match. Set the CT side and upload team logos there, then copy the URL into OBS.

## What GSI can provide
In spectator mode, CS2 sends the 10-player `allplayers` state: health, armor, helmet, money, active weapon/ammo, kills, deaths and assists. The bridge also forwards map, round, CT/T score, round phase and bomb state.

**Important:** GSI only reports data available to the current game client. To show all ten players, run CS2 as the match observer / GOTV spectator. A normal player's client generally exposes only the local player rather than all ten players.

## Security
- The bridge binds only to `127.0.0.1`; it is not exposed to the internet.
- The GSI endpoint checks the token in the CS2 payload.
- Do not port-forward port 3001.
- To change the token, change it in both `server.js` (or set `ARQON_GSI_TOKEN`) and the cfg file.
