/* ARQON unified navigation v1 */
(() => {
  const boot = () => {
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
    nav.insertBefore(groupRoot, nav.querySelector('.nav-social-btn'));

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
      if(event.target.closest('button[data-tab]')) close();
    });
    document.addEventListener('keydown',event => { if(event.key==='Escape') close(); });
    const brand = header.querySelector('.brand');
    const logo = brand?.querySelector('img');
    if(brand && logo && brand.tagName !== 'A'){
      const link = document.createElement('a');
      link.href = '/';
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