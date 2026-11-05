-- NightLink social connections, VIP access and developer gift privileges.
-- This migration was also applied to the connected Supabase project.

update public.profiles
set username = 'member_' || substr(replace(id::text, '-', ''), 1, 8)
where username is null or trim(username) = '';

create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(username));

alter table public.profiles drop constraint if exists profiles_username_format_check;
alter table public.profiles add constraint profiles_username_format_check
  check (username is not null and username ~ '^[a-z0-9_]{3,24}$');

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (new.id,
    'member_' || substr(replace(new.id::text, '-', ''), 1, 8),
    coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), 'Member'))
  on conflict (id) do update
    set display_name = excluded.display_name, updated_at = now();
  return new;
end;
$$;

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friend_requests_not_self check (sender_id <> receiver_id),
  constraint friend_requests_sender_receiver_unique unique(sender_id, receiver_id)
);
create index if not exists friend_requests_receiver_status_idx
  on public.friend_requests(receiver_id, status, created_at desc);

create table if not exists public.friendships (
  user_low_id uuid not null references auth.users(id) on delete cascade,
  user_high_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_low_id, user_high_id),
  constraint friendships_sorted_ids check (user_low_id < user_high_id)
);
create index if not exists friendships_high_id_idx on public.friendships(user_high_id);

alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
revoke all on public.friend_requests, public.friendships from anon, authenticated;
grant select on public.friend_requests, public.friendships to authenticated;

drop policy if exists friend_requests_read_participants on public.friend_requests;
create policy friend_requests_read_participants on public.friend_requests
  for select to authenticated
  using ((select auth.uid()) = sender_id or (select auth.uid()) = receiver_id);
drop policy if exists friendships_read_participants on public.friendships;
create policy friendships_read_participants on public.friendships
  for select to authenticated
  using ((select auth.uid()) = user_low_id or (select auth.uid()) = user_high_id);

create or replace function public.send_friend_request(p_username text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_sender uuid := auth.uid();
  v_receiver uuid;
  v_request_id uuid;
  v_reverse_id uuid;
begin
  if v_sender is null then raise exception 'Authentication required'; end if;
  if p_username is null or trim(p_username) !~ '^[a-zA-Z0-9_]{3,24}$' then
    raise exception 'Enter a valid username (3-24 letters, numbers or underscores)';
  end if;
  select id into v_receiver from public.profiles
    where lower(username) = lower(trim(p_username)) limit 1;
  if v_receiver is null then raise exception 'No member found with that username'; end if;
  if v_receiver = v_sender then raise exception 'You cannot add yourself'; end if;
  if exists (select 1 from public.friendships
    where user_low_id = least(v_sender, v_receiver)
      and user_high_id = greatest(v_sender, v_receiver)) then
    raise exception 'You are already connected';
  end if;

  select id into v_reverse_id from public.friend_requests
    where sender_id = v_receiver and receiver_id = v_sender and status = 'pending'
    for update;
  if v_reverse_id is not null then
    update public.friend_requests set status = 'accepted', updated_at = now()
      where id = v_reverse_id;
    insert into public.friendships(user_low_id, user_high_id)
      values (least(v_sender, v_receiver), greatest(v_sender, v_receiver))
      on conflict do nothing;
    return v_reverse_id;
  end if;

  insert into public.friend_requests(sender_id, receiver_id, status)
    values (v_sender, v_receiver, 'pending')
    on conflict (sender_id, receiver_id) do update
      set status = 'pending', created_at = now(), updated_at = now()
      where public.friend_requests.status in ('declined','cancelled')
    returning id into v_request_id;
  if v_request_id is null then
    raise exception 'A request to this member is already pending or accepted';
  end if;
  return v_request_id;
end;
$$;

create or replace function public.respond_friend_request(p_request_id uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_request public.friend_requests%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_request from public.friend_requests where id = p_request_id for update;
  if not found or v_request.receiver_id <> v_user then raise exception 'Friend request not found'; end if;
  if v_request.status <> 'pending' then raise exception 'This request has already been answered'; end if;
  update public.friend_requests
    set status = case when p_accept then 'accepted' else 'declined' end, updated_at = now()
    where id = p_request_id;
  if p_accept then
    insert into public.friendships(user_low_id, user_high_id)
      values (least(v_request.sender_id, v_request.receiver_id),
              greatest(v_request.sender_id, v_request.receiver_id))
      on conflict do nothing;
  end if;
  return jsonb_build_object('accepted', p_accept);
end;
$$;
revoke all on function public.send_friend_request(text) from public, anon;
grant execute on function public.send_friend_request(text) to authenticated;
revoke all on function public.respond_friend_request(uuid, boolean) from public, anon;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;

drop policy if exists "Users can read their own conversations" on public.messages;
drop policy if exists "Users can send messages as themselves" on public.messages;
create policy messages_read_connected_only on public.messages for select to authenticated
  using (
    (sender_id = (select auth.uid()) or receiver_id = (select auth.uid()))
    and exists (select 1 from public.friendships f
      where f.user_low_id = least(messages.sender_id, messages.receiver_id)
        and f.user_high_id = greatest(messages.sender_id, messages.receiver_id))
  );
create policy messages_insert_connected_only on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (select 1 from public.friendships f
      where f.user_low_id = least(messages.sender_id, messages.receiver_id)
        and f.user_high_id = greatest(messages.sender_id, messages.receiver_id))
  );

drop policy if exists "Callers can create call invitations" on public.call_invitations;
drop policy if exists "Participants can respond to call invitations" on public.call_invitations;
drop policy if exists "Participants can view their call invitations" on public.call_invitations;
create policy call_invitations_read_connected on public.call_invitations for select to authenticated
  using (
    ((select auth.uid()) = caller_id or (select auth.uid()) = receiver_id)
    and exists (select 1 from public.friendships f
      where f.user_low_id = least(call_invitations.caller_id, call_invitations.receiver_id)
        and f.user_high_id = greatest(call_invitations.caller_id, call_invitations.receiver_id))
  );
create policy call_invitations_insert_connected on public.call_invitations for insert to authenticated
  with check (
    (select auth.uid()) = caller_id and caller_id <> receiver_id and status = 'pending'
    and exists (select 1 from public.friendships f
      where f.user_low_id = least(call_invitations.caller_id, call_invitations.receiver_id)
        and f.user_high_id = greatest(call_invitations.caller_id, call_invitations.receiver_id))
  );
create policy call_invitations_update_connected on public.call_invitations for update to authenticated
  using (
    status = 'pending'
    and ((select auth.uid()) = caller_id or (select auth.uid()) = receiver_id)
    and exists (select 1 from public.friendships f
      where f.user_low_id = least(call_invitations.caller_id, call_invitations.receiver_id)
        and f.user_high_id = greatest(call_invitations.caller_id, call_invitations.receiver_id))
  )
  with check (
    ((select auth.uid()) = caller_id and status = 'cancelled')
    or ((select auth.uid()) = receiver_id and status in ('accepted','declined'))
  );

create table if not exists public.vip_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  source text not null default 'manual' check (source in ('manual','subscription','promotion')),
  created_at timestamptz not null default now()
);
alter table public.vip_memberships enable row level security;
revoke all on public.vip_memberships from anon, authenticated;
grant select on public.vip_memberships to authenticated;
drop policy if exists vip_memberships_read_own on public.vip_memberships;
create policy vip_memberships_read_own on public.vip_memberships
  for select to authenticated using (user_id = (select auth.uid()));

create or replace function public.has_vip_access()
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    lower(coalesce(auth.jwt() ->> 'email', '')) = 'roopanaaz2@gmail.com'
    or exists (select 1 from public.vip_memberships v
      where v.user_id = auth.uid() and v.starts_at <= now()
        and (v.expires_at is null or v.expires_at > now()))
  );
$$;
revoke all on function public.has_vip_access() from public, anon;
grant execute on function public.has_vip_access() to authenticated;

create or replace function public.send_battle_gift(
  p_match_id uuid, p_recipient_id uuid, p_gift_key text, p_quantity integer default 1
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_sender uuid := auth.uid();
  v_is_owner boolean := lower(coalesce(auth.jwt() ->> 'email', '')) = 'roopanaaz2@gmail.com';
  v_gift public.gift_catalog%rowtype;
  v_team integer;
  v_cost integer;
  v_score integer;
  v_balance bigint;
  v_gift_id uuid;
begin
  if v_sender is null then raise exception 'Authentication required'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 10 then
    raise exception 'Gift quantity must be between 1 and 10';
  end if;
  if v_sender = p_recipient_id then raise exception 'You cannot send a gift to yourself'; end if;
  select * into v_gift from public.gift_catalog where gift_key = p_gift_key and active = true;
  if not found then raise exception 'Gift is unavailable'; end if;
  if not exists (select 1 from public.matches where id = p_match_id and status = 'live'
    and (battle_ends_at is null or battle_ends_at > now())) then raise exception 'Battle is not live'; end if;
  select team_no into v_team from public.match_players
    where match_id = p_match_id and user_id = p_recipient_id and state in ('joined','ready');
  if not found then raise exception 'Recipient is not an active player in this battle'; end if;

  v_cost := case when v_is_owner then 0 else v_gift.coin_cost * p_quantity end;
  v_score := v_gift.score_value * p_quantity;
  if v_cost > 0 then
    select balance into v_balance from public.coin_wallets where user_id = v_sender for update;
    if not found or v_balance < v_cost then raise exception 'Not enough coins'; end if;
    update public.coin_wallets set balance = balance - v_cost, updated_at = now()
      where user_id = v_sender;
    insert into public.coin_ledger(user_id, amount, entry_type, reference_id, description)
      values (v_sender, -v_cost, 'gift_sent', gen_random_uuid()::text, 'Sent ' || v_gift.display_name);
  elsif v_gift.is_free and not v_is_owner then
    if (select count(*) from public.battle_gifts
      where match_id = p_match_id and sender_id = v_sender
        and gift_key = p_gift_key and created_at > now() - interval '1 minute') >= 1 then
      raise exception 'Please wait before sending another free heart';
    end if;
  end if;

  insert into public.battle_gifts(match_id, sender_id, recipient_id, team_no, gift_key,
    quantity, coins_spent, score_added)
  values (p_match_id, v_sender, p_recipient_id, v_team, p_gift_key,
    p_quantity, v_cost, v_score) returning id into v_gift_id;
  insert into public.battle_scores(match_id, team_no, score)
    values (p_match_id, v_team, v_score)
    on conflict (match_id, team_no) do update
      set score = public.battle_scores.score + excluded.score, updated_at = now();
  return jsonb_build_object('gift_id', v_gift_id, 'coins_spent', v_cost,
    'score_added', v_score, 'developer_free_gift', v_is_owner);
end;
$$;
revoke all on function public.send_battle_gift(uuid, uuid, text, integer) from public, anon;
grant execute on function public.send_battle_gift(uuid, uuid, text, integer) to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'friend_requests') then
    alter publication supabase_realtime add table public.friend_requests;
  end if;
end $$;
