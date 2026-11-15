/* ARQON admin drawer navigation */
(() => {
  const boot = () => {
    const root = document.getElementById('tab-admin');
    if (!root || root.dataset.adminDrawerReady === '1') return;
    root.dataset.adminDrawerReady = '1';

    const style = document.createElement('style');
    style.textContent = `
      #arqon-admin-menu-bar{position:sticky;top:78px;z-index:18;display:flex;justify-content:flex-start;padding:10px 0 12px}
      #arqon-admin-menu-trigger{display:inline-flex;align-items:center;gap:10px;min-height:43px;padding:0 16px;border:1px solid rgba(167,139,250,.48);border-radius:11px;background:linear-gradient(120deg,rgba(37,27,59,.98),rgba(24,18,42,.98));color:#f3eaff;font:700 13px Rajdhani,sans-serif;letter-spacing:1px;cursor:pointer;box-shadow:0 8px 24px rgba(0,0,0,.2)}
      #arqon-admin-menu-trigger svg{width:19px;height:19px;flex:0 0 auto}
      #arqon-admin-drawer-backdrop{position:fixed;inset:0;z-index:1190;background:rgba(3,2,10,.68);opacity:0;visibility:hidden;transition:opacity .2s ease,visibility .2s ease}
      #arqon-admin-drawer{position:fixed;z-index:1191;inset:0 auto 0 0;width:min(360px,88vw);padding:18px 16px 26px;background:linear-gradient(160deg,#171329,#0b0a13);border-right:1px solid rgba(167,139,250,.28);box-shadow:24px 0 70px rgba(0,0,0,.48);transform:translateX(-105%);transition:transform .24s ease;overflow-y:auto;color:#f7f3ff;font-family:Rajdhani,sans-serif}
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
      @media(max-width:600px){#arqon-admin-menu-bar{top:64px;padding:8px 0 10px}#arqon-admin-menu-trigger{min-height:41px}#arqon-admin-drawer{padding-top:max(18px,env(safe-area-inset-top));padding-bottom:max(26px,env(safe-area-inset-bottom))}}
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
    root.insertBefore(bar, root.firstElementChild);

    const backdrop = document.createElement('div');
    backdrop.id = 'arqon-admin-drawer-backdrop';
    backdrop.setAttribute('aria-hidden','true');
    const drawer = document.createElement('aside');
    drawer.id = 'arqon-admin-drawer';
    drawer.setAttribute('aria-label','Разделы панели администратора');
    drawer.innerHTML = '<div class="arqon-admin-drawer-head"><div class="arqon-admin-drawer-brand">ARQON <span>ADMIN</span></div><button id="arqon-admin-drawer-close" type="button" aria-label="Закрыть меню">×</button></div><div id="arqon-admin-drawer-items"></div><a class="arqon-admin-link support" href="/support/admin/">✦ Техподдержка · обращения игроков</a>';
    document.body.append(backdrop,drawer);

    const items = drawer.querySelector('#arqon-admin-drawer-items');

    const builderLink = document.createElement('a');
    builderLink.className = 'arqon-admin-link';
    builderLink.href = '/bracket-builder/';
    builderLink.textContent = '🎯 Конструктор турнирных сеток';
    items.appendChild(builderLink);

    const groups = [
      {name:'ТУРНИР',match:/настройки турнира|сгенерировать сетку|открыть пики|сбросить всё/i},
      {name:'ИГРОКИ И КОМАНДЫ',match:/добавить игрока|соло игроки|свободные игроки|составы и команды/i},
      {name:'КОНТЕНТ И ПАРТНЁРЫ',match:/добавить новость|добавить партнера/i},
      {name:'МАТЧИ И РЕЗУЛЬТАТЫ',match:/чат текущего матча|расписание|результаты турнира/i},
      {name:'КИБЕРСПОРТИВНАЯ ЛИГА',match:/управление турниром.*лига/i}
    ];
    const cards = Array.from(root.children).filter(el => el.classList?.contains('card'));
    const used = new Set();
    groups.forEach(group => {
      const found = cards.filter(card => {
        const heading = card.querySelector(':scope > h2, :scope > h3, :scope > .tabs-inner');
        const label = heading?.textContent?.trim() || (card.querySelector('#solo-list') ? 'Соло игроки и команды' : '');
        if (!label || !group.match.test(label)) return false;
        used.add(card);
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
        if (!card.id) card.id = 'arqon-admin-section-' + cards.indexOf(card);
        const heading = card.querySelector(':scope > h2, :scope > h3, :scope > .tabs-inner');
        const label = heading?.textContent?.trim().replace(/\s+/g,' ') || (card.querySelector('#solo-list') ? 'Составы и команды' : 'Раздел');
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
    cards.filter(card => !used.has(card)).forEach(card => {
      if (!card.id) card.id = 'arqon-admin-section-' + cards.indexOf(card);
      const link = document.createElement('a');
      link.className = 'arqon-admin-link';
      link.href = '#' + card.id;
      link.textContent = card.querySelector('h2,h3')?.textContent?.trim() || 'Дополнительный раздел';
      link.addEventListener('click',event=>{event.preventDefault();close();card.scrollIntoView({behavior:'smooth',block:'start'})});
      let section=items.querySelector('[data-admin-extra]');
      if(!section){section=document.createElement('section');section.className='arqon-admin-group';section.dataset.adminExtra='1';const title=document.createElement('div');title.className='arqon-admin-group-title';title.textContent='ДРУГОЕ';section.appendChild(title);items.appendChild(section)}
      section.appendChild(link);
    });

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
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();