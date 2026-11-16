/* ARQON organizer auth + secure player-code redemption */
(() => {
  let organizerRole = null;

  const byId = (id) => document.getElementById(id);
  // Admin navigation is hidden by default; only a confirmed organizer role may reveal it.
  const hideAdminNavigation = () => {
    const button = byId('admin-tab-btn');
    const section = byId('tab-admin');
    if (button) { button.classList.add('hidden'); button.style.setProperty('display', 'none', 'important'); }
    if (section) { section.classList.add('hidden'); section.style.setProperty('display', 'none', 'important'); }
  };
  hideAdminNavigation();
  const setVisible = (el, visible) => {
    if (!el) return;
    el.classList.toggle('hidden', !visible);
    if (visible) el.style.removeProperty('display');
    else el.style.setProperty('display', 'none', 'important');
  };

  window.isAdmin = () => ['owner', 'admin', 'editor'].includes(organizerRole);
  window.isFullAdmin = () => ['owner', 'admin'].includes(organizerRole);
  setVisible(byId('admin-exclusive-profile-card'), false);

  function installPlayerAccountUi() {
    const header = document.querySelector('header');
    if (!header || byId('player-account-widget')) return;
    const widget = document.createElement('div');
    widget.id = 'player-account-widget';
    widget.className = 'player-account-widget';
    widget.innerHTML = `
      <button class="player-action-button player-match-trigger" id="player-match-trigger" type="button"><span aria-hidden="true">⚔</span><span>МОЙ МАТЧ</span></button>
      <button class="player-account-trigger" id="player-account-trigger" type="button" aria-label="Открыть профиль игрока">
        <img id="player-account-avatar" alt="" src="">
        <span id="player-account-name">Игрок</span>
      </button>`;
    header.appendChild(widget);
    byId('player-match-trigger').addEventListener('click', () => window.showPlayerMatchPanel?.());
    byId('player-account-trigger').addEventListener('click', () => window.showPlayerMatchPanel?.());
    const panelHeader = byId('player-screen')?.querySelector('.card');
    if (panelHeader && !byId('player-match-close')) {
      const close = document.createElement('button');
      close.id = 'player-match-close';
      close.className = 'player-action-button player-match-close';
      close.type = 'button';
      close.innerHTML = '<span aria-hidden="true">⌃</span><span>СВЕРНУТЬ</span>';
      close.addEventListener('click', () => window.hidePlayerMatchPanel?.());
      const actions = panelHeader.querySelector('div:last-child');
      if (actions) {
        actions.classList.add('player-dashboard-actions');
        actions.appendChild(close);
      }
    }
  }

  function installMyProfileButton(visible) {
    const header = document.querySelector('header');
    if (!header) return;
    let button = byId('arqon-my-profile-link');
    if (!button) {
      button = document.createElement('button');
      button.id = 'arqon-my-profile-link';
      button.type = 'button';
      button.textContent = 'МОЙ ПРОФИЛЬ';
      button.setAttribute('aria-label', 'Открыть настройки аккаунта и Telegram');
      button.style.cssText = 'display:none;align-items:center;justify-content:center;min-height:38px;padding:0 14px;margin-left:8px;border:1px solid rgba(167,139,250,.5);border-radius:9px;background:rgba(139,92,246,.14);color:#e9ddff;font:700 12px Rajdhani,sans-serif;letter-spacing:1px;white-space:nowrap;flex:0 0 auto;cursor:pointer';
      header.appendChild(button);
      button.addEventListener('click', openMyProfileSettings);
    }
    button.style.display = visible ? 'inline-flex' : 'none';

    if (!byId('arqon-my-profile-modal')) {
      const modal = document.createElement('div');
      modal.id = 'arqon-my-profile-modal';
      modal.style.cssText = 'display:none;position:fixed;inset:0;z-index:2400;background:rgba(3,2,10,.82);backdrop-filter:blur(8px);align-items:center;justify-content:center;padding:16px';
      modal.innerHTML = `
        <section role="dialog" aria-modal="true" aria-labelledby="arqon-my-profile-title" style="width:min(460px,100%);max-height:min(88vh,760px);overflow:auto;background:linear-gradient(160deg,#171329,#0d0b16);border:1px solid rgba(167,139,250,.45);border-radius:18px;padding:20px;box-shadow:0 24px 90px rgba(0,0,0,.65);color:#f7f3ff;font-family:Rajdhani,sans-serif">
          <div style="display:flex;align-items:center;justify-content:space-between;gap:12px">
            <div><div style="font:700 10px Orbitron,sans-serif;letter-spacing:2px;color:#bda2ff">ARQON ACCOUNT</div><h2 id="arqon-my-profile-title" style="font:700 18px Orbitron,sans-serif;margin:6px 0 0">МОЙ ПРОФИЛЬ</h2></div>
            <button id="arqon-my-profile-close" type="button" aria-label="Закрыть" style="width:38px;height:38px;border:1px solid #51436f;border-radius:10px;background:#211a32;color:#fff;font-size:22px;cursor:pointer">×</button>
          </div>
          <p style="color:#b8afc9;font-size:14px;margin:12px 0 16px">Подключи Telegram, чтобы получать уведомления о новых обращениях игроков и отвечать им прямо через бота.</p>
          <div style="padding:15px;border:1px solid rgba(139,92,246,.38);border-radius:13px;background:rgba(139,92,246,.08)">
            <div style="font:700 11px Orbitron,sans-serif;letter-spacing:1.5px;color:#d9c4ff;margin-bottom:9px">TELEGRAM · ТЕХПОДДЕРЖКА</div>
            <div id="arqon-my-profile-telegram-status" role="status" style="font-size:14px;color:#d8d0e6">Проверяем подключение…</div>
            <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:13px">
              <button id="arqon-my-profile-telegram-connect" type="button" style="border:0;border-radius:10px;padding:11px 15px;background:linear-gradient(110deg,#6d28d9,#8b5cf6);color:#fff;font:700 13px Rajdhani,sans-serif;cursor:pointer">Подключить Telegram</button>
              <button id="arqon-my-profile-telegram-unlink" type="button" style="display:none;border:1px solid #69558c;border-radius:10px;padding:11px 15px;background:transparent;color:#e9ddff;font:700 13px Rajdhani,sans-serif;cursor:pointer">Отключить</button>
            </div>
            <div id="arqon-my-profile-telegram-codebox" style="display:none;margin-top:13px;padding-top:12px;border-top:1px solid #403451">
              <p style="font-size:13px;color:#b8afc9;margin:0 0 8px">Открой бота и отправь ему эту команду в течение 10 минут:</p>
              <code id="arqon-my-profile-telegram-code" style="display:block;overflow-wrap:anywhere;padding:11px;border-radius:9px;background:#090812;color:#e5d5ff"></code>
              <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:9px">
                <button id="arqon-my-profile-telegram-copy" type="button" style="border:1px solid #69558c;border-radius:9px;padding:9px 12px;background:transparent;color:#e9ddff;font:700 12px Rajdhani,sans-serif;cursor:pointer">Скопировать команду</button>
                <a id="arqon-my-profile-telegram-bot" href="https://t.me/arqon_esports_bot" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;border-radius:9px;padding:9px 12px;background:#7138c9;color:white;text-decoration:none;font:700 12px Rajdhani,sans-serif">Открыть @arqon_esports_bot</a>
              </div>
            </div>
          </div>
          <p style="font-size:12px;color:#9188a3;margin:12px 0 0">Подключённый Telegram используется для служебных уведомлений ARQON. Твой @username не показывается другим игрокам.</p>
        </section>`;
      document.body.appendChild(modal);
      byId('arqon-my-profile-close').addEventListener('click', closeMyProfileSettings);
      modal.addEventListener('click', event => { if (event.target === modal) closeMyProfileSettings(); });
      byId('arqon-my-profile-telegram-connect').addEventListener('click', connectMyProfileTelegram);
      byId('arqon-my-profile-telegram-unlink').addEventListener('click', unlinkMyProfileTelegram);
      byId('arqon-my-profile-telegram-copy').addEventListener('click', async () => {
        const value = byId('arqon-my-profile-telegram-code')?.textContent || '';
        try { await navigator.clipboard.writeText(value); byId('arqon-my-profile-telegram-copy').textContent = 'Скопировано'; }
        catch (_) { const range=document.createRange();range.selectNodeContents(byId('arqon-my-profile-telegram-code'));const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range); }
      });
    }
  }

  function openMyProfileSettings() {
    const modal = byId('arqon-my-profile-modal');
    if (!modal) return;
    modal.style.display = 'flex';
    loadMyProfileTelegramStatus();
  }
  function closeMyProfileSettings() {
    const modal = byId('arqon-my-profile-modal');
    if (modal) modal.style.display = 'none';
  }
  async function loadMyProfileTelegramStatus() {
    const status = byId('arqon-my-profile-telegram-status');
    const connect = byId('arqon-my-profile-telegram-connect');
    const unlink = byId('arqon-my-profile-telegram-unlink');
    const codebox = byId('arqon-my-profile-telegram-codebox');
    if (!status || !window.supabaseClient) return;
    status.textContent = 'Проверяем подключение…';
    const { data, error } = await supabaseClient.rpc('get_telegram_link_status');
    if (error) { status.textContent = 'Не удалось проверить Telegram: ' + (error.message || 'ошибка'); return; }
    const state = data?.[0];
    if (state?.is_linked) {
      status.textContent = 'Telegram подключён' + (state.telegram_username ? ' · @' + state.telegram_username : state.first_name ? ' · ' + state.first_name : '') + '. Уведомления техподдержки включены.';
      connect.style.display = 'none'; unlink.style.display = 'inline-flex'; codebox.style.display = 'none';
    } else {
      status.textContent = 'Telegram не подключён. Подключи его, чтобы получать обращения игроков.';
      connect.style.display = 'inline-flex'; unlink.style.display = 'none';
    }
  }
  async function connectMyProfileTelegram() {
    const button = byId('arqon-my-profile-telegram-connect');
    const status = byId('arqon-my-profile-telegram-status');
    button.disabled = true; button.textContent = 'Создаём код…';
    const { data, error } = await supabaseClient.rpc('create_telegram_link_token');
    button.disabled = false; button.textContent = 'Подключить Telegram';
    if (error) { status.textContent = error.message || 'Не удалось создать код.'; return; }
    const token = data?.[0]?.link_token;
    if (!token) { status.textContent = 'Сервер не вернул код подключения.'; return; }
    byId('arqon-my-profile-telegram-code').textContent = '/start ' + token;
    byId('arqon-my-profile-telegram-bot').href = 'https://t.me/arqon_esports_bot?start=' + encodeURIComponent(token);
    byId('arqon-my-profile-telegram-codebox').style.display = 'block';
    status.textContent = 'Код действует 10 минут и используется один раз.';
  }
  async function unlinkMyProfileTelegram() {
    if (!window.confirm('Отключить Telegram от ARQON?')) return;
    const { error } = await supabaseClient.rpc('unlink_telegram_account');
    if (error) { byId('arqon-my-profile-telegram-status').textContent = error.message || 'Не удалось отключить Telegram.'; return; }
    await loadMyProfileTelegramStatus();
  }

  function installSessionLogoutButton() {
    const header = document.querySelector('header');
    if (!header || byId('arqon-session-logout')) return;
    const button = document.createElement('button');
    button.id = 'arqon-session-logout';
    button.type = 'button';
    button.textContent = 'ВЫЙТИ';
    button.setAttribute('aria-label', 'Выйти из аккаунта ARQON');
    button.style.cssText = 'display:none;align-items:center;justify-content:center;min-height:38px;padding:0 14px;margin-left:10px;border:1px solid rgba(248,113,113,.45);border-radius:9px;background:rgba(127,29,29,.16);color:#fecaca;font:700 12px Rajdhani,sans-serif;letter-spacing:1px;cursor:pointer;flex:0 0 auto';
    button.addEventListener('click', async () => {
      if (button.disabled) return;
      button.disabled = true;
      button.textContent = 'ВЫХОД…';
      try {
        localStorage.removeItem('arqon_current_uid');
        localStorage.removeItem('arqon_current_name');
        await supabaseClient.auth.signOut({ scope: 'local' });
      } catch (error) {
        console.error('Не удалось завершить сессию ARQON:', error);
      } finally {
        window.location.replace('/');
      }
    });
    header.appendChild(button);
  }

  function setLogoutVisible(visible) {
    installSessionLogoutButton();
    const button = byId('arqon-session-logout');
    if (button) button.style.display = visible ? 'inline-flex' : 'none';
  }

  function setPlayerAccount(player) {
    if (!player) return;
    const widget = byId('player-account-widget');
    const name = String(player.name || localStorage.getItem('arqon_current_name') || 'Игрок');
    const avatar = String(player.avatar || player.avatar_url || player.photo_url || '');
    if (byId('player-account-name')) byId('player-account-name').textContent = name;
    const img = byId('player-account-avatar');
    if (img) {
      img.src = avatar || ('https://ui-avatars.com/api/?name=' + encodeURIComponent(name) + '&background=7A3BFF&color=fff&size=96&bold=true');
      img.onerror = () => { img.src = 'https://ui-avatars.com/api/?name=' + encodeURIComponent(name) + '&background=7A3BFF&color=fff&size=96&bold=true'; };
    }
    widget?.classList.add('visible');
    const displayName = byId('player-display-name');
    if (displayName) displayName.textContent = name;
  }

  window.showPlayerMatchPanel = function() {
    const screen = byId('player-screen');
    if (!screen) return;
    screen.classList.remove('hidden');
    screen.classList.add('player-match-open');
    screen.style.display = 'flex';
  };
  window.hidePlayerMatchPanel = function() {
    const screen = byId('player-screen');
    if (!screen) return;
    screen.classList.remove('player-match-open');
    screen.classList.add('hidden');
    screen.style.display = 'none';
  };

  const ARQON_MANUAL_AWARDS = {
    founder:{name:'Основатель ARQON',description:'Особый вклад в создание сообщества',icon:'👑'},
    community:{name:'Душа сообщества',description:'Значимый вклад в развитие сообщества',icon:'💜'},
    event_mvp:{name:'MVP события',description:'Лучший игрок отдельного события',icon:'🏆'},
    champion:{name:'Чемпион ARQON',description:'Особое признание за чемпионский результат',icon:'🥇'},
    fair_play:{name:'Честная игра',description:'Пример спортивного поведения',icon:'🤝'},
    legend:{name:'Легенда ARQON',description:'Особое признание от организаторов',icon:'⚡'}
  };
  async function refreshAwardAdminList(){
    const host=byId('arqon-awards-admin-list');if(!host)return;
    host.textContent='Загружаем награды…';
    const {data,error}=await supabaseClient.from('arqon_player_awards')
      .select('id,arqon_id,award_name,award_icon,rarity,reason,granted_at,revoked_at,revoke_reason,profiles(display_name)')
      .order('granted_at',{ascending:false}).limit(100);
    if(error){host.textContent='Не удалось загрузить награды: '+error.message;return}
    host.replaceChildren();
    if(!data?.length){host.textContent='Пока нет выданных наград.';return}
    const labels={common:'Обычная',rare:'Редкая',epic:'Эпическая',legendary:'Легендарная'};
    data.forEach(row=>{
      const item=document.createElement('div');
      item.style.cssText='display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 0;border-bottom:1px solid rgba(167,139,250,.16);flex-wrap:wrap';
      const info=document.createElement('div');info.style.minWidth='0';info.style.flex='1';
      const title=document.createElement('strong');title.textContent=(row.award_icon||'🏅')+' '+row.award_name+' · '+(row.profiles?.display_name||('#'+row.arqon_id));
      const meta=document.createElement('small');meta.style.cssText='display:block;color:#aaa;margin-top:4px';meta.textContent=(labels[row.rarity]||row.rarity)+' · '+row.reason+' · '+new Date(row.granted_at).toLocaleDateString('ru-RU');
      info.append(title,meta);
      if(row.revoked_at){
        const revoked=document.createElement('small');revoked.style.cssText='display:block;color:#fca5a5;margin-top:5px';revoked.textContent='Отозвана '+new Date(row.revoked_at).toLocaleDateString('ru-RU')+(row.revoke_reason?' · '+row.revoke_reason:'');info.append(revoked);
      }
      item.append(info);
      if(!row.revoked_at){const revoke=document.createElement('button');revoke.type='button';revoke.className='btn ghost';revoke.textContent='Отозвать';revoke.dataset.revokeAward=String(row.id);item.append(revoke)}
      host.append(item);
    });
  }
  async function installAwardAdminPanel(){
    const section=byId('tab-admin');if(!section||byId('arqon-awards-admin'))return;
    const card=document.createElement('div');card.className='card';card.id='arqon-awards-admin';
    card.innerHTML='<h2>🏅 Награды игроков ARQON</h2><p style="color:#aaa">Выдача особых наград и управление активной коллекцией игроков.</p><div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:10px"><label>Игрок<select id="arqon-award-player" style="width:100%;margin-top:5px"><option value="">Загрузка игроков…</option></select></label><label>Награда<select id="arqon-award-type" style="width:100%;margin-top:5px"><option value="founder">Основатель ARQON</option><option value="community">Душа сообщества</option><option value="event_mvp">MVP события</option><option value="champion">Чемпион ARQON</option><option value="fair_play">Честная игра</option><option value="legend">Легенда ARQON</option></select></label><label>Редкость<select id="arqon-award-rarity" style="width:100%;margin-top:5px"><option value="common">Обычная</option><option value="rare">Редкая</option><option value="epic">Эпическая</option><option value="legendary">Легендарная</option></select></label></div><label style="display:block;margin-top:12px">Причина выдачи<textarea id="arqon-award-reason" maxlength="300" rows="2" placeholder="За что игрок получает награду?" style="width:100%;margin-top:5px"></textarea></label><button type="button" class="btn" id="arqon-award-grant" style="margin-top:10px">Выдать награду</button><p id="arqon-award-status" role="status" style="color:#c4b5fd"></p><h3 style="margin-top:22px">Активные награды</h3><div id="arqon-awards-admin-list"></div>';
    section.prepend(card);
    const playerSelect=byId('arqon-award-player');
    const {data:players,error}=await supabaseClient.rpc('list_public_player_profiles');
    if(error){playerSelect.replaceChildren(new Option('Не удалось загрузить игроков',''));byId('arqon-award-status').textContent=error.message;return}
    playerSelect.replaceChildren(new Option('Выбери игрока',''));
    (players||[]).filter(p=>p.arqon_id).sort((a,b)=>String(a.player_name||'').localeCompare(String(b.player_name||''),'ru')).forEach(p=>{
      const option=new Option((p.player_name||p.display_name||'Игрок')+' · #'+p.arqon_id,String(p.arqon_id));playerSelect.add(option);
    });
    byId('arqon-award-grant').addEventListener('click',async()=>{
      const button=byId('arqon-award-grant'),status=byId('arqon-award-status');
      const arqonId=Number(playerSelect.value),key=byId('arqon-award-type').value,rarity=byId('arqon-award-rarity').value,reason=byId('arqon-award-reason').value.trim();
      if(!Number.isSafeInteger(arqonId)||arqonId<1){status.textContent='Сначала выбери игрока.';return}
      if(reason.length<3){status.textContent='Укажи причину (не менее 3 символов).';return}
      const award=ARQON_MANUAL_AWARDS[key];if(!award)return;
      button.disabled=true;status.textContent='Выдаём награду…';
      const {data:userData,error:userError}=await supabaseClient.auth.getUser();
      if(userError||!userData?.user){status.textContent='Не удалось подтвердить администратора.';button.disabled=false;return}
      const {error}=await supabaseClient.from('arqon_player_awards').insert({arqon_id:arqonId,award_key:key,award_name:award.name,award_description:award.description,award_icon:award.icon,rarity,reason,granted_by:userData.user.id});
      button.disabled=false;
      if(error){status.textContent=error.code==='23505'?'У этого игрока уже есть такая активная награда.':error.message;return}
      status.textContent='Награда выдана.';byId('arqon-award-reason').value='';await refreshAwardAdminList();
    });
    byId('arqon-awards-admin-list').addEventListener('click',async event=>{
      const button=event.target.closest('[data-revoke-award]');if(!button)return;
      if(!window.confirm('Отозвать эту награду? Запись останется в истории.'))return;
      button.disabled=true;
      const {data:userData}=await supabaseClient.auth.getUser();
      const {error}=await supabaseClient.from('arqon_player_awards').update({revoked_at:new Date().toISOString(),revoked_by:userData?.user?.id||null,revoke_reason:'Отозвана организатором'}).eq('id',Number(button.dataset.revokeAward)).is('revoked_at',null);
      if(error){button.disabled=false;byId('arqon-award-status').textContent='Не удалось отозвать: '+error.message;return}
      byId('arqon-award-status').textContent='Награда отозвана, запись сохранена.';await refreshAwardAdminList();
    });
    await refreshAwardAdminList();
  }

  let serviceAccessRows = [];
  async function refreshServiceAccessAdminList() {
    if (organizerRole !== 'owner') return;
    const status = byId('service-access-admin-status');
    const host = byId('service-access-admin-list');
    if (!status || !host) return;
    status.textContent = 'Загружаем аккаунты…';
    const { data, error } = await supabaseClient.rpc('list_service_access_accounts');
    if (error) { status.textContent = 'Не удалось загрузить аккаунты: ' + error.message; return; }
    serviceAccessRows = Array.isArray(data) ? data : [];
    renderServiceAccessAdminList();
  }
  function renderServiceAccessAdminList() {
    const host = byId('service-access-admin-list');
    const status = byId('service-access-admin-status');
    if (!host || !status) return;
    const search = String(byId('service-access-admin-search')?.value || '').trim().toLocaleLowerCase();
    const rows = serviceAccessRows.filter(row => [row.display_name, row.email, row.organizer_role].some(value => String(value || '').toLocaleLowerCase().includes(search)));
    host.replaceChildren();
    if (!rows.length) host.textContent = serviceAccessRows.length ? 'По запросу ничего не найдено.' : 'Аккаунтов пока нет.';
    rows.forEach(account => {
      const card = document.createElement('div');
      card.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;padding:12px;margin-top:8px;border:1px solid rgba(139,92,246,.22);border-radius:9px;background:rgba(10,10,15,.72)';
      const info = document.createElement('div'); info.style.cssText = 'min-width:0;flex:1';
      const name = document.createElement('strong'); name.textContent = account.display_name || account.email || ('Аккаунт ' + String(account.user_id || '').slice(0,8));
      const meta = document.createElement('div'); meta.style.cssText = 'font-size:12px;color:#999;overflow-wrap:anywhere'; meta.textContent = (account.email || 'Email не указан') + ' · регистрация ' + (account.created_at ? new Date(account.created_at).toLocaleDateString('ru-RU') : '—');
      const state = document.createElement('div'); state.style.cssText = 'font-size:12px;color:#b9a3e8;margin-top:4px';
      const currentRole = account.organizer_role;
      if (currentRole === 'owner') state.textContent = 'Владелец · доступ защищён';
      else if (currentRole === 'judge') state.textContent = 'Судья · отдельный ограниченный доступ';
      else if (currentRole === 'admin') state.textContent = 'Полный доступ организатора · администратор';
      else if (currentRole === 'editor') state.textContent = 'Полный доступ организатора · редактор';
      else if (currentRole === 'bracket_editor') state.textContent = 'Доступ есть · только конструктор сеток';
      else state.textContent = 'Нет доступа к конструктору сеток';
      info.append(name, meta, state); card.append(info);
      if (currentRole === 'bracket_editor' || currentRole === 'admin' || currentRole === 'editor') {
        const button = document.createElement('button'); button.type = 'button'; button.className = 'btn danger';
        button.textContent = currentRole === 'bracket_editor' ? 'Отозвать доступ' : 'Снять все права';
        button.dataset.serviceAccessUser = account.user_id; button.dataset.allowed = 'false'; card.append(button);
      } else if (!currentRole) {
        const button = document.createElement('button'); button.type = 'button'; button.className = 'btn'; button.textContent = 'Разрешить доступ';
        button.dataset.serviceAccessUser = account.user_id; button.dataset.allowed = 'true'; card.append(button);
      }
      host.append(card);
    });
    status.textContent = 'Аккаунтов: ' + serviceAccessRows.length + ' · показано: ' + rows.length;
  }
  async function installOrganizerAccessAdminPanel() {
    if (organizerRole !== 'owner') return;
    const section = byId('tab-admin');
    if (!section || byId('organizer-service-access-admin')) return;
    const card = document.createElement('div'); card.className = 'card'; card.id = 'organizer-service-access-admin';
    card.innerHTML = '<h2>🔐 Доступ к служебному входу</h2><p class="hint" style="margin-bottom:12px">Только владелец может разрешать и отзывать доступ к редактору турнирных сеток. Новым пользователям выдаётся отдельная роль только для конструктора сеток — без доступа к общей админке. Действующие администраторы и редакторы сохраняют свои прежние права.</p><div style="display:flex;gap:8px;flex-wrap:wrap"><input id="service-access-admin-search" type="search" placeholder="Поиск по имени или email" style="flex:1;min-width:180px"><button type="button" class="btn ghost" id="service-access-admin-refresh">Обновить</button></div><p id="service-access-admin-status" class="hint" role="status" style="margin-top:10px">Загружаем аккаунты…</p><div id="service-access-admin-list"></div>';
    section.prepend(card);
    byId('service-access-admin-refresh').addEventListener('click', refreshServiceAccessAdminList);
    byId('service-access-admin-search').addEventListener('input', renderServiceAccessAdminList);
    byId('service-access-admin-list').addEventListener('click', async event => {
      const button = event.target.closest('[data-service-access-user]');
      if (!button || organizerRole !== 'owner') return;
      const userId = button.dataset.serviceAccessUser;
      const allowed = button.dataset.allowed === 'true';
      const account = serviceAccessRows.find(row => row.user_id === userId);
      if (!account) return;
      const label = account.display_name || account.email || 'этого пользователя';
      if (!allowed) { const fullRole = account.organizer_role === 'admin' || account.organizer_role === 'editor'; const question = fullRole ? 'Снять ВСЕ права организатора у ' + label + '? Пользователь потеряет доступ ко всей админ-панели и конструктору.' : 'Отозвать доступ к конструктору у ' + label + '?'; if (!window.confirm(question)) return; }
      button.disabled = true;
      const { error } = await supabaseClient.rpc('set_service_access', { p_user_id: userId, p_allowed: allowed });
      button.disabled = false;
      if (error) { byId('service-access-admin-status').textContent = 'Не удалось изменить доступ: ' + error.message; return; }
      byId('service-access-admin-status').textContent = allowed ? 'Доступ разрешён для ' + label + '.' : 'Доступ отозван у ' + label + '.';
      await refreshServiceAccessAdminList();
    });
    await refreshServiceAccessAdminList();
  }

  function installOrganizerUi() {
    installPlayerAccountUi();
    installSessionLogoutButton();
    const home = byId('tab-home');
    if (home && !byId('organizer-login-btn')) {
      const footer = document.createElement('div');
      footer.className = 'organizer-entry-footer';
      const button = document.createElement('button');
      button.id = 'organizer-login-btn';
      button.type = 'button';
      button.className = 'organizer-login-link';
      button.textContent = 'Вход для организатора';
      button.addEventListener('click', () => {
        const modal = byId('organizer-auth-modal');
        if (modal) modal.style.display = 'flex';
      });
      footer.appendChild(button);
      const serviceLink = document.createElement('a');
      serviceLink.href = '/bracket-builder/';
      serviceLink.className = 'organizer-login-link';
      serviceLink.textContent = 'служебный вход';
      serviceLink.style.cssText = 'opacity:.18;text-decoration:none;font-size:9px;margin-left:8px;letter-spacing:1px';
      serviceLink.addEventListener('mouseenter', () => { serviceLink.style.opacity = '.75'; });
      serviceLink.addEventListener('mouseleave', () => { serviceLink.style.opacity = '.18'; });
      footer.appendChild(serviceLink);
      const bracketTab = byId('tab-bracket');
      if (bracketTab && !byId('published-bracket-link')) {
        const link = document.createElement('a');
        link.id = 'published-bracket-link';
        link.href = '/bracket-builder/';
        link.textContent = 'Открыть опубликованные турнирные сетки →';
        link.style.cssText = 'display:inline-block;margin:12px 0;color:#c4b5fd;font-size:12px;text-decoration:none';
        bracketTab.appendChild(link);
      }
      home.appendChild(footer);
    }

    if (!byId('organizer-auth-modal')) {
      const modal = document.createElement('div');
      modal.id = 'organizer-auth-modal';
      modal.style.cssText = 'display:none;position:fixed;inset:0;z-index:2000;background:rgba(0,0,0,.82);align-items:center;justify-content:center;padding:20px';
      modal.innerHTML = `
        <div style="width:min(420px,100%);background:#15151a;border:1px solid #8b3bff;border-radius:12px;padding:24px;position:relative">
          <button id="organizer-auth-close" type="button" style="position:absolute;right:12px;top:8px;background:none;border:0;color:#aaa;font-size:26px">×</button>
          <h2 style="margin-bottom:8px">Вход организатора</h2>
          <p style="color:#aaa;margin-bottom:16px">Введи почту приглашённого организатора. Мы отправим одноразовую ссылку для входа.</p>
          <input id="organizer-auth-email" type="email" autocomplete="email" placeholder="Email организатора" style="width:100%;padding:12px;margin-bottom:12px;background:#09090d;color:#fff;border:1px solid #444;border-radius:6px">
          <button id="organizer-auth-send" class="btn" type="button" style="width:100%">Отправить ссылку</button>
          <p id="organizer-auth-message" role="status" style="margin-top:12px;color:#aaa"></p>
        </div>`;
      document.body.appendChild(modal);
      byId('organizer-auth-close').addEventListener('click', () => { modal.style.display = 'none'; });
      modal.addEventListener('click', (event) => { if (event.target === modal) modal.style.display = 'none'; });
      byId('organizer-auth-send').addEventListener('click', sendOrganizerLink);
    }
  }

  async function sendOrganizerLink() {
    const email = (byId('organizer-auth-email')?.value || '').trim();
    const message = byId('organizer-auth-message');
    const button = byId('organizer-auth-send');
    if (!email) { if (message) message.textContent = 'Укажи email.'; return; }
    button.disabled = true;
    message.textContent = 'Отправляем ссылку…';
    try {
      const { error } = await supabaseClient.auth.signInWithOtp({
        email,
        options: { shouldCreateUser: false, emailRedirectTo: window.location.origin }
      });
      if (error) throw error;
      message.textContent = 'Если аккаунт приглашён, ссылка отправлена на почту.';
    } catch (error) {
      message.textContent = error.message || 'Не удалось отправить ссылку.';
    } finally {
      button.disabled = false;
    }
  }

  let accountManagementRows = [];
  async function callAccountManagement(payload) {
    const { data, error } = await supabaseClient.functions.invoke('manage-arqon-accounts', { body: payload || { action: 'list' } });
    if (error) {
      let message = error.message || 'Ошибка запроса.';
      try { const details = await error.context?.json?.(); if (details?.error) message = details.error; } catch (_) {}
      throw new Error(message);
    }
    if (data?.error) throw new Error(data.error);
    return data;
  }
  function renderAccountManagementList() {
    const host = byId('arqon-account-management-list');
    const status = byId('arqon-account-management-status');
    if (!host || !status) return;
    const query = String(byId('arqon-account-management-search')?.value || '').trim().toLocaleLowerCase();
    const filtered = accountManagementRows.filter(row => [
      row.email, row.display_name, row.arqon_id, row.organizer_role, row.id
    ].some(value => String(value ?? '').toLocaleLowerCase().includes(query)));
    host.replaceChildren();
    if (!filtered.length) {
      const empty = document.createElement('p');
      empty.className = 'hint';
      empty.textContent = accountManagementRows.length ? 'По запросу ничего не найдено.' : 'Аккаунтов нет.';
      host.append(empty);
    }
    filtered.forEach(account => {
      const card = document.createElement('article');
      card.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;padding:13px;margin-top:9px;border:1px solid rgba(139,92,246,.25);border-radius:12px;background:rgba(8,8,14,.72)';
      const info = document.createElement('div');
      info.style.cssText = 'min-width:220px;flex:1;overflow-wrap:anywhere';
      const heading = document.createElement('strong');
      heading.style.cssText = 'display:block;color:#f5efff;font-size:16px';
      heading.textContent = account.display_name || account.email || ('Аккаунт ' + account.id.slice(0,8));
      const meta = document.createElement('div');
      meta.style.cssText = 'font-size:13px;color:#a9a1b8;margin-top:3px';
      meta.textContent = (account.email || 'Email отсутствует') +
        (account.arqon_id ? ' · ARQON ID #' + account.arqon_id : '') +
        ' · регистрация ' + (account.created_at ? new Date(account.created_at).toLocaleDateString('ru-RU') : '—');
      const state = document.createElement('div');
      state.style.cssText = 'font-size:13px;margin-top:5px;color:#bda2ff';
      const isBanned = !!account.banned_until && new Date(account.banned_until).getTime() > Date.now();
      if (account.organizer_role) {
        state.textContent = 'Защищённая роль: ' + account.organizer_role + ' · управление через раздел прав организаторов';
      } else if (isBanned) {
        state.textContent = 'ЗАБЛОКИРОВАН · до ' + new Date(account.banned_until).toLocaleString('ru-RU');
        state.style.color = '#fca5a5';
      } else {
        state.textContent = account.email_confirmed_at ? 'Аккаунт активен · email подтверждён' : 'Email не подтверждён';
      }
      info.append(heading, meta, state);
      card.append(info);
      if (!account.organizer_role) {
        const actions = document.createElement('div');
        actions.style.cssText = 'display:flex;gap:7px;flex-wrap:wrap';
        const ban = document.createElement('button');
        ban.type = 'button'; ban.className = isBanned ? 'btn ghost' : 'btn danger';
        ban.textContent = isBanned ? 'Разблокировать' : 'Заблокировать';
        ban.dataset.accountAction = isBanned ? 'unban' : 'ban';
        ban.dataset.accountId = account.id;
        actions.append(ban);
        const del = document.createElement('button');
        del.type = 'button'; del.className = 'btn danger';
        del.textContent = 'Удалить';
        del.dataset.accountAction = 'delete';
        del.dataset.accountId = account.id;
        actions.append(del);
        card.append(actions);
      }
      host.append(card);
    });
    status.textContent = 'Всего аккаунтов: ' + accountManagementRows.length + ' · найдено: ' + filtered.length;
  }
  async function refreshAccountManagementList() {
    if (organizerRole !== 'owner') return;
    const status = byId('arqon-account-management-status');
    if (!status) return;
    status.textContent = 'Загружаем аккаунты…';
    const refresh = byId('arqon-account-management-refresh');
    if (refresh) refresh.disabled = true;
    try {
      const data = await callAccountManagement({ action: 'list' });
      accountManagementRows = Array.isArray(data.users) ? data.users : [];
      renderAccountManagementList();
    } catch (error) {
      status.textContent = 'Не удалось загрузить аккаунты: ' + error.message;
    } finally {
      if (refresh) refresh.disabled = false;
    }
  }
  async function installAccountManagementPanel() {
    if (organizerRole !== 'owner') return;
    const section = byId('tab-admin');
    if (!section || byId('arqon-account-management')) return;
    const card = document.createElement('section');
    card.className = 'card';
    card.id = 'arqon-account-management';
    card.innerHTML = '<h2>🛡️ Управление аккаунтами</h2><p class="hint" style="margin-bottom:12px">Блокировка и удаление обычных аккаунтов ARQON. Аккаунты владельца, администраторов, редакторов и судей защищены от действий здесь.</p><div style="display:flex;gap:8px;flex-wrap:wrap"><input id="arqon-account-management-search" type="search" placeholder="Поиск по email, нику или ARQON ID" style="flex:1;min-width:190px"><button type="button" class="btn ghost" id="arqon-account-management-refresh">Обновить</button></div><p id="arqon-account-management-status" class="hint" role="status" style="margin-top:10px">Загружаем аккаунты…</p><div id="arqon-account-management-list"></div>';
    section.prepend(card);
    byId('arqon-account-management-search').addEventListener('input', renderAccountManagementList);
    byId('arqon-account-management-refresh').addEventListener('click', refreshAccountManagementList);
    byId('arqon-account-management-list').addEventListener('click', async event => {
      const button = event.target.closest('[data-account-action][data-account-id]');
      if (!button || organizerRole !== 'owner') return;
      const account = accountManagementRows.find(row => row.id === button.dataset.accountId);
      if (!account || account.organizer_role) return;
      const action = button.dataset.accountAction;
      const label = account.display_name || account.email || 'этот аккаунт';
      const question = action === 'delete'
        ? 'Навсегда удалить аккаунт ' + label + '? Его профиль и связанные с Auth записи будут удалены. Это действие нельзя отменить.'
        : action === 'ban'
          ? 'Заблокировать аккаунт ' + label + '? Он не сможет войти снова, пока блокировка активна.'
          : 'Снять блокировку с аккаунта ' + label + '?';
      if (!window.confirm(question)) return;
      button.disabled = true;
      try {
        await callAccountManagement({ action, user_id: account.id });
        if (action === 'delete') accountManagementRows = accountManagementRows.filter(row => row.id !== account.id);
        else if (action === 'ban') account.banned_until = new Date(Date.now() + 100 * 365.25 * 24 * 60 * 60 * 1000).toISOString();
        else account.banned_until = null;
        renderAccountManagementList();
        const status = byId('arqon-account-management-status');
        if (status) status.textContent = action === 'delete' ? 'Аккаунт удалён.' : action === 'ban' ? 'Аккаунт заблокирован.' : 'Блокировка снята.';
      } catch (error) {
        const status = byId('arqon-account-management-status');
        if (status) status.textContent = 'Не удалось выполнить действие: ' + error.message;
        button.disabled = false;
      }
    });
    await refreshAccountManagementList();
  }

  window.checkUserRole = async function(uid) {
    // A valid auth event means the session exists: keep logout visible even when
    // this Steam account has not yet been mapped to the legacy players table.
    installSessionLogoutButton();
    installMyProfileButton(!!uid);
    setLogoutVisible(!!uid);
    try {
      const { data: role, error: roleError } = await supabaseClient.rpc('current_organizer_role');
      if (roleError) throw roleError;
      organizerRole = role || null;
    } catch (error) {
      console.error('Organizer role lookup failed:', error);
      organizerRole = null;
    }
    window.dispatchEvent(new CustomEvent('arqon:organizer-role-ready', { detail: { role: organizerRole } }));
    setVisible(byId('admin-exclusive-profile-card'), window.isFullAdmin());

    if (window.isAdmin()) {
      setLogoutVisible(true);
      const adminButton = byId('admin-tab-btn');
      if (adminButton) { adminButton.classList.remove('hidden'); adminButton.style.removeProperty('display'); }
      const auth = byId('auth-screen');
      if (auth) auth.style.display = 'none';
      const player = byId('player-screen');
      if (player) { player.classList.add('hidden'); player.style.display = 'none'; }
      const main = document.querySelector('main');
      if (main) main.style.display = 'block';
      setVisible(byId('tab-home'), true);
      const adminSection = byId('tab-admin');
      await installAwardAdminPanel();
      if (organizerRole === 'owner') await installOrganizerAccessAdminPanel();
      if (organizerRole === 'owner') await installAccountManagementPanel();
      if (adminSection && !byId('bracket-builder-admin-link')) {
        const card = document.createElement('div');
        card.className = 'card';
        card.id = 'bracket-builder-admin-link';
        card.innerHTML = '<h2>🎯 Конструктор турнирных сеток</h2><p style="color:#aaa">Создание сеток, соединение матчей, публикация и назначение судей.</p><a href="/bracket-builder/" class="btn" style="display:inline-block;text-decoration:none">Открыть конструктор</a>';
        adminSection.prepend(card);
      }
      setVisible(byId('tab-admin'), true);
      setVisible(byId('tab-bracket'), false);
      if (typeof initSupabaseSync === 'function') initSupabaseSync();
      if (typeof loadLeague === 'function') loadLeague(true);
      const loginButton = byId('organizer-login-btn');
      if (loginButton) {
        const activeButton = loginButton.cloneNode(true);
        activeButton.textContent = 'Выйти из панели';
        loginButton.replaceWith(activeButton);
        activeButton.addEventListener('click', async () => {
          localStorage.removeItem('arqon_current_uid');
          localStorage.removeItem('arqon_current_name');
          await supabaseClient.auth.signOut({ scope: 'local' });
          window.location.replace('/');
        });
      }
      return;
    }

    // A missing/ordinary player role must never leave organizer navigation visible.
    hideAdminNavigation();
    setLogoutVisible(!!(await supabaseClient.auth.getSession()).data?.session?.user);

    // Steam-linked player accounts stay in onboarding until their email is verified.
    try {
      const [{ data: steamProfile }, { data: authUserData }] = await Promise.all([
        supabaseClient.from('profiles').select('steam_id').eq('user_id', uid).maybeSingle(),
        supabaseClient.auth.getUser()
      ]);
      if (steamProfile?.steam_id && authUserData?.user && !authUserData.user.email_confirmed_at) {
        if (typeof window.handleNoAuth === 'function') window.handleNoAuth();
        await window.ensureSteamEmailStep?.();
        return;
      }
    } catch (verificationGateError) {
      console.warn('Steam email verification gate check failed:', verificationGateError);
    }

    const { data: player, error } = await supabaseClient.from('players').select('*').eq('uid', uid).maybeSingle();
    if (error) console.error('Player lookup failed:', error);
    if (player) {
      if (byId('auth-screen')) byId('auth-screen').style.display = 'none';
      installPlayerAccountUi();
      const main = document.querySelector('main');
      if (main) main.style.display = 'block';
      window.hidePlayerMatchPanel?.();
      let account = player;
      if (!account.avatar && !account.avatar_url && typeof collectPlayerAvatars === 'function') {
        try {
          const { data: tournament } = await supabaseClient.from('tournament').select('data').eq('id', 1).maybeSingle();
          const avatars = collectPlayerAvatars(tournament?.data || {});
          account = { ...player, avatar: avatars[String(player.name || '').trim().toLocaleLowerCase()] || '' };
        } catch (avatarError) {
          console.warn('Player avatar lookup failed:', avatarError);
        }
      }
      setPlayerAccount(account);
      setLogoutVisible(true);
      if (typeof startDraftListener === 'function') startDraftListener(uid);
      if (typeof applyPathRoute === 'function') applyPathRoute();
    } else {
      // The account may be new and have no legacy players row yet.
      // Do not hide logout: the Supabase session is still active.
      if (typeof handleNoAuth === 'function') handleNoAuth();
    }
  };

  supabaseClient.auth.getSession().then(({ data }) => {
    if (data?.session?.user) window.checkUserRole(data.session.user.id);
  }).catch((error) => console.error('Session restore failed:', error));

  window.loginWithCode = async function() {
    const code = (byId('auth-code')?.value || '').trim().toUpperCase();
    if (!code) return;
    const button = byId('login-btn');
    const oldText = button?.textContent || 'Войти';
    const errorDiv = byId('auth-error');
    if (button) { button.disabled = true; button.textContent = 'Подключение…'; }
    if (errorDiv) { errorDiv.classList.add('hidden'); errorDiv.textContent = ''; }
    try {
      const { data: sessionData, error: sessionError } = await supabaseClient.auth.getSession();
      if (sessionError) throw sessionError;
      let session = sessionData.session;
      if (!session?.user) {
        const { data, error } = await supabaseClient.auth.signInAnonymously();
        if (error) throw error;
        session = data.session;
      }
      const { data, error } = await supabaseClient.functions.invoke('redeem-player-code', { body: { code } });
      if (error) throw error;
      if (!data?.player_name) throw new Error('Сервер не подтвердил код доступа.');
      localStorage.setItem('arqon_current_uid', session.user.id);
      localStorage.setItem('arqon_current_name', data.player_name);
      window.location.reload();
    } catch (error) {
      if (errorDiv) {
        errorDiv.textContent = error.message || 'Не удалось войти.';
        errorDiv.classList.remove('hidden');
      } else {
        alert(error.message || 'Не удалось войти.');
      }
      if (button) { button.disabled = false; button.textContent = oldText; }
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', installOrganizerUi, { once: true });
  } else {
    installOrganizerUi();
  }
})();
