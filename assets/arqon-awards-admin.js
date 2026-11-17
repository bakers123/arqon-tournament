/* ARQON permanent award management — organizer-only UI, enforced again by RLS */
(() => {
  const $ = id => document.getElementById(id);
  const catalog = {
    founder: {name:'Основатель ARQON',description:'Почётная награда за вклад в создание ARQON.',icon:'🏛',rarity:'legendary'},
    community: {name:'Амбассадор ARQON',description:'За заметный вклад в развитие сообщества ARQON.',icon:'💜',rarity:'epic'},
    event_mvp: {name:'MVP события',description:'За выдающееся выступление на специальном событии ARQON.',icon:'⭐',rarity:'rare'},
    champion: {name:'Чемпион ARQON',description:'За победу в особом турнире или соревновании ARQON.',icon:'🏆',rarity:'epic'},
    fair_play: {name:'Fair Play',description:'За честную игру и уважение к соперникам.',icon:'🤝',rarity:'rare'},
    legend: {name:'Легенда ARQON',description:'Особое признание за выдающийся вклад в историю ARQON.',icon:'👑',rarity:'legendary'}
  };
  const rarityLabel = {common:'Обычная',rare:'Редкая',epic:'Эпическая',legendary:'Легендарная'};
  let selectedPlayer = null;
  let currentAwards = [];

  function client(){ return window.supabaseClient || (typeof supabaseClient!=='undefined'?supabaseClient:null); }
  function admin(){ return typeof window.isAdmin==='function' && window.isAdmin(); }
  function say(message,error=false){const node=$('award-admin-message');if(node){node.textContent=message;node.style.color=error?'#fca5a5':'#c4b5fd';}}
  function formatDate(value){return value?new Date(value).toLocaleString('ru-RU',{dateStyle:'medium',timeStyle:'short'}):'Дата не указана';}

  async function loadHistory(){
    if(!selectedPlayer||!admin())return;
    const host=$('award-admin-history');host.replaceChildren();
    const {data,error}=await client().from('arqon_player_awards')
      .select('id,award_key,award_name,award_description,award_icon,rarity,reason,granted_at,revoked_at,revoke_reason')
      .eq('arqon_id',selectedPlayer.arqon_id).order('granted_at',{ascending:false});
    if(error){say('Не удалось загрузить историю: '+error.message,true);return}
    currentAwards=data||[];
    if(!currentAwards.length){const empty=document.createElement('p');empty.className='hint';empty.textContent='У игрока пока нет особых наград.';host.append(empty);return}
    currentAwards.forEach(award=>{
      const row=document.createElement('div');row.className='history-item';
      const info=document.createElement('div');info.className='history-event';
      const title=document.createElement('strong');title.textContent=(award.award_icon||'🏅')+' '+award.award_name;
      const detail=document.createElement('small');detail.textContent=(rarityLabel[award.rarity]||award.rarity)+' · выдана '+formatDate(award.granted_at)+' · '+award.reason;
      info.append(title,detail);
      if(award.revoked_at){const revoked=document.createElement('small');revoked.textContent='Отозвана '+formatDate(award.revoked_at)+(award.revoke_reason?' · '+award.revoke_reason:'');revoked.style.color='#fca5a5';info.append(revoked)}
      row.append(info);
      if(!award.revoked_at){
        const revoke=document.createElement('button');revoke.type='button';revoke.className='btn ghost';revoke.textContent='Отозвать';
        revoke.addEventListener('click',()=>revokeAward(award,revoke));row.append(revoke);
      }else{
        const badge=document.createElement('span');badge.className='hint';badge.textContent='Отозвана';row.append(badge);
      }
      host.append(row);
    });
  }

  async function findPlayer(){
    if(!admin()){say('Недостаточно прав.',true);return}
    const raw=$('award-player-id').value.trim(),id=Number(raw);
    if(!Number.isSafeInteger(id)||id<1){say('Введи корректный ARQON ID.',true);return}
    const button=$('award-player-find');button.disabled=true;say('Ищем игрока…');
    const {data:rows,error}=await client().rpc('get_award_recipient',{p_arqon_id:id});
    const data=rows?.[0]||null;
    button.disabled=false;
    if(error){selectedPlayer=null;$('award-grant-fields').classList.add('hidden');$('award-player-result').textContent='Ошибка поиска: '+error.message;say('Не удалось найти игрока.',true);return}
    if(!data){selectedPlayer=null;$('award-grant-fields').classList.add('hidden');$('award-player-result').textContent='Игрок с таким ARQON ID не найден.';$('award-admin-history').replaceChildren();say('');return}
    selectedPlayer=data;
    $('award-player-result').textContent='Выбран игрок: '+(data.display_name||data.steam_persona_name||'Игрок')+' · ARQON ID #'+data.arqon_id;
    $('award-grant-fields').classList.remove('hidden');say('Игрок найден. Можно выдать награду.');
    await loadHistory();
  }

  async function grantAward(){
    if(!admin()||!selectedPlayer){say('Сначала найди игрока.',true);return}
    const key=$('award-type').value,item=catalog[key],reason=$('award-reason').value.trim();
    if(!item){say('Выбери награду.',true);return}
    if(reason.length<3||reason.length>300){say('Укажи причину от 3 до 300 символов.',true);return}
    const {data:auth}=await client().auth.getUser();
    if(!auth?.user){say('Сессия организатора не найдена. Войди заново.',true);return}
    const button=$('award-grant');button.disabled=true;say('Выдаём награду…');
    const {error}=await client().from('arqon_player_awards').insert({
      arqon_id:selectedPlayer.arqon_id,award_key:key,award_name:item.name,
      award_description:item.description,award_icon:item.icon,rarity:item.rarity,
      reason,granted_by:auth.user.id
    });
    button.disabled=false;
    if(error){say(error.code==='23505'?'У игрока уже есть такая активная награда.':error.message||'Не удалось выдать награду.',true);return}
    $('award-reason').value='';say('Награда выдана и сохранена в коллекции игрока.');
    await loadHistory();
  }

  async function revokeAward(award,button){
    if(!admin())return;
    const reason=window.prompt('Почему отзываем награду? (необязательно)','');
    if(reason===null)return;
    const {data:auth}=await client().auth.getUser();
    if(!auth?.user){say('Сессия организатора не найдена.',true);return}
    button.disabled=true;
    const {error}=await client().from('arqon_player_awards').update({
      revoked_at:new Date().toISOString(),revoked_by:auth.user.id,revoke_reason:reason.trim().slice(0,300)||null
    }).eq('id',award.id).is('revoked_at',null);
    if(error){button.disabled=false;say(error.message||'Не удалось отозвать награду.',true);return}
    say('Награда отозвана. Запись сохранена в истории.');
    await loadHistory();
  }

  let coverProfiles = [];
  let coverPreviewUrl = null;
  function coverSay(message,error=false){
    const node=$('admin-cover-status');
    if(node){node.textContent=message;node.style.color=error?'#fca5a5':'#c4b5fd'}
  }
  function selectedCoverProfile(){
    const id=$('admin-cover-player')?.value;
    return coverProfiles.find(profile=>profile.user_id===id)||null;
  }
  async function loadCoverProfiles(){
    if(!admin()){coverSay('Недостаточно прав.',true);return}
    const select=$('admin-cover-player'),button=$('admin-cover-refresh');
    if(!select)return;
    if(button)button.disabled=true;
    select.disabled=true;
    coverSay('Загружаем игроков…');
    const {data,error}=await client().functions.invoke('manage-arqon-accounts',{body:{action:'list_steam_profiles'}});
    if(button)button.disabled=false;
    select.disabled=false;
    if(error||!Array.isArray(data?.profiles)){
      coverProfiles=[];
      select.replaceChildren(new Option('Не удалось загрузить игроков',''));
      coverSay(error?.message||data?.error||'Не удалось получить список профилей.',true);
      return;
    }
    coverProfiles=data.profiles;
    const previous=select.value;
    select.replaceChildren(new Option('Выбери игрока',''));
    coverProfiles.forEach(profile=>{
      const label=(profile.display_name||profile.steam_persona_name||profile.game_nick||'Игрок')+
        ' · ARQON #'+(profile.arqon_id??'—')+(profile.game_nick&&profile.game_nick!==profile.display_name?' · '+profile.game_nick:'');
      select.add(new Option(label,profile.user_id));
    });
    if(coverProfiles.some(profile=>profile.user_id===previous))select.value=previous;
    coverSay('Игроков в списке: '+coverProfiles.length+'.');
  }
  async function fileToBase64(file){
    const bytes=new Uint8Array(await file.arrayBuffer());
    let binary='';
    const chunkSize=0x8000;
    for(let offset=0;offset<bytes.length;offset+=chunkSize){
      binary+=String.fromCharCode(...bytes.subarray(offset,Math.min(offset+chunkSize,bytes.length)));
    }
    return btoa(binary);
  }
  async function uploadAdminPlayerCover(){
    if(!admin()){coverSay('Недостаточно прав.',true);return}
    const profile=selectedCoverProfile(),file=$('admin-cover-file')?.files?.[0],button=$('admin-cover-upload');
    if(!profile){coverSay('Сначала выбери игрока.',true);return}
    if(!file){coverSay('Выбери файл обложки.',true);return}
    const allowed=['image/gif','image/jpeg','image/png','image/webp'];
    if(!allowed.includes(file.type)){coverSay('Поддерживаются GIF, JPG, PNG и WEBP.',true);return}
    if(file.size>5*1024*1024){coverSay('Файл больше 5 МБ. Максимум — 5 МБ.',true);return}
    button.disabled=true;coverSay('Подготавливаем исходный файл…');
    try{
      const base64=await fileToBase64(file);
      const uploaded=await client().functions.invoke('manage-arqon-accounts',{body:{
        action:'upload_steam_profile_media',user_id:profile.user_id,kind:'cover',mime:file.type,base64
      }});
      if(uploaded.error||!uploaded.data?.url)throw new Error(uploaded.data?.error||uploaded.error?.message||'Не удалось загрузить файл в хранилище.');
      const p={
        display_name:profile.display_name||profile.steam_persona_name||profile.game_nick||'Игрок',
        game_nick:profile.game_nick||null,bio:profile.bio||'',
        cs2_faceit_elo:profile.cs2_faceit_elo??null,cs2_faceit_url:profile.cs2_faceit_url||null,
        dota2_mmr:profile.dota2_mmr??null,dota2_profile_url:profile.dota2_profile_url||null,
        avatar_url:profile.avatar_url||null,cover_url:uploaded.data.url,
        is_public:profile.is_public===true,show_steam:profile.show_steam===true,
        looking_for_team:profile.looking_for_team===true,preferred_role:profile.preferred_role||''
      };
      const saved=await client().functions.invoke('manage-arqon-accounts',{body:{
        action:'update_steam_profile',user_id:profile.user_id,profile:p
      }});
      if(saved.error||!saved.data?.ok)throw new Error(saved.data?.error||saved.error?.message||'Файл загружен, но не удалось сохранить обложку профиля.');
      profile.cover_url=uploaded.data.url;
      $('admin-cover-file').value='';
      coverSay(file.type==='image/gif'?'GIF-обложка установлена. Анимация сохранена.':'Обложка игрока успешно обновлена.');
    }catch(error){
      coverSay(error?.message||'Не удалось сохранить обложку.',true);
    }finally{button.disabled=false}
  }
  function previewAdminCover(){
    const file=$('admin-cover-file')?.files?.[0],wrap=$('admin-cover-preview-wrap'),img=$('admin-cover-preview');
    if(coverPreviewUrl){URL.revokeObjectURL(coverPreviewUrl);coverPreviewUrl=null}
    if(!file){wrap?.classList.add('hidden');if(img)img.removeAttribute('src');return}
    coverPreviewUrl=URL.createObjectURL(file);
    img.src=coverPreviewUrl;wrap.classList.remove('hidden');
  }

  function boot(){
    if(!$('arqon-awards-admin'))return;
    $('award-player-find')?.addEventListener('click',findPlayer);
    $('admin-cover-refresh')?.addEventListener('click',loadCoverProfiles);
    $('admin-cover-upload')?.addEventListener('click',uploadAdminPlayerCover);
    $('admin-cover-file')?.addEventListener('change',previewAdminCover);
    $('admin-cover-player')?.addEventListener('focus',()=>{if(!coverProfiles.length)loadCoverProfiles()});
    loadCoverProfiles();
    $('award-grant')?.addEventListener('click',grantAward);
    $('award-player-id')?.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();findPlayer()}});
    const section=$('tab-admin');
    if(section&&window.MutationObserver)new MutationObserver(()=>{if(!admin())return}).observe(section,{attributes:true,attributeFilter:['class','style']});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
