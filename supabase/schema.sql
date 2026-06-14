-- Tokenholic cross-device sync schema.
-- Run as-is in the Supabase dashboard → SQL Editor.
--
-- One row per (user, device). Each device upserts ONLY its own row
-- (single-writer); every device reads all of the signed-in user's rows and
-- aggregates client-side, subtracting the subscription once.

create table if not exists public.device_snapshots (
    user_id       uuid        not null default auth.uid() references auth.users(id) on delete cascade,
    device_id     text        not null,
    device_name   text        not null,
    platform      text,
    app_version   text,
    schema_version int        not null default 1,
    window_start  timestamptz,
    -- tools: JSON array of DeviceToolTotal
    -- [{ "tool":"claudeCode", "apiCostUSD":12.3, "inputTokens":...,
    --    "outputTokens":..., "cacheReadTokens":..., "cacheWriteTokens":...,
    --    "recordCount":... }, ...]
    tools         jsonb       not null default '[]'::jsonb,
    updated_at    timestamptz not null default now(),
    primary key (user_id, device_id)
);

create index if not exists device_snapshots_user_idx
    on public.device_snapshots (user_id);

-- Server-stamp updated_at so a client cannot push a stale/forged freshness value.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end; $$;

drop trigger if exists set_updated_at on public.device_snapshots;
create trigger set_updated_at
    before insert or update on public.device_snapshots
    for each row execute function public.touch_updated_at();

-- Row-Level Security: a user only ever sees/writes their own rows; anon sees none.
alter table public.device_snapshots enable row level security;

create policy "select_own" on public.device_snapshots
    for select to authenticated using (user_id = auth.uid());

create policy "insert_own" on public.device_snapshots
    for insert to authenticated with check (user_id = auth.uid());

-- UPDATE needs both: `using` hides other users' rows; `with check` blocks
-- reassigning ownership to another user.
create policy "update_own" on public.device_snapshots
    for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "delete_own" on public.device_snapshots
    for delete to authenticated using (user_id = auth.uid());

-- Optional: Realtime (a future Tokenholic version can subscribe for live updates).
-- Realtime respects RLS, so events only flow for the user's own rows.
alter table public.device_snapshots replica identity full;
alter publication supabase_realtime add table public.device_snapshots;
