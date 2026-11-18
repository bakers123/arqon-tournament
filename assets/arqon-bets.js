(() => {
'use strict';
const SUPABASE_URL='https://uscnaqcvuwjrmkjyuklp.supabase.co';
const SUPABASE_KEY='sb_publishable_oE2Bc1wPAcDt6HE8bOUj3Q_0-2FfIxB';
const db=window.arqonLiveDb || window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{storageKey:'sb-uscnaqcvuwjrmkjyuklp-auth-token',persistSession:true,autoRefreshToken:false,detectSessionInUrl:false}});
const $=id=>document.getElementById(id);
const el=(tag,cls,text)=>{const node=document.createElement(tag);if(cls)node.className=cls;if(text!==undefined)node.textContent=text;return node};
let user=null,arqonId=null,balance=null,isAdmin=false,events=[],bets=[],matches=[];
const money=n=>Number(n||0).toLocaleString('ru-RU');
const date=v=>v?new Date(v).toLocaleString('ru-RU',{dateStyle:'medium',timeStyle:'short'}):'Время не указано';
const say=(message,error=false)=>{const n=$('notice');if(n){n.textContent=message;n.className='notice show'+(error?' error':'')}};
const rpc=async(name,args)=>{const {data,error}=await db.rpc(name,args);if(error)throw error;return data};
async function init(){
 try{
  const auth=await db.auth.getUser();user=auth.data?.user||null;
  if(user){const role=await rpc('has_organizer_role',{required_role:'admin'});isAdmin=role===true;$('bets-admin').hidden=!isAdmin;
   const profile=await db.from('profiles').select('arqon_id').eq('user_id',user.id).maybeSingle();if(profile.error)throw profile.error;arqonId=profile.data?.arqon_id??null;
   if(arqonId!==null){const w=await db.from('arqon_coin_wallets').select('balance').eq('arqon_id',arqonId).maybeSingle();if(w.error)throw w.error;balance=w.data?.balance??0;}
  }
  await loadMatches();await loadAll();
  $('bet-event-form').addEventListener('submit',createEvent);
  $('bet-market-form').addEventListener('submit',createMarket);
  db.channel('arqon-bets-events').on('postgres_changes',{event:'*',schema:'public',table:'arqon_bet_events'},()=>loadAll().catch(e=>say('Ошибка обновления ставок: '+e.message,true))).on('postgres_changes',{event:'*',schema:'public',table:'arqon_bet_markets'},()=>loadAll().catch(()=>{})).on('postgres_changes',{event:'*',schema:'public',table:'arqon_bet_selections'},()=>loadAll().catch(()=>{})).subscribe();
  if(user)db.channel('arqon-bets-user').on('postgres_changes',{event:'*',schema:'public',table:'arqon_bets',filter:'user_id=eq.'+user.id},()=>loadAll().catch(()=>{})).subscribe();
 }catch(e){say('Не удалось загрузить ARQON Bets: '+e.message,true);$('bets-events').replaceChildren(el('div','empty','Не удалось загрузить ставки. Обнови страницу или сообщи администрации.'))}
}
async function loadMatches(){
 const {data,error}=await db.from('live_matches').select('id,title,team1,team2,starts_at,status').order('starts_at',{ascending:true});if(error)throw error;matches=data||[];
}
async function loadAll(){
 const [eventResult,betResult]=await Promise.all([
  db.from('arqon_bet_events').select('id,title,description,starts_at,status,live_match_id,arqon_bet_markets(id,title,market_type,min_stake,max_stake,status,winning_selection_id,arqon_bet_selections!arqon_bet_selections_market_id_fkey(id,label,selection_key,odds,pool_amount,is_active))').order('starts_at',{ascending:true}),
  user?db.from('arqon_bets').select('id,event_id,market_id,selection_id,stake,odds_locked,potential_payout,status,created_at').eq('user_id',user.id).order('created_at',{ascending:false}).limit(60):Promise.resolve({data:[],error:null})
 ]);
 if(eventResult.error)throw eventResult.error;if(betResult.error)throw betResult.error;
 events=eventResult.data||[];bets=betResult.data||[];
 if(user&&arqonId!==null){const w=await db.from('arqon_coin_wallets').select('balance').eq('arqon_id',arqonId).maybeSingle();if(w.error)throw w.error;balance=w.data?.balance??0;}
 render();
}
function render(){
 $('bets-wallet').textContent=user&&balance!==null?'◈ Баланс: '+money(balance)+' Coins':'◈ Войди в ARQON';
 renderEvents();renderHistory();if(isAdmin)renderAdmin();
}
function renderEvents(){
 const host=$('bets-events');host.replaceChildren();
 const visible=events.filter(e=>e.status!=='draft');
 if(!visible.length){host.append(el('div','empty','Пока нет событий для ставок. Администратор добавит их здесь.'));return}
 visible.forEach(event=>{
  const card=el('article','bet-event'),head=el('div','bet-event-head'),info=el('div');
  info.append(el('h3','',event.title),el('p','bet-muted',date(event.starts_at)+(event.description?' · '+event.description:'')));
  head.append(info,el('span','bet-status',event.status==='open'?(new Date(event.starts_at).getTime()>Date.now()?'Приём ставок':'Ставки закрыты по времени'):event.status==='closed'?'Закрыто':event.status==='settled'?'Рассчитано':'Отменено'));card.append(head);
  (event.arqon_bet_markets||[]).forEach(market=>{
   const box=el('section','bet-market');box.append(el('h4','',market.title+' · '+(market.status==='open'?'ОТКРЫТ':market.status==='settled'?'РАССЧИТАН':'ЗАКРЫТ')));
   const selections=(market.arqon_bet_selections||[]).filter(s=>s.is_active!==false);
   if(market.status==='settled'&&market.winning_selection_id){const win=selections.find(s=>s.id===market.winning_selection_id);box.append(el('p','bet-muted','Результат: '+(win?.label||'—')))}
   const outcomes=el('div','bet-outcomes'),choice=document.createElement('select');choice.setAttribute('aria-label','Выбери исход');
   selections.forEach((s,index)=>{
    choice.add(new Option(s.label+' · '+Number(s.odds).toFixed(2),s.id));
    const button=el('button','bet-outcome');button.type='button';button.append(el('span','',s.label),el('strong','',Number(s.odds).toFixed(2)));
    if(index===0)button.classList.add('selected');
    button.addEventListener('click',()=>{choice.value=s.id;outcomes.querySelectorAll('.bet-outcome').forEach(x=>x.classList.remove('selected'));button.classList.add('selected');updatePotential()});
    outcomes.append(button);
   });
   box.append(outcomes);
   const canBet=market.status==='open'&&event.status==='open'&&new Date(event.starts_at).getTime()>Date.now();
   if(canBet&&selections.length>=2){
    const form=el('form','bet-form'),selectLabel=el('label','field'),stakeLabel=el('label','field'),stake=document.createElement('input');
    selectLabel.append(el('span','bet-muted','Исход'),choice);
    stake.type='number';stake.min=String(market.min_stake);stake.max=String(market.max_stake);stake.step='1';stake.value=String(market.min_stake);stake.required=true;
    stakeLabel.append(el('span','bet-muted','Ставка · '+market.min_stake+'–'+market.max_stake+' Coins'),stake);
    const potential=el('div','field');potential.append(el('span','bet-muted','Возможный возврат'),el('strong','','—'));
    const potentialValue=potential.querySelector('strong'),submit=el('button','btn','Поставить Coins');submit.type='submit';submit.disabled=!user||arqonId===null;
    function updatePotential(){const selected=selections.find(s=>s.id===choice.value);const amount=Number(stake.value);potentialValue.textContent=selected&&Number.isSafeInteger(amount)&&amount>0?'◈ '+money(Math.floor(amount*Number(selected.odds)))+' Coins':'—'}
    choice.addEventListener('change',()=>{outcomes.querySelectorAll('.bet-outcome').forEach((b,i)=>b.classList.toggle('selected',selections[i]?.id===choice.value));updatePotential()});stake.addEventListener('input',updatePotential);updatePotential();
    form.append(selectLabel,stakeLabel,potential,submit);
    form.addEventListener('submit',async e=>{e.preventDefault();if(!user){say('Войди в ARQON, чтобы делать ставки.',true);return}const amount=Number(stake.value);if(!Number.isSafeInteger(amount)||amount<market.min_stake||amount>market.max_stake){say('Ставка должна соответствовать лимитам рынка.',true);return}submit.disabled=true;try{const result=await rpc('place_arqon_bet',{p_selection_id:choice.value,p_stake:amount});say('Ставка принята: '+amount+' Coins × '+Number(result.odds).toFixed(2)+'. Возможный возврат — '+money(result.potential_payout)+' Coins.');await loadAll()}catch(err){say('Ставка не принята: '+err.message,true);submit.disabled=false}});
    if(!user){const login=el('a','chat-login','Войди в аккаунт ARQON, чтобы поставить Coins →');login.href='/players/';box.append(login)}
    else if(arqonId===null)box.append(el('p','bet-muted','Для ставок нужен профиль ARQON с привязанным ARQON ID.'));
    box.append(form);
   }else if(market.status==='open'&&event.status==='open')box.append(el('p','bet-muted','Приём ставок закрыт: событие уже началось.'));
   bets.filter(b=>b.market_id===market.id).forEach(b=>{const s=selections.find(x=>x.id===b.selection_id);box.append(el('p','bet-muted','Твоя ставка: '+(s?.label||'исход')+' · '+b.stake+' × '+Number(b.odds_locked).toFixed(2)+' · '+statusLabel(b.status)))});
   card.append(box);
  });
  if(isAdmin&&event.status==='open'){const close=el('button','btn secondary','Закрыть все ставки события');close.type='button';close.style.marginTop='10px';close.addEventListener('click',async()=>{if(!confirm('Закрыть приём ставок по событию?'))return;try{await rpc('close_arqon_bet_event',{p_event_id:event.id});say('Приём ставок закрыт.');await loadAll()}catch(e){say(e.message,true)}});card.append(close)}
  host.append(card);
 });
}
function statusLabel(status){return status==='pending'?'Ожидает результата':status==='won'?'Выиграла':status==='void'?'Возвращена':'Проиграла'}
function renderHistory(){
 const host=$('bets-history');host.replaceChildren();
 if(!user){host.append(el('p','bet-muted','Войди в ARQON, чтобы видеть историю ставок.'));return}
 if(!bets.length){host.append(el('p','bet-muted','Ты пока не делал ставок.'));return}
 bets.forEach(b=>{const event=events.find(x=>x.id===b.event_id),market=event?.arqon_bet_markets?.find(x=>x.id===b.market_id),selection=market?.arqon_bet_selections?.find(x=>x.id===b.selection_id),row=el('div','bet-history-row');row.append(el('span','',(event?.title||'Событие')+' · '+(market?.title||'Рынок')+' · '+(selection?.label||'Исход')),el('strong','',b.stake+' × '+Number(b.odds_locked).toFixed(2)+' · '+statusLabel(b.status)+(b.status==='won'?' · +'+money(b.potential_payout)+' Coins':'')));host.append(row)});
}
function renderAdmin(){
 const matchSelect=$('bet-event-match'),marketEvent=$('bet-market-event'),oldMatch=matchSelect.value,oldEvent=marketEvent.value;
 matchSelect.replaceChildren(new Option('Без привязки — результат вручную',''));matches.filter(m=>m.status==='scheduled'&&m.starts_at&&new Date(m.starts_at).getTime()>Date.now()).forEach(m=>matchSelect.add(new Option(m.title+' · '+m.team1+' vs '+m.team2,m.id)));if(matches.some(m=>m.id===oldMatch))matchSelect.value=oldMatch;
 marketEvent.replaceChildren();events.filter(e=>e.status==='open'&&new Date(e.starts_at).getTime()>Date.now()).forEach(e=>marketEvent.add(new Option(e.title, e.id)));if(events.some(e=>e.id===oldEvent))marketEvent.value=oldEvent;
 const host=$('bets-admin-list');host.replaceChildren();
 if(!events.length){host.append(el('p','bet-muted','Событий пока нет.'));return}
 events.forEach(event=>{
  const item=el('article','bet-event');item.append(el('h3','',event.title+' · '+event.status+' · '+date(event.starts_at)));
  (event.arqon_bet_markets||[]).forEach(market=>{
   const section=el('div','bet-market');section.append(el('h4','',market.title+' · '+market.status));
   (market.arqon_bet_selections||[]).forEach(s=>{
    const row=el('div','bet-admin-selection'),label=el('span','bet-muted',s.label+' · пул '+money(s.pool_amount)),input=document.createElement('input'),save=el('button','btn secondary','Сохранить кэф');
    input.type='number';input.min='1.01';input.max='100';input.step='.001';input.value=Number(s.odds).toFixed(2);
    save.type='button';save.addEventListener('click',async()=>{save.disabled=true;try{await rpc('update_arqon_bet_odds',{p_selection_id:s.id,p_odds:Number(input.value)});say('Коэффициент обновлён.');await loadAll()}catch(e){say('Не удалось обновить кэф: '+e.message,true);save.disabled=false}});
    row.append(label,input,save);section.append(row);
   });
   if(['open','closed','settled'].includes(market.status)){
    const actions=el('div','bet-admin-actions'),winner=document.createElement('select');winner.add(new Option('Выбери выигравший исход',''));(market.arqon_bet_selections||[]).forEach(s=>winner.add(new Option(s.label,s.id)));
    if(market.status==='settled'&&market.winning_selection_id)winner.value=market.winning_selection_id;
    if(market.status==='settled'){
     const correct=el('button','btn secondary','Исправить результат');correct.type='button';
     correct.addEventListener('click',async()=>{if(!winner.value){say('Выбери правильный исход.',true);return}if(!confirm('Исправить результат? Система пересчитает выплаты. Если игрок уже потратил выигрыш, операция будет безопасно отклонена.'))return;try{await rpc('correct_arqon_bet_market_result',{p_market_id:market.id,p_winning_selection_id:winner.value});say('Результат исправлен, балансы и ставки пересчитаны.');await loadAll()}catch(e){say('Не удалось исправить результат: '+e.message,true)}});
     actions.append(winner,correct);
    }else{
     const settle=el('button','btn','Рассчитать рынок'),voidBtn=el('button','btn secondary','Отменить и вернуть ставки'),auto=el('button','btn secondary','Автопересчитать кэфы');
     settle.type=voidBtn.type=auto.type='button';
     settle.addEventListener('click',async()=>{if(!winner.value){say('Выбери выигравший исход.',true);return}if(!confirm('Рассчитать рынок и начислить выигрыши?'))return;try{await rpc('settle_arqon_bet_market',{p_market_id:market.id,p_winning_selection_id:winner.value});say('Рынок рассчитан, выигрыши начислены.');await loadAll()}catch(e){say('Ошибка расчёта: '+e.message,true)}});
     voidBtn.addEventListener('click',async()=>{if(!confirm('Отменить рынок и вернуть ставки игрокам?'))return;try{await rpc('void_arqon_bet_market',{p_market_id:market.id});say('Рынок отменён, ставки возвращены.');await loadAll()}catch(e){say('Ошибка возврата: '+e.message,true)}});
     auto.addEventListener('click',async()=>{try{await rpc('recalculate_arqon_bet_odds',{p_market_id:market.id});say('Коэффициенты пересчитаны по распределению ставок.');await loadAll()}catch(e){say('Автопересчёт не выполнен: '+e.message,true)}});
     actions.append(winner,settle,voidBtn,auto);
    }
    section.append(actions);
   }
   item.append(section);
  });
  host.append(item);
 });
}
async function createEvent(e){
 e.preventDefault();const button=$('bet-event-create');button.disabled=true;
 try{const start=new Date($('bet-event-start').value);if(Number.isNaN(start.getTime()))throw new Error('Укажи дату и время начала');await rpc('create_arqon_bet_event',{p_title:$('bet-event-title').value.trim(),p_description:$('bet-event-description').value.trim(),p_starts_at:start.toISOString(),p_live_match_id:$('bet-event-match').value||null});$('bet-event-form').reset();say('Событие для ставок создано.');await loadAll()}
 catch(err){say('Не удалось создать событие: '+err.message,true)}finally{button.disabled=false}
}
async function createMarket(e){
 e.preventDefault();const button=$('bet-market-create');button.disabled=true;
 try{
  const lines=$('bet-market-options').value.split('\n').map(x=>x.trim()).filter(Boolean);
  const selections=lines.map(line=>{const parts=line.split('|').map(x=>x.trim());if(parts.length!==3)throw new Error('Формат строки: Название | коэффициент | ключ');return {label:parts[0],odds:Number(parts[1]),key:parts[2]}});
  if(selections.length<2)throw new Error('Добавь минимум два исхода');
  await rpc('create_arqon_bet_market',{p_event_id:$('bet-market-event').value,p_title:$('bet-market-title').value.trim(),p_market_type:$('bet-market-type').value,p_min_stake:Number($('bet-market-min').value),p_max_stake:Number($('bet-market-max').value),p_selections:selections});
  $('bet-market-title').value='';$('bet-market-options').value='';say('Рынок и коэффициенты созданы.');await loadAll();
 }catch(err){say('Не удалось создать рынок: '+err.message,true)}finally{button.disabled=false}
}
if($('arqon-bets-panel'))init();
})();