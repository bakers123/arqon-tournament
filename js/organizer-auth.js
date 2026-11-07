/* ARQON organizer auth + secure player-code redemption */
(() => {
  let organizerRole = null;

  const byId = (id) => document.getElementById(id);
  const setVisible = (el, visible) => {
    if (!el) return;
    el.classList.toggle('hidden', !visible);
    el.style.display = visible ? '' : 'none';
  };

  window.isAdmin = () => ['owner', 'admin', 'editor'].includes(organizerRole);

  function installPlayerAccountUi() {
    const header = document.querySelector('header');
    if (!header || byId('player-account-widget')) return;
    const widget = document.createElement('div');
    widget.id = 'player-account-widget';
    widget.className = 'player-account-widget';
    widget.innerHTML = `
      <button class="player-match-trigger btn ghost" id="player-match-trigger" type="button">⚔ Мой матч</button>
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
      close.className = 'player-match-close';
      close.type = 'button';
      close.textContent = 'Свернуть ×';
      close.addEventListener('click', () => window.hidePlayerMatchPanel?.());
      panelHeader.querySelector('div:last-child')?.appendChild(close);
    }
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
    const nav = document.querySelector('header nav');
    if (nav && !byId('organizer-login-btn')) {
      const button = document.createElement('button');
      button.id = 'organizer-login-btn';
      button.type = 'button';
      button.textContent = 'Организатор';
      button.addEventListener('click', () => {
        const modal = byId('organizer-auth-modal');
        if (modal) modal.style.display = 'flex';
      });
      nav.appendChild(button);
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
    try {
      const { data: role, error: roleError } = await supabaseClient.rpc('current_organizer_role');
      if (roleError) throw roleError;
      organizerRole = role || null;
    } catch (error) {
      console.error('Organizer role lookup failed:', error);
      organizerRole = null;
    }

    if (window.isAdmin()) {
      const auth = byId('auth-screen');
      if (auth) auth.style.display = 'none';
      const player = byId('player-screen');
      if (player) { player.classList.add('hidden'); player.style.display = 'none'; }
      const main = document.querySelector('main');
      if (main) main.style.display = 'block';
      setVisible(byId('tab-home'), true);
      setVisible(byId('tab-admin'), true);
      setVisible(byId('tab-bracket'), false);
      const adminButton = byId('admin-tab-btn');
      if (adminButton) { adminButton.classList.remove('hidden'); adminButton.style.display = 'inline-block'; }
      if (typeof initSupabaseSync === 'function') initSupabaseSync();
      if (typeof loadLeague === 'function') loadLeague(true);
      const loginButton = byId('organizer-login-btn');
      if (loginButton) {
        const activeButton = loginButton.cloneNode(true);
        activeButton.textContent = 'Выйти из панели';
        loginButton.replaceWith(activeButton);
        activeButton.addEventListener('click', async () => {
          await supabaseClient.auth.signOut();
          window.location.reload();
        });
      }
      return;
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
      if (typeof startDraftListener === 'function') startDraftListener(uid);
      if (typeof applyPathRoute === 'function') applyPathRoute();
    } else if (typeof handleNoAuth === 'function') {
      handleNoAuth();
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
