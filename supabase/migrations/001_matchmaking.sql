-- NightLink matchmaking foundation
-- Apply this migration in the Supabase SQL editor or with the Supabase CLI.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Member',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), 'Member')
  )
  on conflict (id) do update
    set display_name = excluded.display_name,
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create table if not exists public.matchmaking_queue (
  user_id uuid primary key references auth.users(id) on delete cascade,
  mode text not null check (mode in ('1v1', '2v2', '1v1v1v1')),
  status text not null default 'waiting' check (status in ('waiting', 'matched', 'cancelled')),
  joined_at timestamptz not null default now()
);

create index if not exists matchmaking_queue_mode_status_joined_idx
  on public.matchmaking_queue (mode, status, joined_at);

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  mode text not null check (mode in ('1v1', '2v2', '1v1v1v1')),
  status text not null default 'ready' check (status in ('ready', 'live', 'completed', 'cancelled')),
  max_players integer not null check (max_players in (2, 4)),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz
);

create table if not exists public.match_players (
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_no integer not null check (team_no between 1 and 4),
  slot_no integer not null check (slot_no between 1 and 2),
  state text not null default 'joined' check (state in ('joined', 'ready', 'left')),
  joined_at timestamptz not null default now(),
  primary key (match_id, user_id),
  unique (match_id, team_no, slot_no)
);

create index if not exists match_players_user_idx on public.match_players (user_id);
create index if not exists matches_status_created_idx on public.matches (status, created_at desc);

create or replace function public.mode_capacity(p_mode text)
returns integer
language sql
immutable
as $$
  select case p_mode when '1v1' then 2 when '2v2' then 4 when '1v1v1v1' then 4 else 0 end;
$$;

create or replace function public.join_matchmaking(p_mode text)
returns table (match_id uuid, mode text, match_status text, player_count integer, capacity integer)
language plpgsql
security definer set search_path = public
as $$
declare
  v_capacity integer;
  v_match_id uuid;
  v_player_count integer;
  v_user uuid := auth.uid();
  v_user_ids uuid[];
  v_index integer;
  v_team integer;
  v_slot integer;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  v_capacity := public.mode_capacity(p_mode);
  if v_capacity = 0 then
    raise exception 'Unsupported match mode';
  end if;

  -- One queue entry per user. Rejoining changes the selected mode and timestamp.
  delete from public.matchmaking_queue
    where user_id = v_user and status = 'waiting';

  -- Serialize batches per mode so two callers cannot consume the same players.
  perform pg_advisory_xact_lock(hashtext('nightlink-matchmaking:' || p_mode));

  insert into public.matchmaking_queue (user_id, mode, status, joined_at)
  values (v_user, p_mode, 'waiting', now())
  on conflict (user_id) do update
    set mode = excluded.mode, status = 'waiting', joined_at = excluded.joined_at;

  select count(*) into v_player_count
    from public.matchmaking_queue
    where mode = p_mode and status = 'waiting';

  if v_player_count < v_capacity then
    return query select null::uuid, p_mode, 'waiting'::text, v_player_count, v_capacity;
    return;
  end if;

  select array_agg(user_id order by joined_at, user_id)
    into v_user_ids
    from (
      select user_id, joined_at
      from public.matchmaking_queue
      where mode = p_mode and status = 'waiting'
      order by joined_at, user_id
      limit v_capacity
      for update
    ) batch;

  insert into public.matches (mode, max_players, created_by)
  values (p_mode, v_capacity, v_user_ids[1])
  returning id into v_match_id;

  for v_index in 1..v_capacity loop
    if p_mode = '2v2' then
      v_team := case when v_index <= 2 then 1 else 2 end;
      v_slot := case when v_index in (1, 3) then 1 else 2 end;
    elsif p_mode = '1v1v1v1' then
      v_team := v_index;
      v_slot := 1;
    else
      v_team := v_index;
      v_slot := 1;
    end if;

    insert into public.match_players (match_id, user_id, team_no, slot_no)
    values (v_match_id, v_user_ids[v_index], v_team, v_slot);
  end loop;

  update public.matchmaking_queue
    set status = 'matched'
    where user_id = any(v_user_ids) and mode = p_mode and status = 'waiting';

  return query
    select v_match_id, p_mode, 'ready'::text, v_capacity, v_capacity;
end;
$$;

create or replace function public.leave_matchmaking()
returns void
language sql
security definer set search_path = public
as $$
  delete from public.matchmaking_queue
  where user_id = auth.uid() and status = 'waiting';
$$;

create or replace function public.get_my_active_match()
returns table (
  match_id uuid,
  mode text,
  match_status text,
  max_players integer,
  player_count bigint,
  created_at timestamptz
)
language sql
security definer set search_path = public
as $$
  select m.id, m.mode, m.status, m.max_players,
         count(mp2.user_id), m.created_at
  from public.matches m
  join public.match_players mp on mp.match_id = m.id
  join public.match_players mp2 on mp2.match_id = m.id and mp2.state <> 'left'
  where mp.user_id = auth.uid()
    and m.status in ('ready', 'live')
  group by m.id
  order by m.created_at desc
  limit 1;
$$;

create or replace function public.set_match_ready(p_match_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_count integer;
  v_capacity integer;
begin
  update public.match_players
    set state = 'ready'
    where match_id = p_match_id and user_id = auth.uid() and state <> 'left';

  if not found then
    raise exception 'You are not a participant in this match';
  end if;

  select count(*) filter (where state = 'ready'), max(m.max_players)
    into v_count, v_capacity
    from public.match_players mp
    join public.matches m on m.id = mp.match_id
    where mp.match_id = p_match_id;

  if v_count = v_capacity then
    update public.matches
      set status = 'live', started_at = coalesce(started_at, now())
      where id = p_match_id and status = 'ready';
  end if;
end;
$$;

create or replace function public.leave_match(p_match_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.match_players
    set state = 'left'
    where match_id = p_match_id and user_id = auth.uid();

  if not found then
    raise exception 'You are not a participant in this match';
  end if;

  if not exists (
    select 1 from public.match_players
    where match_id = p_match_id and state <> 'left'
  ) then
    update public.matches
      set status = 'cancelled', ended_at = now()
      where id = p_match_id and status in ('ready', 'live');
  end if;
end;
$$;

alter table public.profiles enable row level security;
alter table public.matchmaking_queue enable row level security;
alter table public.matches enable row level security;
alter table public.match_players enable row level security;

drop policy if exists profiles_select_authenticated on public.profiles;
create policy profiles_select_authenticated on public.profiles
  for select to authenticated using (true);
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Queue mutations happen through security-definer functions.
drop policy if exists queue_select_own on public.matchmaking_queue;
create policy queue_select_own on public.matchmaking_queue
  for select to authenticated using (user_id = auth.uid());
drop policy if exists queue_delete_own on public.matchmaking_queue;
create policy queue_delete_own on public.matchmaking_queue
  for delete to authenticated using (user_id = auth.uid());

create or replace function public.is_match_participant(p_match_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.match_players
    where match_id = p_match_id and user_id = p_user_id and state <> 'left'
  );
$$;

revoke all on function public.is_match_participant(uuid, uuid) from public;
grant execute on function public.is_match_participant(uuid, uuid) to authenticated;

drop policy if exists matches_select_participant on public.matches;
create policy matches_select_participant on public.matches
  for select to authenticated using (
    public.is_match_participant(id, auth.uid())
  );
drop policy if exists players_select_participant on public.match_players;
create policy players_select_participant on public.match_players
  for select to authenticated using (
    public.is_match_participant(match_id, auth.uid())
  );

revoke all on function public.join_matchmaking(text) from public;
grant execute on function public.join_matchmaking(text) to authenticated;
revoke all on function public.leave_matchmaking() from public;
grant execute on function public.leave_matchmaking() to authenticated;
revoke all on function public.get_my_active_match() from public;
grant execute on function public.get_my_active_match() to authenticated;
revoke all on function public.set_match_ready(uuid) from public;
grant execute on function public.set_match_ready(uuid) to authenticated;
revoke all on function public.leave_match(uuid) from public;
grant execute on function public.leave_match(uuid) to authenticated;

-- Realtime updates for future lobby screens.
alter publication supabase_realtime add table public.matches;
alter publication supabase_realtime add table public.match_players;
