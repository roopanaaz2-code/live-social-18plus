-- Keep the developer email out of current application source and policies.
create or replace function public.has_vip_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and (
    auth.uid() = 'fcdb86f2-1fce-4f7a-8d84-f1ace7df12cd'::uuid
    or exists (
      select 1 from public.vip_memberships v
      where v.user_id = auth.uid()
        and v.starts_at <= now()
        and (v.expires_at is null or v.expires_at > now())
    )
  );
$$;
revoke all on function public.has_vip_access() from public, anon;
grant execute on function public.has_vip_access() to authenticated;

create or replace function public.send_battle_gift(
  p_match_id uuid,
  p_recipient_id uuid,
  p_gift_key text,
  p_quantity integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender uuid := auth.uid();
  v_is_owner boolean := auth.uid() = 'fcdb86f2-1fce-4f7a-8d84-f1ace7df12cd'::uuid;
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

  select * into v_gift from public.gift_catalog
  where gift_key = p_gift_key and active = true;
  if not found then raise exception 'Gift is unavailable'; end if;

  if not exists (
    select 1 from public.matches
    where id = p_match_id and status = 'live'
      and (battle_ends_at is null or battle_ends_at > now())
  ) then
    raise exception 'Battle is not live';
  end if;

  select team_no into v_team
  from public.match_players
  where match_id = p_match_id and user_id = p_recipient_id
    and state in ('joined','ready');
  if not found then raise exception 'Recipient is not an active player in this battle'; end if;

  v_cost := case when v_is_owner then 0 else v_gift.coin_cost * p_quantity end;
  v_score := v_gift.score_value * p_quantity;

  if v_cost > 0 then
    select balance into v_balance
    from public.coin_wallets where user_id = v_sender for update;
    if not found or v_balance < v_cost then raise exception 'Not enough coins'; end if;

    update public.coin_wallets
      set balance = balance - v_cost, updated_at = now()
      where user_id = v_sender;

    insert into public.coin_ledger(user_id, amount, entry_type, reference_id, description)
      values (v_sender, -v_cost, 'gift_sent', gen_random_uuid()::text,
              'Sent ' || v_gift.display_name);
  elsif v_gift.is_free and not v_is_owner then
    if (
      select count(*) from public.battle_gifts
      where match_id = p_match_id and sender_id = v_sender
        and gift_key = p_gift_key and created_at > now() - interval '1 minute'
    ) >= 1 then
      raise exception 'Please wait before sending another free heart';
    end if;
  end if;

  insert into public.battle_gifts(
    match_id, sender_id, recipient_id, team_no, gift_key,
    quantity, coins_spent, score_added
  )
  values (
    p_match_id, v_sender, p_recipient_id, v_team, p_gift_key,
    p_quantity, v_cost, v_score
  )
  returning id into v_gift_id;

  insert into public.battle_scores(match_id, team_no, score)
  values (p_match_id, v_team, v_score)
  on conflict (match_id, team_no) do update
    set score = public.battle_scores.score + excluded.score,
        updated_at = now();

  return jsonb_build_object(
    'gift_id', v_gift_id,
    'coins_spent', v_cost,
    'score_added', v_score,
    'developer_free_gift', v_is_owner
  );
end;
$$;
revoke all on function public.send_battle_gift(uuid, uuid, text, integer) from public, anon;
grant execute on function public.send_battle_gift(uuid, uuid, text, integer) to authenticated;

drop policy if exists "Owner can view all coin payment orders" on public.coin_orders;
create policy "Owner can view all coin payment orders"
  on public.coin_orders
  for select to authenticated
  using (auth.uid() = 'fcdb86f2-1fce-4f7a-8d84-f1ace7df12cd'::uuid);
