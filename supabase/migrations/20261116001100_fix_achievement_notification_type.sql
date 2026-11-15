-- Keep the notification type aligned with the existing notification enum/check.
create or replace function public.award_arqon_achievement_coins()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_reward bigint; v_awarded boolean; v_user_id uuid;
begin
  v_reward := case new.achievement_key
    when 'tournament_first' then 20 when 'tournament_podium' then 30
    when 'tournament_champion' then 60 when 'tournament_mvp' then 50
    when 'tournament_veteran' then 75 when 'tournament_legend' then 150
    when 'live_first_match' then 20 when 'live_stability' then 50
    when 'live_adr_100' then 75 when 'live_fragger' then 75
    when 'live_team_player' then 50 when 'live_mvp' then 60 else 0 end;
  if v_reward<=0 then return new; end if;
  v_awarded:=public.award_arqon_coins(new.arqon_id,v_reward,'achievement',
    'Достижение «'||new.achievement_name||'»','achievement:'||new.achievement_key);
  if v_awarded then
    select p.user_id into v_user_id from public.profiles p where p.arqon_id=new.arqon_id;
    if v_user_id is not null then
      insert into public.user_notifications(user_id,notification_type,title,body,target_url,related_id)
      values(v_user_id,'system','Новое достижение ARQON!',
        'Получено «'||new.achievement_name||'». Начислено +'||v_reward||' Coins.',
        '/achievements/','achievement:'||new.arqon_id::text||':'||new.achievement_key);
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.award_arqon_achievement_coins() from public,anon,authenticated;