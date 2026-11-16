/* ARQON admin drawer navigation */
(() => {
  const boot = () => {
    const root = document.getElementById('tab-admin');
    if (!root || root.dataset.adminDrawerReady === '1') return;
    root.dataset.adminDrawerReady = '1';

    const style = document.createElement('style');
    style.textContent = `
      #arqon-admin-menu-bar{position:sticky;top:76px;z-index:1600;isolation:isolate;display:flex;justify-content:flex-start;align-items:center;width:100%;margin:0 0 14px;padding:8px 0 10px;pointer-events:auto;background:linear-gradient(180deg,rgba(9,8,15,.96),rgba(9,8,15,.72));backdrop-filter:blur(12px)}
      #arqon-admin-menu-trigger{display:inline-flex;align-items:center;gap:10px;min-height:43px;padding:0 16px;border:1px solid rgba(167,139,250,.48);border-radius:11px;background:linear-gradient(120deg,rgba(37,27,59,.98),rgba(24,18,42,.98));color:#f3eaff;font:700 13px Rajdhani,sans-serif;letter-spacing:1px;cursor:pointer;box-shadow:0 8px 24px rgba(0,0,0,.2)}
      #arqon-admin-menu-trigger svg{width:19px;height:19px;flex:0 0 auto}
      #arqon-admin-drawer-backdrop{position:fixed;inset:0;z-index:20000;background:rgba(3,2,10,.68);opacity:0;visibility:hidden;transition:opacity .2s ease,visibility .2s ease}
      #arqon-admin-drawer{position:fixed;z-index:20001;top:0;left:0;right:auto;bottom:0;width:min(400px,calc(100vw - 24px));max-width:calc(100vw - 24px);height:100vh;height:100dvh;max-height:100vh;max-height:100dvh;box-sizing:border-box;padding:18px 16px max(26px,env(safe-area-inset-bottom));padding-top:max(18px,env(safe-area-inset-top));background:linear-gradient(160deg,#171329,#0b0a13);border-right:1px solid rgba(167,139,250,.28);box-shadow:24px 0 70px rgba(0,0,0,.48);transform:translate3d(calc(-100% - 12px),0,0);transition:transform .24s ease;overflow-y:auto;overflow-x:hidden;overscroll-behavior:contain;color:#f7f3ff;font-family:Rajdhani,sans-serif}
      #arqon-admin-drawer.is-open{transform:translateX(0)}
      #arqon-admin-drawer-backdrop.is-open{opacity:1;visibility:visible}
      .arqon-admin-drawer-head{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:4px 3px 17px;border-bottom:1px solid rgba(173,132,255,.18);margin-bottom:14px}
      .arqon-admin-drawer-brand{font:800 13px Orbitron,sans-serif;letter-spacing:1.2px}.arqon-admin-drawer-brand span{color:#a78bfa}
      #arqon-admin-drawer-close{display:inline-flex;align-items:center;justify-content:center;flex:0 0 38px;width:38px;height:38px;min-width:38px;min-height:38px;padding:0;line-height:1;font:400 25px/1 Arial,sans-serif;text-align:center;box-sizing:border-box;border:1px solid rgba(167,139,250,.3);border-radius:10px;background:#211a32;color:white;cursor:pointer}
      .arqon-admin-group{margin:14px 0}.arqon-admin-group-title{font:700 10px Orbitron,sans-serif;letter-spacing:1.5px;color:#9d91b6;padding:0 9px 7px}
      .arqon-admin-link{display:flex;align-items:center;gap:10px;width:100%;min-height:42px;padding:9px 11px;margin:3px 0;border:1px solid transparent;border-radius:9px;background:transparent;color:#e9e0f8;text-decoration:none;text-align:left;font:700 14px Rajdhani,sans-serif;cursor:pointer}
      .arqon-admin-link:hover,.arqon-admin-link:focus-visible{background:rgba(139,92,246,.13);border-color:rgba(167,139,250,.24);outline:none}
      .arqon-admin-link.support{margin-top:14px;background:rgba(139,92,246,.14);border-color:rgba(167,139,250,.3);color:#dfceff}
      body.arqon-admin-drawer-open{overflow:hidden}
      #media(max-width:600px){#arqon-admin-menu-bar{top:64px;padding:7px 0 9px;margin-bottom:10px}#arqon-admin-menu-trigger{min-height:41px}#arqon-admin-drawer{padding-top:max(18px,env(safe-area-inset-top));padding-bottom:max(26px,env(safe-area-inset-bottom))}}
      @media(prefers-reduced-motion:reduce){#arqon-admin-drawer,#arqon-admin-drawer-backdrop{transition:none}}
    `;
    document.head.appendChild(style);

    const bar = document.createElement('div');
    bar.id = 'arqon-admin-menu-bar';
    const trigger = document.createElement('button');
    trigger.id = 'arqon-admin-menu-trigger';
    trigger.type = 'button';
    trigger.setAttribute('aria-expanded','false');
    trigger.setAttribute('aria-controls','arqon-admin-drawer');
    trigger.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h16"/></svg><span>МЕНЮ АДМИНКИ</span>';
    bar.appendChild(trigger);
    const adminMain = root.closest('main') || root.parentElement;
    if (adminMain) adminMain.insertBefore(bar, root); else root.insertBefore(bar, root.firstElementChild);

    const backdrop = document.createElement('div');
    backdrop.id = 'arqon-admin-drawer-backdrop';
    backdrop.setAttribute('aria-hidden','true');
    const drawer = document.createElement('aside');
    drawer.id = 'arqon-admin-drawer';
    drawer.setAttribute('aria-label','Разделы панели администратора');
    drawer.innerHTML = '<div class="arqon-admin-drawer-head"><div class="arqon-admin-drawer-brand">ARQON <span>ADMIN</span></div><button id="arqon-admin-drawer-close" type="button" aria-label="Закрыть меню">×</button></div><div id="arqon-admin-drawer-items"></div><a class="arqon-admin-link" href="/live/">◉ ARQON Live Center</a><a class="arqon-admin-link support" href="/support/admin/">✦ Техподдержка · обращения игроков</a>';
    document.body.append(backdrop,drawer);

    const items = drawer.querySelector('#arqon-admin-drawer-items');

    const builderLink = document.createElement('a');
    builderLink.className = 'arqon-admin-link';
    builderLink.href = '/bracket-builder/';
    builderLink.textContent = '🎯 Конструктор турнирных сеток';
    items.appendChild(builderLink);

    const groups = [
      {name:'УПРАВЛЕНИЕ И ДОСТУПЫ',match:/управление аккаунтами|доступ к служебному входу|права организаторов|роли|безопасност/i},
      {name:'ТУРНИР И СЕТКИ',match:/настройки турнира|сгенерировать сетку|открыть пики|сбросить всё|турнирная сетка|конструктор турнирных сеток/i},
      {name:'ИГРОКИ, НАГРАДЫ И COINS',match:/выдача arqon coins|награды игроков|эксклюзивы профиля|добавить игрока|соло игроки|свободные игроки|составы и команды|редактирование steam|игроки|команды/i},
      {name:'МАТЧИ И РЕЗУЛЬТАТЫ',match:/чат текущего матча|расписание|результаты турнира|добавить матч|добавить результаты|матчи/i},
      {name:'КИБЕРСПОРТИВНАЯ ЛИГА',match:/управление турниром.*лига|киберспортивная лига|лига/i},
      {name:'КОНТЕНТ И ПАРТНЁРЫ',match:/добавить новость|добавить партнера|новости|партнер|эксклюзивы профиля|достижени|магазин/i},
      {name:'ПРОЧИЕ ИНСТРУМЕНТЫ',match:/.*/i}
    ];
    function rebuildAdminMenu() {
      const cards = Array.from(root.children).filter(el => el.classList?.contains('card') && !el.hidden && getComputedStyle(el).display !== 'none');
      items.querySelectorAll('.arqon-admin-group').forEach(el => el.remove());
      const used = new Set();
      groups.forEach((group,index) => {
        const found = cards.filter(card => {
          if (used.has(card)) return false;
          const heading = card.querySelector(':scope > h2, :scope > h3, :scope > .tabs-inner');
          const label = heading?.textContent?.trim() || (card.querySelector('#solo-list') ? 'Соло игроки и команды' : '');
          if (!label || !group.match.test(label)) return false;
          if (index === groups.length - 1 && groups.slice(0,-1).some(g=>g.match.test(label))) return false;
          return true;
        });
        if (!found.length) return;
        const section = document.createElement('section');
        section.className = 'arqon-admin-group';
        const title = document.createElement('div');
        title.className = 'arqon-admin-group-title';
        title.textContent = group.name;
        section.appendChild(title);
        found.forEach(card => {
          used.add(card);
          if (!card.id) card.id = 'arqon-admin-section-' + cards.indexOf(card);
          const heading = card.querySelector(':scope > h2, :scope > h3, :scope > .tabs-inner');
          const label = heading?.textContent?.trim().replace(/\\s+/g,' ') || (card.querySelector('#solo-list') ? 'Составы и команды' : 'Раздел');
          const link = document.createElement('a');
          link.className = 'arqon-admin-link';
          link.href = '#' + card.id;
          link.textContent = label.length > 48 ? label.slice(0,45) + '…' : label;
          link.addEventListener('click',event => {
            event.preventDefault();
            close();
            card.scrollIntoView({behavior:window.matchMedia('(prefers-reduced-motion: reduce)').matches?'auto':'smooth',block:'start'});
          });
          section.appendChild(link);
        });
        items.appendChild(section);
      });
    }
    rebuildAdminMenu();
    const menuObserver = new MutationObserver(() => rebuildAdminMenu());
    menuObserver.observe(root,{childList:true,subtree:true,attributes:true,attributeFilter:['class','hidden','style']});
    const open = () => {
      if (!window.isAdmin?.()) return;
      drawer.classList.add('is-open');backdrop.classList.add('is-open');document.body.classList.add('arqon-admin-drawer-open');
      trigger.setAttribute('aria-expanded','true');drawer.querySelector('#arqon-admin-drawer-close').focus();
    };
    function close(){
      drawer.classList.remove('is-open');backdrop.classList.remove('is-open');document.body.classList.remove('arqon-admin-drawer-open');
      trigger.setAttribute('aria-expanded','false');
    }
    trigger.addEventListener('click',()=>drawer.classList.contains('is-open')?close():open());
    backdrop.addEventListener('click',close);
    drawer.querySelector('#arqon-admin-drawer-close').addEventListener('click',close);
    document.addEventListener('keydown',event=>{if(event.key==='Escape')close()});
    const syncVisibility=()=>{
      const allowed=!!window.isAdmin?.()&&!root.classList.contains('hidden')&&getComputedStyle(root).display!=='none';
      bar.style.display=allowed?'flex':'none';
      if(!allowed)close();
    };
    new MutationObserver(syncVisibility).observe(root,{attributes:true,attributeFilter:['class','style']});
    syncVisibility();
    window.addEventListener('resize',syncVisibility);
    window.addEventListener('arqon:organizer-role-ready',syncVisibility);
    window.addEventListener('pageshow',syncVisibility);
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();