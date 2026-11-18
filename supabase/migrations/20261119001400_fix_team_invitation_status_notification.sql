create or replace function public.notify_team_invitation_status()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
 if old.status is distinct from new.status and new.status in ('accepted','declined') then
  insert into public.user_notifications(user_id,notification_type,title,body,target_url,related_id)
  values(
   new.invited_by,
   'team_status',
   case when new.status='accepted' then 'Приглашение принято' else 'Приглашение отклонено' end,
   'Игрок '||coalesce(
     (select coalesce(nullif(p.game_nick,''),nullif(p.display_name,''),'ARQON #'||p.arqon_id::text)
      from public.profiles p where p.user_id=new.target_user_id limit 1),
     'ARQON'
   )||
   case when new.status='accepted' then ' принял приглашение в команду «' else ' отклонил приглашение в команду «' end||
   left(new.team_name,100)||'»',
   '/teams/',
   new.id::text
  );
 end if;
 return new;
end;
$function$;
