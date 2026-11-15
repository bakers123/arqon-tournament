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
