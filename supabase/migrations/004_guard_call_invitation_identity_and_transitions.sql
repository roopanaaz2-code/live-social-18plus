-- Lock call invitation identity fields; only the intended recipient can accept/decline,
-- and only the caller can cancel a pending invitation.
create or replace function public.guard_call_invitation_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.caller_id is distinct from old.caller_id
     or new.receiver_id is distinct from old.receiver_id
     or new.call_mode is distinct from old.call_mode
     or new.room_name is distinct from old.room_name
     or new.created_at is distinct from old.created_at
     or new.expires_at is distinct from old.expires_at then
    raise exception 'Call invitation details cannot be changed';
  end if;

  if old.status <> 'pending' then
    raise exception 'This call invitation is no longer pending';
  end if;

  if auth.uid() = old.caller_id then
    if new.status <> 'cancelled' then
      raise exception 'Only the recipient can accept or decline a call';
    end if;
  elsif auth.uid() = old.receiver_id then
    if new.status not in ('accepted','declined') then
      raise exception 'Only the caller can cancel a call';
    end if;
  else
    raise exception 'You are not a participant in this call';
  end if;

  return new;
end;
$$;

drop trigger if exists call_invitation_update_guard on public.call_invitations;
create trigger call_invitation_update_guard
before update on public.call_invitations
for each row execute function public.guard_call_invitation_update();

revoke all on function public.guard_call_invitation_update() from public, anon, authenticated;
