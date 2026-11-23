/* ARQON unified navigation v2 */
(() => {
  const boot = () => {
    if (!document.querySelector('script[data-arqon-notifications]')) { const notificationScript=document.createElement('script'); notificationScript.src='/assets/arqon-notifications.js?v=3'; notificationScript.dataset.arqonNotifications='true'; document.head.appendChild(notificationScript); }
    const header = document.querySelector('body > header');
    const nav = header?.querySelector('nav');
    if (!header || !nav || header.querySelector('.arqon-menu-trigger')) return;
    const trigger = document.createElement('button');
    trigger.type = 'button';
    trigger.className = 'arqon-menu-trigger';
    trigger.setAttribute('aria-label', 'Открыть меню');
    trigger.setAttribute('aria-expanded', 'false');
    trigger.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h16"/></svg>';
    header.insertBefore(trigger, header.firstElementChild);

    const backdrop = document.createElement('div');
    backdrop.className = 'arqon-menu-backdrop';
    backdrop.setAttribute('aria-hidden','true');
    document.body.appendChild(backdrop);

    const head = document.createElement('div');
    head.className = 'arqon-nav-head';
    head.innerHTML = '<div class="arqon-nav-brand">ARQON <span>ESPORTS</span></div><button class="arqon-nav-close" type="button" aria-label="Закрыть меню">×</button>';
    nav.prepend(head);

    const buttons = Array.from(nav.querySelectorAll('button[data-tab]'));
    const groups = [
      {title:'Главное',keys:['home']},
      {title:'Соревнования',keys:['tournaments','bracket','schedule','results','league','history']},
      {title:'Сообщество',keys:['players','teams','news']},
      {title:'Партнёры и управление',keys:['partners','admin']}
    ];
    const groupRoot = document.createElement('div');
    groupRoot.className = 'arqon-nav-groups';
    const byKey = new Map(buttons.map(b => [b.dataset.tab,b]));
    groups.forEach(group => {
      const section = document.createElement('section');
      section.className = 'arqon-nav-group';
      const label = document.createElement('div');
      label.className = 'arqon-nav-group-title';
      label.textContent = group.title;
      section.appendChild(label);
      group.keys.forEach(key => { const button = byKey.get(key); if(button) section.appendChild(button); });
      groupRoot.appendChild(section);
    });
    const competitionSection = Array.from(groupRoot.querySelectorAll('.arqon-nav-group')).find(section => section.querySelector('.arqon-nav-group-title')?.textContent === 'Соревнования');
    if (competitionSection && !competitionSection.querySelector('.arqon-nav-live')) {
      const liveLink = document.createElement('a');
      liveLink.className = 'arqon-nav-support arqon-nav-live';
      liveLink.href = '/live/';
      liveLink.textContent = '◉  ARQON Live Center';
      competitionSection.appendChild(liveLink);
    }
    const communitySection = Array.from(groupRoot.querySelectorAll('.arqon-nav-group')).find(section => section.querySelector('.arqon-nav-group-title')?.textContent === 'Сообщество');
    if (communitySection && !communitySection.querySelector('.arqon-nav-support')) {
      const supportLink = document.createElement('a');
      supportLink.className = 'arqon-nav-support';
      supportLink.href = '/support/';
      supportLink.textContent = '✦  Техподдержка';
      communitySection.appendChild(supportLink);
    }
    const extraSection = document.createElement('section');
    extraSection.className = 'arqon-nav-group arqon-nav-extra';
    const extraLabel = document.createElement('div');
    extraLabel.className = 'arqon-nav-group-title';
    extraLabel.textContent = 'Дополнительно';
    extraSection.appendChild(extraLabel);
    groupRoot.appendChild(extraSection);

    // Keep utility links/buttons (updates, achievements, shop, etc.) inside
    // the drawer column instead of leaving them as stray flex children.
    const moveExtraControls = () => {
      // Dynamic utility controls (achievements, shop, etc.) may be wrapped
      // in DIVs by their own modules. Move every direct nav child except the
      // structural groups and social links into the same full-width column.
      Array.from(nav.children).forEach(node => {
        if (node === head || node === groupRoot || node.matches('.nav-social-btn')) return;
        if (node.matches('button[data-tab]')) return;
        extraSection.appendChild(node);
      });
      extraSection.hidden = extraSection.children.length === 1;
    };
    groupRoot.style.cssText = 'display:flex;flex-direction:column;align-items:stretch;width:100%;min-width:0;flex:0 0 auto';
    extraSection.style.cssText = 'display:flex;flex-direction:column;align-items:stretch;width:100%;min-width:0;flex:0 0 auto';

    nav.insertBefore(groupRoot, nav.querySelector('.nav-social-btn'));
    moveExtraControls();
    const extraControlsObserver = new MutationObserver(() => moveExtraControls());
    extraControlsObserver.observe(nav, { childList: true });

    // Expandable categories live inside the existing drawer controller.
    const makeAccordion = (section, titleNode) => {
      if (!section || !titleNode) return;
      const toggle = document.createElement('button');
      toggle.type = 'button';
      toggle.className = 'arqon-nav-group-toggle';
      toggle.setAttribute('aria-expanded','false');
      toggle.innerHTML = '<span></span><span class="arqon-nav-chevron" aria-hidden="true">⌄</span>';
      toggle.firstElementChild.textContent = titleNode.textContent;
      const content = document.createElement('div');
      content.className = 'arqon-nav-group-items';
      while (titleNode.nextSibling) content.appendChild(titleNode.nextSibling);
      content.hidden = true;
      titleNode.replaceWith(toggle);
      section.appendChild(content);
      toggle.addEventListener('click', () => {
        const expanded = content.hidden;
        content.hidden = !expanded;
        toggle.setAttribute('aria-expanded',String(expanded));
        section.classList.toggle('is-expanded',expanded);
      });
    };
    groupRoot.querySelectorAll('.arqon-nav-group').forEach(section =>
      makeAccordion(section,section.querySelector('.arqon-nav-group-title'))
    );
    makeAccordion(extraSection,extraLabel);

    const close = () => {
      nav.classList.remove('arqon-nav-open');
      backdrop.classList.remove('is-open');
      document.body.classList.remove('arqon-menu-open');
      trigger.setAttribute('aria-expanded','false');
      trigger.setAttribute('aria-label','Открыть меню');
      trigger.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h16"/></svg>';
    };
    const open = () => {
      nav.classList.add('arqon-nav-open');
      backdrop.classList.add('is-open');
      document.body.classList.add('arqon-menu-open');
      trigger.setAttribute('aria-expanded','true');
      trigger.setAttribute('aria-label','Закрыть меню');
      trigger.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h16"/></svg>';
    };
    trigger.addEventListener('click', () => nav.classList.contains('arqon-nav-open') ? close() : open());
    backdrop.addEventListener('click',close);
    const closeControl = head.querySelector('.arqon-nav-close');
    closeControl.addEventListener('click',close);
    
    nav.addEventListener('click',event => {
      const homeButton = event.target.closest('button[data-tab="home"]');
      const currentPath = window.location.pathname.replace(/\/+$/, '') || '/';
      if (homeButton && currentPath !== '/') {
        event.preventDefault();
        event.stopImmediatePropagation();
        window.location.replace('/?arqon_build=202611151930');
        return;
      }
      // Do not close the drawer during capture: page modules often handle
      // tab buttons in the bubbling phase. Closing here hides the target
      // before its action can complete, especially on desktop.
      if(event.target.closest('button[data-tab], a[href]')) {
        window.setTimeout(() => close(), 180);
      }
    }, true);
    document.addEventListener('keydown',event => { if(event.key==='Escape') close(); });
    const brand = header.querySelector('.brand');
    const logo = brand?.querySelector('img');
    if(brand && logo && brand.tagName !== 'A'){
      const link = document.createElement('a');
      link.href = '/?arqon_build=202611151930';
      link.setAttribute('aria-label','ARQON — на главную');
      link.style.cssText = 'display:flex;align-items:center';
      brand.replaceChild(link,logo);
      link.appendChild(logo);
    }
    const active = nav.querySelector('button[data-tab].active');
    if(active) active.setAttribute('aria-current','page');
  };
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
})();