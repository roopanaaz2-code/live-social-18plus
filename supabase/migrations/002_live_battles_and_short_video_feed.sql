-- NightLink live battle and short-video feed extension.
-- Depends on the existing NightLink matchmaking, wallet and gift foundation.

alter table public.matches
  add column if not exists battle_duration_seconds integer not null default 240
    check (battle_duration_seconds between 30 and 900),
  add column if not exists battle_ends_at timestamptz,
  add column if not exists winner_team_no integer;

create table if not exists public.battle_comments (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  content text not null check (char_length(content) between 1 and 300),
  created_at timestamptz not null default now()
);
create index if not exists battle_comments_match_created_idx
  on public.battle_comments(match_id, created_at desc);

create table if not exists public.battle_likes (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  host_id uuid not null references auth.users(id) on delete cascade,
  team_no integer not null check (team_no between 1 and 4),
  created_at timestamptz not null default now(),
  constraint battle_likes_once_per_viewer unique(match_id, viewer_id, host_id),
  constraint battle_likes_not_self check (viewer_id <> host_id)
);
create index if not exists battle_likes_match_idx on public.battle_likes(match_id);

create or replace function public.initialize_live_battle()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'live' and old.status is distinct from 'live' then
    new.started_at := coalesce(new.started_at, now());
    new.battle_ends_at := coalesce(new.battle_ends_at,
      new.started_at + make_interval(secs => new.battle_duration_seconds));
    insert into public.battle_scores(match_id, team_no, score)
    select new.id, mp.team_no, count(*)::bigint * 3
    from public.match_players mp
    where mp.match_id = new.id and mp.state in ('joined','ready')
    group by mp.team_no
    on conflict (match_id, team_no) do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists matches_initialize_live_battle on public.matches;
create trigger matches_initialize_live_battle
before update of status on public.matches
for each row execute function public.initialize_live_battle();

create or replace function public.add_battle_comment(p_match_id uuid, p_content text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_name text;
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_content is null or char_length(trim(p_content)) not between 1 and 300 then
    raise exception 'Comment must be between 1 and 300 characters';
  end if;
  if not exists (select 1 from public.matches where id = p_match_id
    and status = 'live' and (battle_ends_at is null or battle_ends_at > now())) then
    raise exception 'Battle is not live';
  end if;
  select coalesce(nullif(display_name,''),'Member') into v_name
    from public.profiles where id = v_user;
  insert into public.battle_comments(match_id,user_id,display_name,content)
  values (p_match_id,v_user,coalesce(v_name,'Member'),trim(p_content))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.add_battle_like(p_match_id uuid, p_host_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_team integer;
  v_inserted integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if v_user = p_host_id then raise exception 'You cannot like your own battle profile'; end if;
  if not exists (select 1 from public.matches where id = p_match_id
    and status = 'live' and (battle_ends_at is null or battle_ends_at > now())) then
    raise exception 'Battle is not live';
  end if;
  select team_no into v_team from public.match_players
    where match_id = p_match_id and user_id = p_host_id and state in ('joined','ready');
  if not found then raise exception 'Host is not playing in this battle'; end if;
  insert into public.battle_likes(match_id,viewer_id,host_id,team_no)
  values (p_match_id,v_user,p_host_id,v_team)
  on conflict (match_id,viewer_id,host_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    insert into public.battle_scores(match_id,team_no,score) values (p_match_id,v_team,2)
    on conflict (match_id,team_no) do update
      set score = public.battle_scores.score + 2, updated_at = now();
  end if;
  return jsonb_build_object('added',v_inserted = 1,'score_added',case when v_inserted = 1 then 2 else 0 end);
end;
$$;

create or replace function public.finish_battle(p_match_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_match public.matches%rowtype;
  v_winner integer;
  v_scores jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_match from public.matches where id = p_match_id for update;
  if not found then raise exception 'Battle not found'; end if;
  if v_match.status = 'completed' then
    select coalesce(jsonb_agg(jsonb_build_object('team_no',team_no,'score',score)),'[]'::jsonb)
      into v_scores from public.battle_scores where match_id = p_match_id;
    return jsonb_build_object('status','completed','winner_team_no',v_match.winner_team_no,'scores',v_scores);
  end if;
  if v_match.status <> 'live' then raise exception 'Battle is not live'; end if;
  if v_match.battle_ends_at is not null and now() < v_match.battle_ends_at then
    raise exception 'Battle timer has not finished';
  end if;
  select team_no into v_winner from public.battle_scores
    where match_id = p_match_id order by score desc, team_no asc limit 1;
  update public.matches set status='completed',ended_at=now(),winner_team_no=v_winner
    where id=p_match_id;
  select coalesce(jsonb_agg(jsonb_build_object('team_no',team_no,'score',score)),'[]'::jsonb)
    into v_scores from public.battle_scores where match_id=p_match_id;
  return jsonb_build_object('status','completed','winner_team_no',v_winner,'scores',v_scores);
end;
$$;

-- Discoverable live battles. This also finalizes expired matches on the next
-- authenticated lobby refresh, so a disconnected room cannot remain live forever.
create or replace function public.get_live_battles()
returns table(match_id uuid,mode text,started_at timestamptz,battle_ends_at timestamptz,players jsonb,scores jsonb)
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.matches m set status='completed',ended_at=coalesce(m.ended_at,now()),
    winner_team_no=(select bs.team_no from public.battle_scores bs where bs.match_id=m.id
      order by bs.score desc,bs.team_no asc limit 1)
  where m.status='live' and m.battle_ends_at is not null and m.battle_ends_at <= now();

  return query select m.id,m.mode,m.started_at,m.battle_ends_at,
    coalesce((select jsonb_agg(jsonb_build_object(
      'user_id',mp.user_id,'team_no',mp.team_no,
      'display_name',coalesce(nullif(p.display_name,''),'Member'),'avatar_url',p.avatar_url)
      order by mp.team_no,mp.slot_no)
      from public.match_players mp left join public.profiles p on p.id=mp.user_id
      where mp.match_id=m.id and mp.state in ('joined','ready')),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('team_no',bs.team_no,'score',bs.score) order by bs.team_no)
      from public.battle_scores bs where bs.match_id=m.id),'[]'::jsonb)
  from public.matches m where m.status='live' order by m.started_at desc;
end;
$$;

create or replace function public.get_battle_access(p_match_id uuid)
returns table(room_name text,is_player boolean,battle_ends_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  return query select 'battle_'||replace(m.id::text,'-',''),
    exists(select 1 from public.match_players mp where mp.match_id=m.id
      and mp.user_id=v_user and mp.state in ('joined','ready')),
    m.battle_ends_at
  from public.matches m where m.id=p_match_id and m.status='live';
  if not found then raise exception 'Battle is not live'; end if;
end;
$$;

alter table public.battle_gifts
  add column if not exists sender_name text,
  add column if not exists recipient_name text,
  add column if not exists gift_name text,
  add column if not exists gift_emoji text;

create or replace function public.enrich_battle_gift_event()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  select coalesce(nullif(display_name,''),'Member') into new.sender_name
    from public.profiles where id=new.sender_id;
  select coalesce(nullif(display_name,''),'Member') into new.recipient_name
    from public.profiles where id=new.recipient_id;
  select display_name,emoji into new.gift_name,new.gift_emoji
    from public.gift_catalog where gift_key=new.gift_key;
  return new;
end;
$$;
drop trigger if exists battle_gifts_enrich_event on public.battle_gifts;
create trigger battle_gifts_enrich_event before insert on public.battle_gifts
for each row execute function public.enrich_battle_gift_event();

create or replace function public.guard_battle_gift_time()
returns trigger language plpgsql set search_path = public as $$
begin
  if not exists(select 1 from public.matches where id=new.match_id and status='live'
    and (battle_ends_at is null or battle_ends_at>now())) then
    raise exception 'Battle has ended';
  end if;
  return new;
end;
$$;
drop trigger if exists battle_gifts_time_guard on public.battle_gifts;
create trigger battle_gifts_time_guard before insert on public.battle_gifts
for each row execute function public.guard_battle_gift_time();

insert into public.gift_catalog(gift_key,display_name,emoji,coin_cost,score_value,is_free,active)
values
 ('heart','Heart','❤️',0,1,true,true),
 ('rose','Rose','🌹',3,3,false,true),
 ('coffee','Coffee','☕',10,10,false,true),
 ('doughnut','Doughnut','🍩',15,15,false,true),
 ('ice_cream','Ice Cream','🍦',20,20,false,true),
 ('flower_bouquet','Flower Bouquet','💐',30,30,false,true),
 ('love_letter','Love Letter','💌',35,35,false,true),
 ('sunglasses','Sunglasses','🕶️',50,50,false,true),
 ('perfume','Perfume','香',75,75,false,true),
 ('teddy_bear','Teddy Bear','🧸',100,100,false,true),
 ('crown','Crown','👑',150,150,false,true),
 ('diamond','Diamond','💎',200,200,false,true),
 ('trophy','Trophy','🏆',300,300,false,true),
 ('sports_car','Sports Car','🏎️',500,500,false,true),
 ('fireworks','Fireworks','🎆',700,700,false,true),
 ('yacht','Yacht','🛥️',1000,1000,false,true),
 ('castle','Castle','🏰',1500,1500,false,true),
 ('rocket','Rocket','🚀',2000,2000,false,true),
 ('planet','Planet','🪐',3000,3000,false,true),
 ('galaxy','Galaxy','🌌',5000,5000,false,true)
on conflict(gift_key) do update set display_name=excluded.display_name,emoji=excluded.emoji,
 coin_cost=excluded.coin_cost,score_value=excluded.score_value,is_free=excluded.is_free,active=true;

create table if not exists public.video_posts (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 video_path text not null,
 caption text not null default '' check(char_length(caption)<=500),
 duration_seconds integer not null check(duration_seconds between 1 and 15),
 audio_source text not null default 'none' check(audio_source in ('none','app','device','original')),
 audio_path text,
 music_track_id uuid,
 created_at timestamptz not null default now()
);
create index if not exists video_posts_created_idx on public.video_posts(created_at desc);

create table if not exists public.video_post_interactions (
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.video_posts(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 action text not null check(action in ('like','share')),
 created_at timestamptz not null default now(),
 unique(post_id,user_id,action)
);
create table if not exists public.video_post_comments (
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.video_posts(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 display_name text not null,
 content text not null check(char_length(content) between 1 and 500),
 created_at timestamptz not null default now(),
 unique(post_id,user_id)
);
create index if not exists video_post_comments_post_created_idx
 on public.video_post_comments(post_id,created_at desc);

create table if not exists public.app_music_tracks (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 artist text,
 storage_path text not null,
 duration_seconds integer,
 active boolean not null default true,
 created_at timestamptz not null default now()
);

alter table public.battle_comments enable row level security;
alter table public.battle_likes enable row level security;
alter table public.video_posts enable row level security;
alter table public.video_post_interactions enable row level security;
alter table public.video_post_comments enable row level security;
alter table public.app_music_tracks enable row level security;

drop policy if exists battle_comments_read_authenticated on public.battle_comments;
create policy battle_comments_read_authenticated on public.battle_comments for select to authenticated using(true);
drop policy if exists battle_likes_read_authenticated on public.battle_likes;
create policy battle_likes_read_authenticated on public.battle_likes for select to authenticated using(true);
drop policy if exists video_posts_read_authenticated on public.video_posts;
create policy video_posts_read_authenticated on public.video_posts for select to authenticated using(true);
drop policy if exists video_posts_insert_own on public.video_posts;
create policy video_posts_insert_own on public.video_posts for insert to authenticated with check(user_id=(select auth.uid()));
drop policy if exists video_posts_update_own on public.video_posts;
create policy video_posts_update_own on public.video_posts for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
drop policy if exists video_posts_delete_own on public.video_posts;
create policy video_posts_delete_own on public.video_posts for delete to authenticated using(user_id=(select auth.uid()));
drop policy if exists video_post_interactions_read_authenticated on public.video_post_interactions;
create policy video_post_interactions_read_authenticated on public.video_post_interactions for select to authenticated using(true);
drop policy if exists video_post_interactions_insert_own on public.video_post_interactions;
create policy video_post_interactions_insert_own on public.video_post_interactions for insert to authenticated with check(user_id=(select auth.uid()));
drop policy if exists video_post_comments_read_authenticated on public.video_post_comments;
create policy video_post_comments_read_authenticated on public.video_post_comments for select to authenticated using(true);
drop policy if exists video_post_comments_insert_own on public.video_post_comments;
create policy video_post_comments_insert_own on public.video_post_comments for insert to authenticated
 with check(user_id=(select auth.uid()) and exists(select 1 from public.video_posts p where p.id=post_id));
drop policy if exists app_music_tracks_read_active on public.app_music_tracks;
create policy app_music_tracks_read_active on public.app_music_tracks for select to authenticated using(active=true);

grant select on public.battle_comments,public.battle_likes,public.video_posts,
 public.video_post_interactions,public.video_post_comments,public.app_music_tracks to authenticated;
grant insert,update,delete on public.video_posts to authenticated;
grant insert on public.video_post_interactions,public.video_post_comments to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values
 ('nightlink-videos','nightlink-videos',true,52428800,array['video/mp4','video/quicktime','video/webm']),
 ('nightlink-audio','nightlink-audio',true,20971520,array['audio/mpeg','audio/mp4','audio/aac','audio/wav','audio/x-wav','audio/ogg'])
on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists nightlink_video_upload_own_folder on storage.objects;
create policy nightlink_video_upload_own_folder on storage.objects for insert to authenticated
 with check(bucket_id='nightlink-videos' and (storage.foldername(name))[1]=(select auth.uid()::text));
drop policy if exists nightlink_audio_upload_own_folder on storage.objects;
create policy nightlink_audio_upload_own_folder on storage.objects for insert to authenticated
 with check(bucket_id='nightlink-audio' and (storage.foldername(name))[1]=(select auth.uid()::text));

revoke all on function public.add_battle_comment(uuid,text) from public,anon;
grant execute on function public.add_battle_comment(uuid,text) to authenticated;
revoke all on function public.add_battle_like(uuid,uuid) from public,anon;
grant execute on function public.add_battle_like(uuid,uuid) to authenticated;
revoke all on function public.finish_battle(uuid) from public,anon;
grant execute on function public.finish_battle(uuid) to authenticated;
revoke all on function public.get_live_battles() from public,anon;
grant execute on function public.get_live_battles() to authenticated;
revoke all on function public.get_battle_access(uuid) from public,anon;
grant execute on function public.get_battle_access(uuid) to authenticated;
revoke all on function public.initialize_live_battle() from public,anon,authenticated;
revoke all on function public.enrich_battle_gift_event() from public,anon,authenticated;
revoke all on function public.guard_battle_gift_time() from public,anon,authenticated;

do $$
declare t text;
begin
 foreach t in array array['battle_comments','battle_likes','video_posts','video_post_interactions','video_post_comments'] loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
    and schemaname='public' and tablename=t) then
    execute format('alter publication supabase_realtime add table public.%I',t);
  end if;
 end loop;
end $$;


-- Persistent profile likes are separate from the per-battle +2 score event.
create table if not exists public.profile_likes (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references auth.users(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(profile_id, viewer_id),
  check(profile_id <> viewer_id)
);
alter table public.profile_likes enable row level security;
drop policy if exists profile_likes_read_authenticated on public.profile_likes;
create policy profile_likes_read_authenticated on public.profile_likes
  for select to authenticated using(true);
grant select on public.profile_likes to authenticated;

create or replace function public.add_battle_like(p_match_id uuid, p_host_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_team integer;
  v_battle_inserted integer;
  v_profile_inserted integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if v_user = p_host_id then raise exception 'You cannot like your own battle profile'; end if;
  if not exists(select 1 from public.matches where id=p_match_id and status='live'
    and (battle_ends_at is null or battle_ends_at>now())) then raise exception 'Battle is not live'; end if;
  select team_no into v_team from public.match_players
    where match_id=p_match_id and user_id=p_host_id and state in ('joined','ready');
  if not found then raise exception 'Host is not playing in this battle'; end if;
  insert into public.profile_likes(profile_id,viewer_id)
    values(p_host_id,v_user) on conflict(profile_id,viewer_id) do nothing;
  get diagnostics v_profile_inserted = row_count;
  insert into public.battle_likes(match_id,viewer_id,host_id,team_no)
    values(p_match_id,v_user,p_host_id,v_team) on conflict(match_id,viewer_id,host_id) do nothing;
  get diagnostics v_battle_inserted = row_count;
  if v_battle_inserted=1 then
    insert into public.battle_scores(match_id,team_no,score) values(p_match_id,v_team,2)
    on conflict(match_id,team_no) do update
      set score=public.battle_scores.score+2,updated_at=now();
  end if;
  return jsonb_build_object('added',v_battle_inserted=1,
    'profile_like_added',v_profile_inserted=1,
    'score_added',case when v_battle_inserted=1 then 2 else 0 end);
end;
$$;
revoke all on function public.add_battle_like(uuid,uuid) from public,anon;
grant execute on function public.add_battle_like(uuid,uuid) to authenticated;


-- A tied top score is a draw rather than an arbitrary team-number win.
create or replace function public.finish_battle(p_match_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_match public.matches%rowtype;
  v_winner integer;
  v_scores jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_match from public.matches where id=p_match_id for update;
  if not found then raise exception 'Battle not found'; end if;
  if v_match.status='completed' then
    select coalesce(jsonb_agg(jsonb_build_object('team_no',team_no,'score',score)),'[]'::jsonb)
      into v_scores from public.battle_scores where match_id=p_match_id;
    return jsonb_build_object('status','completed','winner_team_no',v_match.winner_team_no,
      'is_draw',v_match.winner_team_no is null,'scores',v_scores);
  end if;
  if v_match.status<>'live' then raise exception 'Battle is not live'; end if;
  if v_match.battle_ends_at is not null and now()<v_match.battle_ends_at then
    raise exception 'Battle timer has not finished';
  end if;
  select case when count(*)=1 then max(team_no) else null end into v_winner
  from public.battle_scores where match_id=p_match_id
    and score=(select max(score) from public.battle_scores where match_id=p_match_id);
  update public.matches set status='completed',ended_at=now(),winner_team_no=v_winner where id=p_match_id;
  select coalesce(jsonb_agg(jsonb_build_object('team_no',team_no,'score',score)),'[]'::jsonb)
    into v_scores from public.battle_scores where match_id=p_match_id;
  return jsonb_build_object('status','completed','winner_team_no',v_winner,
    'is_draw',v_winner is null,'scores',v_scores);
end;
$$;

create or replace function public.get_live_battles()
returns table(match_id uuid,mode text,started_at timestamptz,battle_ends_at timestamptz,players jsonb,scores jsonb)
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.matches m set status='completed',ended_at=coalesce(m.ended_at,now()),
    winner_team_no=(
      select case when count(*)=1 then max(team_no) else null end
      from public.battle_scores bs where bs.match_id=m.id
        and bs.score=(select max(bs2.score) from public.battle_scores bs2 where bs2.match_id=m.id)
    )
  where m.status='live' and m.battle_ends_at is not null and m.battle_ends_at<=now();
  return query select m.id,m.mode,m.started_at,m.battle_ends_at,
    coalesce((select jsonb_agg(jsonb_build_object('user_id',mp.user_id,'team_no',mp.team_no,
      'display_name',coalesce(nullif(p.display_name,''),'Member'),'avatar_url',p.avatar_url)
      order by mp.team_no,mp.slot_no)
      from public.match_players mp left join public.profiles p on p.id=mp.user_id
      where mp.match_id=m.id and mp.state in ('joined','ready')),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('team_no',bs.team_no,'score',bs.score) order by bs.team_no)
      from public.battle_scores bs where bs.match_id=m.id),'[]'::jsonb)
  from public.matches m where m.status='live' order by m.started_at desc;
end;
$$;
revoke all on function public.finish_battle(uuid) from public,anon;
grant execute on function public.finish_battle(uuid) to authenticated;
revoke all on function public.get_live_battles() from public,anon;
grant execute on function public.get_live_battles() to authenticated;


-- Keep matchmaking SECURITY DEFINER RPCs unavailable to unauthenticated clients.
revoke all on function public.get_my_active_match() from public, anon;
grant execute on function public.get_my_active_match() to authenticated;
revoke all on function public.is_match_participant(uuid,uuid) from public, anon;
grant execute on function public.is_match_participant(uuid,uuid) to authenticated;
revoke all on function public.join_matchmaking(text) from public, anon;
grant execute on function public.join_matchmaking(text) to authenticated;
revoke all on function public.leave_match(uuid) from public, anon;
grant execute on function public.leave_match(uuid) to authenticated;
revoke all on function public.leave_matchmaking() from public, anon;
grant execute on function public.leave_matchmaking() to authenticated;
revoke all on function public.set_match_ready(uuid) from public, anon;
grant execute on function public.set_match_ready(uuid) to authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.rls_auto_enable() from public, anon, authenticated;
