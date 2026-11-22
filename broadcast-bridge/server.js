'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { WebSocketServer, WebSocket } = require('ws');

const HOST = '127.0.0.1';
const PORT = Number(process.env.PORT || 3001);
const GSI_TOKEN = process.env.ARQON_GSI_TOKEN || 'arqon-gsi-local-2026-change-this-token';
const OVERLAY_FILE = path.join(__dirname, '..', 'broadcast', 'index.html');
let latestState = null;
const clients = new Set();

function send(client, message) {
  if (client.readyState === WebSocket.OPEN) client.send(JSON.stringify(message));
}
function broadcast(message) {
  const payload = JSON.stringify(message);
  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) client.send(payload);
  }
}
function safeSnapshot(body) {
  const allplayers = body && body.allplayers && typeof body.allplayers === 'object' ? body.allplayers : {};
  const players = Object.entries(allplayers).map(([steamid, player]) => {
    const weapons = player && player.weapons && typeof player.weapons === 'object' ? player.weapons : {};
    const weaponList = Object.values(weapons).filter(Boolean);
    const active = weaponList.find(w => w.state === 'active') || weaponList[0] || null;
    const state = player.state || {};
    const stats = player.match_stats || {};
    const rawPosition = player.position;
    const coords = typeof rawPosition === 'string' ? rawPosition.split(',').map(Number) : [];
    const position = coords.length >= 2 && coords.slice(0, 3).every(Number.isFinite)
      ? { x: coords[0], y: coords[1], z: Number.isFinite(coords[2]) ? coords[2] : 0 }
      : null;
    return {
      steamid,
      position,
      name: String(player.name || 'Unknown').slice(0, 48),
      team: player.team === 'CT' || player.team === 'T' ? player.team : null,
      health: Number.isFinite(Number(state.health)) ? Number(state.health) : 0,
      armor: Number.isFinite(Number(state.armor)) ? Number(state.armor) : 0,
      helmet: Boolean(state.helmet),
      money: Number.isFinite(Number(state.money)) ? Number(state.money) : null,
      alive: Number(state.health) > 0,
      kills: Number(stats.kills || 0),
      deaths: Number(stats.deaths || 0),
      assists: Number(stats.assists || 0),
      weapon: active ? String(active.name || '').replace(/^weapon_/, '').toLowerCase() : '',
      ammo: active && active.ammo_clip != null ? Number(active.ammo_clip) : null,
      reserve: active && active.ammo_reserve != null ? Number(active.ammo_reserve) : null,
      grenades: weaponList.map(w => String(w && w.name || '').replace(/^weapon_/, '').toLowerCase()).filter(name => ['flashbang','hegrenade','smokegrenade','molotov','incgrenade','decoy','firebomb'].includes(name)),
      hasBomb: Boolean(player.state && player.state.burning)
    };
  });
  const map = body.map || {};
  const countdown = body.phase_countdowns || {};
  return {
    receivedAt: Date.now(),
    map: {
      name: map.name || '',
      phase: map.phase || '',
      round: Number(map.round || 0),
      ct: { name: map.team_ct && map.team_ct.name || 'CT', score: Number(map.team_ct && map.team_ct.score || 0) },
      t: { name: map.team_t && map.team_t.name || 'T', score: Number(map.team_t && map.team_t.score || 0) }
    },
    round: {
      phase: body.round && body.round.phase || '',
      bomb: body.round && body.round.bomb || (body.bomb && body.bomb.state) || ''
    },
    timer: countdown.phase_ends_in || countdown.phaseEndsIn || null,
    players
  };
}
const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
    res.end(JSON.stringify({ ok: true, service: 'ARQON Broadcast Bridge', clients: clients.size, hasGameData: Boolean(latestState) }));
    return;
  }
  if (req.method === 'GET' && (req.url === '/broadcast' || req.url.startsWith('/broadcast/'))) {
    fs.readFile(OVERLAY_FILE, (error, html) => {
      if (error) {
        res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' });
        res.end('Не найден broadcast/index.html. Запустите мост из папки broadcast-bridge внутри репозитория.');
        return;
      }
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'access-control-allow-origin': '*' });
      res.end(html);
    });
    return;
  }
  if (req.method === 'POST' && req.url === '/gsi') {
    let raw = '';
    req.setEncoding('utf8');
    req.on('data', chunk => {
      raw += chunk;
      if (raw.length > 1024 * 1024) req.destroy();
    });
    req.on('end', () => {
      let body;
      try { body = JSON.parse(raw || '{}'); } catch {
        res.writeHead(400); res.end('Invalid JSON'); return;
      }
      const supplied = body.auth && body.auth.token;
      if (GSI_TOKEN && supplied !== GSI_TOKEN) {
        res.writeHead(401); res.end('Unauthorized GSI token'); return;
      }
      latestState = safeSnapshot(body);
      broadcast({ type: 'gsi', state: latestState });
      res.writeHead(200, { 'content-type': 'text/plain' });
      res.end('ok');
    });
    return;
  }
  res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
  res.end('Not found');
});
const wss = new WebSocketServer({ server, path: '/ws' });
wss.on('connection', socket => {
  clients.add(socket);
  send(socket, { type: 'bridge', connected: true, hasGameData: Boolean(latestState) });
  if (latestState) send(socket, { type: 'gsi', state: latestState });
  socket.on('close', () => clients.delete(socket));
  socket.on('error', () => clients.delete(socket));
});
server.listen(PORT, HOST, () => {
  console.log('ARQON Broadcast Bridge: http://' + HOST + ':' + PORT);
  console.log('OBS HUD: http://' + HOST + ':' + PORT + '/broadcast/');
  console.log('CS2 GSI endpoint: http://' + HOST + ':' + PORT + '/gsi');
  console.log('Only local connections are accepted. Keep this window open during the broadcast.');
});
