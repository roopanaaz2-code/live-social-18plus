-- Double-tap likes increase profile likes only; they never change battle score.
alter table public.profile_likes
  drop constraint if exists profile_likes_profile_id_viewer_id_key;

create index if not exists profile_likes_profile_id_created_idx
  on public.profile_likes (profile_id, created_at desc);

create or replace function public.add_battle_like(p_match_id uuid, p_host_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_profile_inserted integer;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;
  if v_user = p_host_id then
    raise exception 'You cannot like your own battle profile';
  end if;
  if not exists (
    select 1 from public.matches
    where id = p_match_id
      and status = 'live'
      and (battle_ends_at is null or battle_ends_at > now())
  ) then
    raise exception 'Battle is not live';
  end if;
  if not exists (
    select 1 from public.match_players
    where match_id = p_match_id
      and user_id = p_host_id
      and state in ('joined', 'ready')
  ) then
    raise exception 'Host is not playing in this battle';
  end if;

  -- Record every deliberate double-tap as a profile like.
  insert into public.profile_likes (profile_id, viewer_id)
  values (p_host_id, v_user);
  get diagnostics v_profile_inserted = row_count;

  -- Keep one engagement record per viewer/host/battle, but do not award
  -- battle points for likes. Battle points come from joining (+3/player)
  -- and gifts only.
  insert into public.battle_likes (match_id, viewer_id, host_id, team_no)
  select p_match_id, v_user, p_host_id, mp.team_no
  from public.match_players mp
  where mp.match_id = p_match_id
    and mp.user_id = p_host_id
    and mp.state in ('joined', 'ready')
  on conflict (match_id, viewer_id, host_id) do nothing;

  return jsonb_build_object(
    'added', v_profile_inserted = 1,
    'profile_like_added', v_profile_inserted = 1,
    'score_added', 0
  );
end;
$$;

revoke all on function public.add_battle_like(uuid, uuid) from public, anon;
grant execute on function public.add_battle_like(uuid, uuid) to authenticated;
