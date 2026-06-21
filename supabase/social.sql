-- ============================================================================
-- Tokenholic social schema  (supabase/social.sql)
-- ============================================================================
-- Run as-is in the Supabase dashboard -> SQL Editor. Idempotent: safe to re-run.
-- Additive to schema.sql; does NOT touch public.device_snapshots.
--
-- THREAT MODEL: the publishable/anon key ships in the client. A hostile client
-- holds that key PLUS a valid session for SOME user. It must NOT be able to:
-- read a non-friend's numbers/profile, forge/auto-create a friendship, enumerate
-- the user base or handle namespace, or forge/inflate ANOTHER user's daily total.
--
-- STRATEGY (post-red-team):
--  * profiles & daily_totals have NO cross-user SELECT policy. All cross-user
--    reads go through SECURITY DEFINER RPCs that first prove an ACCEPTED
--    friendship + sharing-on.
--  * daily_totals is RPC-ONLY: direct INSERT/UPDATE/DELETE are revoked from
--    authenticated, so EVERY integrity guard (bounds, finiteness, monotonicity,
--    device cap, day window) lives in upsert_daily_total and cannot be bypassed
--    via PostgREST. (Red-team: number-integrity lens.)
--  * Friendship mutation is consent-based and only via definer RPCs; no client
--    INSERT path. Invite redemption is single-use-by-default and refuses
--    blocked/revoked pairs. (Red-team: HIGH invite findings.)
--  * Every definer function uses `set search_path = ''` and fully schema-
--    qualified identifiers, and asserts auth.uid() is not null up front.

create extension if not exists pgcrypto;

-- ============================================================================
-- 0. Shared helpers
-- ============================================================================

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end; $$;

create or replace function public.normalize_handle(h text)
returns text language sql immutable as $$ select lower(btrim(h)) $$;

-- ============================================================================
-- 1. profiles
-- ============================================================================
-- Lazily created on first social engagement (claim_handle); never on signup, so
-- a non-participant has no discoverable handle. github_login is captured
-- server-side from the JWT so a squatter cannot fully impersonate a GitHub user.

create table if not exists public.profiles (
    user_id            uuid        primary key references auth.users(id) on delete cascade,
    handle             text        not null,
    handle_norm        text        not null,
    display_name       text,
    avatar_url         text,
    github_login       text,                                  -- server-captured, display/verify
    share_daily_total  boolean     not null default true,
    last_handle_change timestamptz,
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now(),
    constraint handle_norm_matches check (handle_norm = lower(btrim(handle))),
    constraint handle_format check (handle_norm ~ '^[a-z0-9][a-z0-9_]{2,29}$')
);

create unique index if not exists profiles_handle_norm_key
    on public.profiles (handle_norm);

drop trigger if exists set_updated_at on public.profiles;
create trigger set_updated_at
    before insert or update on public.profiles
    for each row execute function public.touch_updated_at();

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
    for select to authenticated using (user_id = auth.uid());
-- No INSERT/UPDATE/DELETE policy: profile writes go through claim_handle /
-- set_share_preference (definer). DELETE cascades from auth.users on account
-- deletion. (Cross-user discovery is ONLY via the lookup/leaderboard RPCs.)

-- Reserved/abusable handles cannot be claimed.
create table if not exists public.reserved_handles (handle_norm text primary key);
-- RLS on with NO policy: clients can't read the denylist directly. The seed
-- insert below and the claim_handle check both run with RLS bypassed (the SQL
-- editor as table owner; claim_handle as SECURITY DEFINER), so this is purely
-- to keep the denylist unreadable by anon/authenticated keys.
alter table public.reserved_handles enable row level security;
insert into public.reserved_handles (handle_norm) values
    ('admin'),('administrator'),('anthropic'),('claude'),('tokenholic'),
    ('support'),('official'),('system'),('root'),('staff'),('mod'),('moderator')
on conflict do nothing;

-- ============================================================================
-- 2. friendships  (accepted, symmetric, canonical ordered pair)
-- ============================================================================

create table if not exists public.friendships (
    user_low   uuid        not null references auth.users(id) on delete cascade,
    user_high  uuid        not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_low, user_high),
    constraint friendship_ordered check (user_low < user_high)
);
create index if not exists friendships_high_idx on public.friendships (user_high);

alter table public.friendships enable row level security;

drop policy if exists "friendships_select_mine" on public.friendships;
create policy "friendships_select_mine" on public.friendships
    for select to authenticated using (auth.uid() in (user_low, user_high));
-- Unfriend is via remove_friend() (definer) so it can also record a revocation.
-- No client INSERT/UPDATE/DELETE policy.

-- ============================================================================
-- 2b. blocks + revocations  (make unfriend durable; red-team MEDIUM)
-- ============================================================================
-- A blocked pair can never be (re)friended by request OR invite. A revocation
-- records that a friendship was torn down so a still-live invite code cannot
-- silently re-friend the pair without a fresh, explicit request.

create table if not exists public.blocks (
    blocker    uuid        not null references auth.users(id) on delete cascade,
    blocked    uuid        not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker, blocked)
);
alter table public.blocks enable row level security;
drop policy if exists "blocks_select_mine" on public.blocks;
create policy "blocks_select_mine" on public.blocks
    for select to authenticated using (blocker = auth.uid());
-- writes via block_user()/unblock_user() definer RPCs only.

create table if not exists public.friendship_revocations (
    user_low   uuid        not null,
    user_high  uuid        not null,
    revoked_at timestamptz not null default now(),
    primary key (user_low, user_high),
    constraint revocation_ordered check (user_low < user_high)
);
-- internal only: no RLS-exposed policy, read/written exclusively inside definers.
alter table public.friendship_revocations enable row level security;

-- ============================================================================
-- 3. friend_requests  (directed, pending consent)
-- ============================================================================

create table if not exists public.friend_requests (
    id          uuid        primary key default gen_random_uuid(),
    requester   uuid        not null references auth.users(id) on delete cascade,
    addressee   uuid        not null references auth.users(id) on delete cascade,
    status      text        not null default 'pending'
                            check (status in ('pending','accepted','declined','cancelled')),
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    constraint no_self_request check (requester <> addressee)
);
create unique index if not exists friend_requests_pending_key
    on public.friend_requests (requester, addressee) where status = 'pending';
create index if not exists friend_requests_addressee_idx
    on public.friend_requests (addressee) where status = 'pending';
create index if not exists friend_requests_requester_idx
    on public.friend_requests (requester) where status = 'pending';

drop trigger if exists set_updated_at on public.friend_requests;
create trigger set_updated_at
    before insert or update on public.friend_requests
    for each row execute function public.touch_updated_at();

alter table public.friend_requests enable row level security;
drop policy if exists "requests_select_mine" on public.friend_requests;
create policy "requests_select_mine" on public.friend_requests
    for select to authenticated using (auth.uid() in (requester, addressee));
-- created/resolved only via RPCs.

-- ============================================================================
-- 4. invite_codes  (shareable link/code -> friendship with issuer)
-- ============================================================================
-- Red-team HIGH: single-use by default + short expiry so a leaked/posted code
-- cannot be replayed by a crowd; already-friend redemption is a no-op that does
-- NOT consume a use; blocked/revoked pairs are refused at redeem time.

create table if not exists public.invite_codes (
    code        text        primary key,
    owner       uuid        not null references auth.users(id) on delete cascade,
    active      boolean     not null default true,
    max_uses    int         not null default 1 check (max_uses > 0 and max_uses <= 1000),
    use_count   int         not null default 0,
    expires_at  timestamptz,
    created_at  timestamptz not null default now()
);
create index if not exists invite_codes_owner_idx on public.invite_codes (owner);

alter table public.invite_codes enable row level security;
drop policy if exists "invites_select_own" on public.invite_codes;
create policy "invites_select_own" on public.invite_codes
    for select to authenticated using (owner = auth.uid());
-- issuance/rotation/redemption are RPC-only; no INSERT/UPDATE/DELETE policy.

-- Per-redeemer idempotency: one redemption per (code, redeemer) so use_count
-- reflects DISTINCT redeemers, not call count.
create table if not exists public.invite_redemptions (
    code     text        not null,
    redeemer uuid        not null references auth.users(id) on delete cascade,
    redeemed_at timestamptz not null default now(),
    primary key (code, redeemer)
);
alter table public.invite_redemptions enable row level security; -- internal only

-- ============================================================================
-- 5. daily_totals  (per user PER DEVICE per LOCAL day) — RPC-ONLY WRITES
-- ============================================================================
-- `day` is a bare DATE in the CLIENT's local calendar (matches AppModel's
-- startOfDay bucketing). Server never recomputes it. Table CHECK constraints are
-- the floor of trust even if a policy is ever re-added.
--   * api_value_usd in [0, 100000] and finite (value = value rejects NaN; the
--     upper bound rejects Infinity which would otherwise pass `>= 0`).
--   * tokens in [0, 1e15].

create table if not exists public.daily_totals (
    user_id      uuid        not null default auth.uid()
                             references auth.users(id) on delete cascade,
    device_id    text        not null,
    day          date        not null,
    api_value_usd double precision not null default 0
                  check (api_value_usd >= 0 and api_value_usd <= 100000
                         and api_value_usd = api_value_usd),
    tokens       bigint      not null default 0
                  check (tokens >= 0 and tokens <= 1000000000000000),
    updated_at   timestamptz not null default now(),
    primary key (user_id, device_id, day)
);
create index if not exists daily_totals_day_user_idx
    on public.daily_totals (day, user_id);

drop trigger if exists set_updated_at on public.daily_totals;
create trigger set_updated_at
    before insert or update on public.daily_totals
    for each row execute function public.touch_updated_at();

alter table public.daily_totals enable row level security;

-- The user may READ their own rows (so the client can show its own split); all
-- WRITES go through upsert_daily_total (definer). No insert/update/delete policy.
drop policy if exists "daily_select_own" on public.daily_totals;
create policy "daily_select_own" on public.daily_totals
    for select to authenticated using (user_id = auth.uid());

-- Defensive: revoke any direct DML grants on the table from the client roles.
revoke insert, update, delete on public.daily_totals from authenticated, anon;

-- ============================================================================
-- 6. Internal helpers (SECURITY DEFINER)
-- ============================================================================

create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql security definer set search_path = '' stable as $$
    select exists (
        select 1 from public.friendships
        where user_low = least(a, b) and user_high = greatest(a, b)
    );
$$;

create or replace function public.is_blocked(a uuid, b uuid)
returns boolean
language sql security definer set search_path = '' stable as $$
    select exists (
        select 1 from public.blocks
        where (blocker = a and blocked = b) or (blocker = b and blocked = a)
    );
$$;

-- in-DB rate limiter for handle lookups (red-team MEDIUM enumeration oracle).
create table if not exists public.lookup_attempts (
    user_id      uuid        primary key references auth.users(id) on delete cascade,
    window_start timestamptz not null default now(),
    n            int         not null default 0
);
alter table public.lookup_attempts enable row level security; -- internal only

create or replace function public.note_lookup_attempt(p_uid uuid, p_limit int, p_window interval)
returns void language plpgsql security definer set search_path = '' as $$
begin
    insert into public.lookup_attempts (user_id, window_start, n)
    values (p_uid, now(), 1)
    on conflict (user_id) do update set
        window_start = case when public.lookup_attempts.window_start < now() - p_window
                            then now() else public.lookup_attempts.window_start end,
        n = case when public.lookup_attempts.window_start < now() - p_window
                 then 1 else public.lookup_attempts.n + 1 end;
    if (select n from public.lookup_attempts where user_id = p_uid) > p_limit then
        raise exception 'rate limited' using errcode = '53400';
    end if;
end; $$;

-- ============================================================================
-- 7. RPCs  (all definer, search_path='', auth.uid() asserted, schema-qualified)
-- ============================================================================

-- --- 7.1 claim_handle -------------------------------------------------------
create or replace function public.claim_handle(
    p_handle       text,
    p_display_name text default null,
    p_avatar_url   text default null
) returns public.profiles
language plpgsql security definer set search_path = '' as $$
declare
    uid    uuid := auth.uid();
    norm   text := lower(btrim(p_handle));
    gh     text;
    existing public.profiles;
    row    public.profiles;
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    if norm !~ '^[a-z0-9][a-z0-9_]{2,29}$' then
        raise exception 'invalid handle' using errcode = '22023';
    end if;
    if exists (select 1 from public.reserved_handles where handle_norm = norm) then
        raise exception 'handle reserved' using errcode = '23505';
    end if;
    if exists (select 1 from public.profiles where handle_norm = norm and user_id <> uid) then
        raise exception 'handle taken' using errcode = '23505';
    end if;

    -- Capture GitHub login from the JWT identity (server-trusted; not client text).
    select coalesce(
        u.raw_user_meta_data ->> 'user_name',
        u.raw_user_meta_data ->> 'preferred_username',
        u.raw_user_meta_data ->> 'login')
      into gh
      from auth.users u where u.id = uid;

    select * into existing from public.profiles where user_id = uid;
    -- Rename cooldown: 1 handle change / 7 days (does not apply to first claim).
    if existing.user_id is not null and existing.handle_norm <> norm
       and existing.last_handle_change is not null
       and existing.last_handle_change > now() - interval '7 days' then
        raise exception 'handle changed too recently' using errcode = '55000';
    end if;

    insert into public.profiles
        (user_id, handle, handle_norm, display_name, avatar_url, github_login, last_handle_change)
    values (uid, btrim(p_handle), norm, p_display_name, p_avatar_url, gh, now())
    on conflict (user_id) do update set
        handle             = excluded.handle,
        handle_norm        = excluded.handle_norm,
        display_name       = coalesce(excluded.display_name, public.profiles.display_name),
        avatar_url         = coalesce(excluded.avatar_url, public.profiles.avatar_url),
        github_login       = coalesce(public.profiles.github_login, excluded.github_login),
        last_handle_change = case when public.profiles.handle_norm <> excluded.handle_norm
                                  then now() else public.profiles.last_handle_change end
    returning * into row;
    return row;
exception when unique_violation then
    raise exception 'handle taken' using errcode = '23505';
end; $$;

-- --- 7.2 set_share_preference ----------------------------------------------
create or replace function public.set_share_preference(p_share boolean)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    update public.profiles set share_daily_total = p_share where user_id = uid;
    if not found then raise exception 'no profile: claim a handle first' using errcode = 'P0002'; end if;
    return p_share;
end; $$;

-- --- 7.3 lookup_profile_by_handle  (rate-limited, MINIMAL projection) -------
-- Red-team MEDIUM: per-caller rate limit + return only {user_id, handle}. No
-- avatar/display_name to a non-friend, so a confirmed guess yields just enough
-- to send a request.
create or replace function public.lookup_profile_by_handle(p_handle text)
returns table (user_id uuid, handle text)
language plpgsql security definer set search_path = '' stable as $$
declare
    uid  uuid := auth.uid();
    norm text := lower(btrim(p_handle));
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    if norm !~ '^[a-z0-9][a-z0-9_]{2,29}$' then return; end if;
    perform public.note_lookup_attempt(uid, 30, interval '1 hour');
    return query
        select p.user_id, p.handle
        from public.profiles p
        where p.handle_norm = norm and p.user_id <> uid
        limit 1;
end; $$;

-- --- 7.4 send_friend_request  (no existence oracle, pending cap) ------------
create or replace function public.send_friend_request(p_addressee uuid)
returns public.friend_requests
language plpgsql security definer set search_path = '' as $$
declare
    uid uuid := auth.uid();
    req public.friend_requests;
    rev public.friend_requests;
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    if p_addressee is null or p_addressee = uid then
        raise exception 'invalid request' using errcode = '22023';
    end if;
    if public.is_blocked(uid, p_addressee) then
        raise exception 'cannot send request' using errcode = '42501';
    end if;
    if public.are_friends(uid, p_addressee) then
        raise exception 'already friends' using errcode = '23505';
    end if;
    -- Pending-request spam cap.
    if (select count(*) from public.friend_requests
        where requester = uid and status = 'pending') >= 50 then
        raise exception 'too many pending requests' using errcode = '53400';
    end if;

    -- Reverse pending? auto-accept (both sides opted in).
    select * into rev from public.friend_requests
        where requester = p_addressee and addressee = uid and status = 'pending';
    if found then return public.accept_friend_request(rev.id); end if;

    -- NOTE: no auth.users existence pre-check (removed enumeration oracle). The
    -- addressee FK rejects a dangling UUID uniformly as an insert failure.
    insert into public.friend_requests (requester, addressee)
    values (uid, p_addressee)
    on conflict (requester, addressee) where status = 'pending'
        do update set updated_at = now()
    returning * into req;
    return req;
end; $$;

-- --- 7.5 accept_friend_request ----------------------------------------------
create or replace function public.accept_friend_request(p_request_id uuid)
returns public.friend_requests
language plpgsql security definer set search_path = '' as $$
declare
    uid uuid := auth.uid();
    req public.friend_requests;
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    select * into req from public.friend_requests where id = p_request_id for update;
    if not found then raise exception 'no such request' using errcode = 'P0002'; end if;
    if req.addressee <> uid then raise exception 'not your request to accept' using errcode = '42501'; end if;
    if req.status = 'accepted' and public.are_friends(req.requester, req.addressee) then return req; end if;
    if req.status <> 'pending' then raise exception 'request not pending' using errcode = '22023'; end if;
    if public.is_blocked(req.requester, req.addressee) then
        raise exception 'blocked' using errcode = '42501';
    end if;

    insert into public.friendships (user_low, user_high)
    values (least(req.requester, req.addressee), greatest(req.requester, req.addressee))
    on conflict do nothing;
    -- A fresh accepted friendship clears any stale revocation for the pair.
    delete from public.friendship_revocations
        where user_low = least(req.requester, req.addressee)
          and user_high = greatest(req.requester, req.addressee);

    update public.friend_requests set status = 'accepted'
        where id = p_request_id returning * into req;
    return req;
end; $$;

-- --- 7.6 decline_friend_request ---------------------------------------------
create or replace function public.decline_friend_request(p_request_id uuid)
returns public.friend_requests
language plpgsql security definer set search_path = '' as $$
declare
    uid uuid := auth.uid();
    req public.friend_requests;
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    select * into req from public.friend_requests where id = p_request_id for update;
    if not found then raise exception 'no such request' using errcode = 'P0002'; end if;
    if uid not in (req.requester, req.addressee) then raise exception 'not your request' using errcode = '42501'; end if;
    if req.status <> 'pending' then return req; end if;
    update public.friend_requests
        set status = case when uid = req.addressee then 'declined' else 'cancelled' end
        where id = p_request_id returning * into req;
    return req;
end; $$;

-- --- 7.7 remove_friend / block / unblock ------------------------------------
-- Unfriend records a revocation so a live invite code can't silently re-friend.
create or replace function public.remove_friend(p_other uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    delete from public.friendships
        where user_low = least(uid, p_other) and user_high = greatest(uid, p_other);
    insert into public.friendship_revocations (user_low, user_high)
    values (least(uid, p_other), greatest(uid, p_other))
    on conflict (user_low, user_high) do update set revoked_at = now();
    return true;
end; $$;

create or replace function public.block_user(p_other uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    if p_other = uid then raise exception 'invalid' using errcode = '22023'; end if;
    perform public.remove_friend(p_other);
    insert into public.blocks (blocker, blocked) values (uid, p_other) on conflict do nothing;
    -- cancel any pending requests between the pair
    update public.friend_requests set status = 'cancelled'
        where status = 'pending'
          and ((requester = uid and addressee = p_other) or (requester = p_other and addressee = uid));
    return true;
end; $$;

create or replace function public.unblock_user(p_other uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    delete from public.blocks where blocker = uid and blocked = p_other;
    return true;
end; $$;

-- --- 7.8 create_invite / rotate_invite --------------------------------------
-- Default single-use, 24h expiry (red-team HIGH). Rotate deactivates prior live
-- codes so a leaked old link stops working.
create or replace function public.create_invite(
    p_rotate     boolean default true,
    p_max_uses   int     default 1,
    p_expires_in interval default interval '24 hours'
) returns public.invite_codes
language plpgsql security definer set search_path = '' as $$
declare
    uid  uuid := auth.uid();
    code text;
    row  public.invite_codes;
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    if p_rotate then
        update public.invite_codes set active = false where owner = uid and active;
    end if;
    code := translate(encode(gen_random_bytes(16), 'base64'), '+/=', '-_');
    insert into public.invite_codes (code, owner, max_uses, expires_at)
    values (code, uid, least(greatest(coalesce(p_max_uses,1),1),1000),
            case when p_expires_in is null then null else now() + p_expires_in end)
    returning * into row;
    return row;
end; $$;

create or replace function public.rotate_invite()
returns public.invite_codes
language sql security definer set search_path = '' as $$
    select public.create_invite(true, 1, interval '24 hours');
$$;

-- --- 7.9 redeem_invite  (consent-safe, replay-safe; red-team HIGH) ----------
create or replace function public.redeem_invite(p_code text)
returns table (friend_user_id uuid, friend_handle text, friend_display_name text)
language plpgsql security definer set search_path = '' as $$
declare
    uid uuid := auth.uid();
    inv public.invite_codes;
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    select * into inv from public.invite_codes where code = p_code for update;
    if not found or not inv.active
       or (inv.expires_at is not null and inv.expires_at < now())
       or inv.use_count >= inv.max_uses then
        raise exception 'invalid or expired code' using errcode = 'P0002';
    end if;
    if inv.owner = uid then raise exception 'cannot redeem your own code' using errcode = '22023'; end if;
    if public.is_blocked(uid, inv.owner) then
        raise exception 'invalid or expired code' using errcode = 'P0002';  -- uniform failure
    end if;

    -- Already friends OR already redeemed by this user: no-op that does NOT
    -- consume a use (stops a single attacker burning a code to exhaustion).
    if public.are_friends(uid, inv.owner)
       or exists (select 1 from public.invite_redemptions where code = p_code and redeemer = uid) then
        return query select p.user_id, p.handle, p.display_name
                     from public.profiles p where p.user_id = inv.owner;
        return;
    end if;

    -- If the pair was explicitly torn down (revoked) OR a request was declined,
    -- do NOT auto-friend; route through a fresh pending request the owner taps.
    if exists (select 1 from public.friendship_revocations
               where user_low = least(uid, inv.owner) and user_high = greatest(uid, inv.owner))
       or exists (select 1 from public.friend_requests
               where requester = inv.owner and addressee = uid and status = 'declined') then
        insert into public.friend_requests (requester, addressee)
        values (uid, inv.owner)
        on conflict (requester, addressee) where status = 'pending' do update set updated_at = now();
        insert into public.invite_redemptions (code, redeemer) values (p_code, uid) on conflict do nothing;
        update public.invite_codes set use_count = use_count + 1 where code = p_code;
        -- Return nothing (no instant friendship); client shows "request sent".
        return;
    end if;

    -- Normal path: auto-accept friendship for the issuer<->redeemer pair.
    insert into public.friendships (user_low, user_high)
    values (least(uid, inv.owner), greatest(uid, inv.owner))
    on conflict do nothing;
    update public.friend_requests set status = 'accepted'
        where status = 'pending'
          and ((requester = uid and addressee = inv.owner)
            or (requester = inv.owner and addressee = uid));
    insert into public.invite_redemptions (code, redeemer) values (p_code, uid) on conflict do nothing;
    update public.invite_codes set use_count = use_count + 1 where code = p_code;

    return query select p.user_id, p.handle, p.display_name
                 from public.profiles p where p.user_id = inv.owner;
end; $$;

-- --- 7.10 upsert_daily_total  (THE only write path; all guards here) --------
-- Red-team HIGH self-inflation: bounded value (table CHECK also enforces),
-- bounded day window, device-row cap per (user,day), monotonic greatest() on
-- BOTH branches (no DELETE+INSERT bypass — direct DML is revoked).
create or replace function public.upsert_daily_total(
    p_device_id text,
    p_day       date,
    p_api_value double precision,
    p_tokens    bigint default 0
) returns public.daily_totals
language plpgsql security definer set search_path = '' as $$
declare
    uid uuid := auth.uid();
    row public.daily_totals;
    n   int;
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    if p_device_id is null or length(p_device_id) = 0 or length(p_device_id) > 100 then
        raise exception 'invalid device' using errcode = '22023';
    end if;
    if p_api_value is null or p_api_value < 0 or p_api_value > 100000
       or p_api_value <> p_api_value then               -- rejects NaN/Infinity
        raise exception 'invalid value' using errcode = '22023';
    end if;
    if coalesce(p_tokens,0) < 0 or coalesce(p_tokens,0) > 1000000000000000 then
        raise exception 'invalid tokens' using errcode = '22023';
    end if;
    -- ±1 day window around server UTC date covers all real timezone offsets
    -- while blocking far-past/future stacking and keeping prune effective.
    if p_day < current_date - 2 or p_day > current_date + 1 then
        raise exception 'day out of range' using errcode = '22023';
    end if;
    -- Device-row cap kills the "mint unlimited device_ids" sum amplification.
    if not exists (select 1 from public.daily_totals
                   where user_id = uid and device_id = p_device_id and day = p_day) then
        select count(distinct device_id) into n from public.daily_totals
            where user_id = uid and day = p_day;
        if n >= 25 then raise exception 'too many devices' using errcode = '54000'; end if;
    end if;

    insert into public.daily_totals (user_id, device_id, day, api_value_usd, tokens)
    values (uid, p_device_id, p_day, p_api_value, coalesce(p_tokens,0))
    on conflict (user_id, device_id, day) do update
        set api_value_usd = greatest(public.daily_totals.api_value_usd, excluded.api_value_usd),
            tokens        = greatest(public.daily_totals.tokens, excluded.tokens)
    returning * into row;
    return row;
end; $$;

-- --- 7.11 leaderboard_for_day  (friends-only aggregate; plpgsql guard) ------
-- Red-team LOW: explicit auth.uid() assertion (not a trailing WHERE). Returns
-- caller + accepted friends with sharing ON, one aggregated row each. Self
-- always included. Idle-but-sharing friends are included with 0 (product choice:
-- show everyone you're friends with) — see securityResolution for the tradeoff.
create or replace function public.leaderboard_for_day(p_day date)
returns table (
    user_id       uuid,
    handle        text,
    display_name  text,
    avatar_url    text,
    api_value_usd double precision,
    tokens        bigint,
    is_self       boolean
)
language plpgsql security definer set search_path = '' stable as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    return query
    with visible as (
        select uid as vid, true as is_self
        union
        select case when f.user_low = uid then f.user_high else f.user_low end, false
        from public.friendships f
        where uid in (f.user_low, f.user_high)
    ),
    eligible as (
        select v.vid, v.is_self
        from visible v
        left join public.profiles p on p.user_id = v.vid
        where v.is_self or coalesce(p.share_daily_total, false) = true
    ),
    totals as (
        select d.user_id,
               least(sum(d.api_value_usd), 100000)::double precision as api_value_usd,
               sum(d.tokens)::bigint as tokens
        from public.daily_totals d
        join eligible e on e.vid = d.user_id
        where d.day = p_day
        group by d.user_id
    )
    select e.vid, pr.handle, pr.display_name, pr.avatar_url,
           coalesce(t.api_value_usd, 0), coalesce(t.tokens, 0), e.is_self
    from eligible e
    left join public.profiles pr on pr.user_id = e.vid
    left join totals t on t.user_id = e.vid
    order by coalesce(t.api_value_usd, 0) desc,
             coalesce(t.tokens, 0) desc,
             pr.handle asc nulls last,
             e.vid asc;                              -- deterministic tiebreak
end; $$;

-- --- 7.12 list_friends  (friendship-gated read of friends' display info) -----
-- profiles has NO cross-user SELECT, so the caller's accepted friends' handles
-- are surfaced ONLY here, and ONLY for users who are actually friends with the
-- caller. `sharing` lets the UI mark a friend who has hidden their daily number.
create or replace function public.list_friends()
returns table (user_id uuid, handle text, display_name text, avatar_url text,
               sharing boolean, befriended_at timestamptz)
language plpgsql security definer set search_path = '' stable as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    return query
        select fr.fid, p.handle, p.display_name, p.avatar_url,
               coalesce(p.share_daily_total, false), fr.created_at
        from (
            select case when f.user_low = uid then f.user_high else f.user_low end as fid,
                   f.created_at
            from public.friendships f
            where uid in (f.user_low, f.user_high)
        ) fr
        left join public.profiles p on p.user_id = fr.fid
        order by p.handle asc nulls last;
end; $$;

-- --- 7.13 list_requests  (pending requests both directions, gated) ----------
-- Returns only the caller's own pending requests, joining the counterparty's
-- minimal profile (definer, since profiles has no cross-user SELECT).
create or replace function public.list_requests()
returns table (request_id uuid, other_user_id uuid, handle text,
               display_name text, direction text, created_at timestamptz)
language plpgsql security definer set search_path = '' stable as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
    return query
        select r.id,
               case when r.requester = uid then r.addressee else r.requester end,
               p.handle, p.display_name,
               case when r.requester = uid then 'outgoing' else 'incoming' end,
               r.created_at
        from public.friend_requests r
        left join public.profiles p
               on p.user_id = case when r.requester = uid then r.addressee else r.requester end
        where r.status = 'pending' and uid in (r.requester, r.addressee)
        order by r.created_at desc;
end; $$;

-- ============================================================================
-- 8. Grants
-- ============================================================================
revoke all on function
    public.are_friends(uuid, uuid),
    public.is_blocked(uuid, uuid),
    public.note_lookup_attempt(uuid, int, interval),
    public.claim_handle(text, text, text),
    public.set_share_preference(boolean),
    public.lookup_profile_by_handle(text),
    public.send_friend_request(uuid),
    public.accept_friend_request(uuid),
    public.decline_friend_request(uuid),
    public.remove_friend(uuid),
    public.block_user(uuid),
    public.unblock_user(uuid),
    public.create_invite(boolean, int, interval),
    public.rotate_invite(),
    public.redeem_invite(text),
    public.upsert_daily_total(text, date, double precision, bigint),
    public.leaderboard_for_day(date),
    public.list_friends(),
    public.list_requests()
    from public, anon;

grant execute on function
    public.claim_handle(text, text, text),
    public.set_share_preference(boolean),
    public.lookup_profile_by_handle(text),
    public.send_friend_request(uuid),
    public.accept_friend_request(uuid),
    public.decline_friend_request(uuid),
    public.remove_friend(uuid),
    public.block_user(uuid),
    public.unblock_user(uuid),
    public.create_invite(boolean, int, interval),
    public.rotate_invite(),
    public.redeem_invite(text),
    public.upsert_daily_total(text, date, double precision, bigint),
    public.leaderboard_for_day(date),
    public.list_friends(),
    public.list_requests()
    to authenticated;
-- are_friends / is_blocked / note_lookup_attempt are internal helpers; not granted.

-- ============================================================================
-- 9. Retention
-- ============================================================================
create or replace function public.prune_daily_totals(p_keep_days int default 60)
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
    delete from public.daily_totals where day < (current_date - make_interval(days => p_keep_days));
    get diagnostics n = row_count;
    return n;
end; $$;
revoke all on function public.prune_daily_totals(int) from public, anon, authenticated;
-- If pg_cron is enabled:
-- select cron.schedule('prune_daily_totals','0 4 * * *', $$ select public.prune_daily_totals(60); $$);

-- ============================================================================
-- 10. Realtime (own-row live refresh only; cross-user reads use the RPC).
-- ============================================================================
alter table public.daily_totals replica identity full;
do $$ begin
    alter publication supabase_realtime add table public.daily_totals;
exception when duplicate_object then null; end $$;
