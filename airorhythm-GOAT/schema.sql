-- =============================================================================
--  AiroRhythm — Postgres schema + Row Level Security (Supabase)
--  Target: the real backend behind DeviceRepository / AuthService.
--  Run in the Supabase SQL editor (or as a migration) BEFORE pointing the app at it.
-- =============================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- profiles (optional; Supabase auth.users is the identity source)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  created_at  timestamptz not null default now()
);
alter table public.profiles enable row level security;

create policy "profiles: read own"
  on public.profiles for select using (auth.uid() = id);
create policy "profiles: insert own"
  on public.profiles for insert with check (auth.uid() = id);
create policy "profiles: update own"
  on public.profiles for update using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- devices
-- ---------------------------------------------------------------------------
create table if not exists public.devices (
  id            uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  name          text not null check (char_length(name) between 2 and 60),
  room          text not null default '',
  device_type   text not null check (device_type in ('virtual', 'physical')),
  capabilities  jsonb not null default '{}'::jsonb,
  firmware      text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists devices_owner_idx on public.devices (owner_user_id);

-- ---------------------------------------------------------------------------
-- device_memberships  (owner | controller | viewer)
-- ---------------------------------------------------------------------------
create table if not exists public.device_memberships (
  id          uuid primary key default gen_random_uuid(),
  device_id   uuid not null references public.devices (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  role        text not null check (role in ('owner', 'controller', 'viewer')),
  granted_via text not null default 'created',   -- created | pairing-code
  created_at  timestamptz not null default now(),
  unique (device_id, user_id)
);
create index if not exists device_memberships_user_idx on public.device_memberships (user_id);

-- ---------------------------------------------------------------------------
-- device_state  (desired vs reported, revision for stale-update rejection)
-- ---------------------------------------------------------------------------
create table if not exists public.device_state (
  device_id     uuid primary key references public.devices (id) on delete cascade,
  power         text not null default 'off' check (power in ('on', 'off', 'unknown')),
  speed         int check (speed is null or (speed between 0 and 100)),
  mode          text not null default 'manual' check (mode in ('manual', 'automatic')),
  desired_power text check (desired_power in ('on', 'off')),
  desired_speed int check (desired_speed is null or (desired_speed between 0 and 100)),
  desired_mode  text check (desired_mode in ('manual', 'automatic')),
  on_threshold      numeric(5, 2) not null default 70,
  off_threshold     numeric(5, 2) not null default 60,
  min_dwell_seconds int not null default 20,
  last_switch_at    timestamptz,
  revision      bigint not null default 1,
  updated_at    timestamptz not null default now(),
  constraint thresholds_valid check (off_threshold < on_threshold)
);

-- ---------------------------------------------------------------------------
-- device_readings  (latest telemetry per device; history table is separate)
-- ---------------------------------------------------------------------------
create table if not exists public.device_readings (
  device_id            uuid primary key references public.devices (id) on delete cascade,
  humidity_percent     numeric(5, 2),   -- monitored parameter #1
  smoke_index          numeric(5, 2),   -- monitored parameter #2, 0..100
  load_percent         numeric(5, 2),   -- fan resistance from dust/debris, 0..100
  actual_speed_percent numeric(5, 2),   -- achieved speed after resistance losses
  source               text not null check (source in ('simulated', 'physical')),
  sensor_health        text not null default 'ok',
  observed_at          timestamptz
);

-- Bounded telemetry history (keep 7 days: drop via pg_cron or an edge function).
create table if not exists public.device_telemetry (
  id                   bigserial primary key,
  device_id            uuid not null references public.devices (id) on delete cascade,
  humidity_percent     numeric(5, 2),
  smoke_index          numeric(5, 2),
  load_percent         numeric(5, 2),
  actual_speed_percent numeric(5, 2),
  source               text not null check (source in ('simulated', 'physical')),
  observed_at          timestamptz not null default now()
);
create index if not exists telemetry_device_time_idx
  on public.device_telemetry (device_id, observed_at desc);

-- ---------------------------------------------------------------------------
-- pairing_codes  (hash only — never the raw code)
-- ---------------------------------------------------------------------------
create table if not exists public.pairing_codes (
  id            uuid primary key default gen_random_uuid(),
  device_id     uuid not null references public.devices (id) on delete cascade,
  code_hash     text not null,
  salt          text not null,
  grants_role   text not null default 'controller'
                  check (grants_role in ('controller', 'viewer', 'owner')),
  created_by    uuid not null references auth.users (id) on delete cascade,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  max_attempts  int not null default 5,
  attempts      int not null default 0,
  consumed_at   timestamptz,
  consumed_by   uuid
);
create index if not exists pairing_codes_device_idx on public.pairing_codes (device_id);
-- No SELECT policy: codes are never readable by clients.

-- ---------------------------------------------------------------------------
-- device_events  (bounded activity history)
-- ---------------------------------------------------------------------------
create table if not exists public.device_events (
  id         bigserial primary key,
  device_id  uuid not null references public.devices (id) on delete cascade,
  kind       text not null check (kind in ('command', 'state', 'pairing', 'membership', 'system')),
  message    text not null,
  actor      text not null default '',
  ok         boolean not null default true,
  at         timestamptz not null default now()
);
create index if not exists device_events_device_time_idx
  on public.device_events (device_id, at desc);

-- =============================================================================
--  ROW LEVEL SECURITY
-- =============================================================================
alter table public.devices            enable row level security;
alter table public.device_memberships enable row level security;
alter table public.device_state       enable row level security;
alter table public.device_readings    enable row level security;
alter table public.device_telemetry   enable row level security;
alter table public.pairing_codes      enable row level security;
alter table public.device_events      enable row level security;

-- helper: is the current user a member of this device?
create or replace function public.is_device_member(_device_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.device_memberships m
    where m.device_id = _device_id and m.user_id = auth.uid()
  );
$$;

create or replace function public.device_role(_device_id uuid)
returns text
language sql stable security definer set search_path = public as $$
  select m.role from public.device_memberships m
  where m.device_id = _device_id and m.user_id = auth.uid();
$$;

-- devices: members read; only owner updates/deletes; any authenticated user may create
create policy "devices: members read"
  on public.devices for select using (public.is_device_member(id));
create policy "devices: create own"
  on public.devices for insert with check (auth.uid() = owner_user_id);
create policy "devices: owner update"
  on public.devices for update using (public.device_role(id) = 'owner');
create policy "devices: owner delete"
  on public.devices for delete using (public.device_role(id) = 'owner');

-- memberships: members see who has access; only owners manage rows.
create policy "memberships: members read"
  on public.device_memberships for select using (public.is_device_member(device_id));
-- NOTE: no INSERT/UPDATE policy — membership is granted only by the pairing function
-- (security definer) or by the device-creation trigger. Users cannot grant themselves access.
create policy "memberships: owner revoke"
  on public.device_memberships for delete
  using (public.device_role(device_id) = 'owner' and role <> 'owner');

-- state: members read; owner + controller write
create policy "state: members read"
  on public.device_state for select using (public.is_device_member(device_id));
create policy "state: controller write"
  on public.device_state for update
  using (public.device_role(device_id) in ('owner', 'controller'));
create policy "state: controller insert"
  on public.device_state for insert
  with check (public.device_role(device_id) in ('owner', 'controller'));

-- readings / telemetry / events: members read, writes come from the trusted service
create policy "readings: members read"
  on public.device_readings for select using (public.is_device_member(device_id));
create policy "telemetry: members read"
  on public.device_telemetry for select using (public.is_device_member(device_id));
create policy "events: members read"
  on public.device_events for select using (public.is_device_member(device_id));

-- =============================================================================
--  PAIRING (server-side, security definer)
-- =============================================================================
-- Issue a code. Returns the RAW code once; only the hash is stored.
create or replace function public.create_pairing_code(
  _device_id uuid,
  _ttl_seconds int default 180,
  _grants_role text default 'controller'
) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_code  text;
  v_salt  text;
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i       int;
begin
  if public.device_role(_device_id) not in ('owner', 'controller') then
    raise exception 'not allowed to issue a code for this device';
  end if;

  -- one live code per device
  update public.pairing_codes
     set consumed_at = now()
   where device_id = _device_id and consumed_at is null;

  v_code := '';
  for i in 1..6 loop
    v_code := v_code || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
  end loop;
  v_salt := encode(extensions.gen_random_bytes(16), 'hex');

  insert into public.pairing_codes (device_id, code_hash, salt, grants_role, created_by, expires_at)
  values (_device_id, encode(extensions.digest(v_salt || ':' || v_code, 'sha256'), 'hex'),
          v_salt, _grants_role, auth.uid(), now() + (_ttl_seconds || ' seconds')::interval);

  return v_code;
end;
$$;

-- Redeem a code: hash comparison + expiry + single-use consumption happen in one statement,
-- so two concurrent redemptions cannot both succeed.
create or replace function public.redeem_pairing_code(_code text)
returns table (device_id uuid, role text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_clean text := upper(regexp_replace(coalesce(_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_rec   public.pairing_codes;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if length(v_clean) <> 6 then
    raise exception 'invalid code';
  end if;

  -- count attempts on live codes, then find a match
  update public.pairing_codes
     set attempts = attempts + 1
   where consumed_at is null and expires_at > now();

  select * into v_rec
    from public.pairing_codes c
   where c.consumed_at is null
     and c.expires_at > now()
     and c.attempts <= c.max_attempts
     and c.code_hash = encode(extensions.digest(c.salt || ':' || v_clean, 'sha256'), 'hex')
   order by c.created_at desc
   limit 1;

  if v_rec.id is null then
    raise exception 'invalid, expired or already used code';
  end if;

  -- atomic single-use consumption
  update public.pairing_codes
     set consumed_at = now(), consumed_by = auth.uid()
   where id = v_rec.id and consumed_at is null;

  if not found then
    raise exception 'code already used';
  end if;

  insert into public.device_memberships (device_id, user_id, role, granted_via)
  values (v_rec.device_id, auth.uid(), v_rec.grants_role, 'pairing-code')
  on conflict (device_id, user_id) do nothing;

  insert into public.device_events (device_id, kind, message, actor)
  values (v_rec.device_id, 'pairing', 'Paired via code as ' || v_rec.grants_role, auth.uid()::text);

  return query select v_rec.device_id, v_rec.grants_role;
end;
$$;

-- =============================================================================
--  Housekeeping: create state + membership rows for new devices
-- =============================================================================
create or replace function public.after_device_insert()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.device_memberships (device_id, user_id, role, granted_via)
  values (new.id, new.owner_user_id, 'owner', 'created');

  insert into public.device_state (device_id, power, speed)
  values (new.id, 'off', case when (new.capabilities ->> 'speedControl')::bool then 60 end);

  insert into public.device_readings (device_id, source)
  values (new.id, case when new.device_type = 'virtual' then 'simulated' else 'physical' end);

  insert into public.device_events (device_id, kind, message)
  values (new.id, 'system', 'Device created (' || new.device_type || ')');
  return new;
end;
$$;

drop trigger if exists devices_after_insert on public.devices;
create trigger devices_after_insert
  after insert on public.devices
  for each row execute function public.after_device_insert();

-- =============================================================================
--  Realtime: publish only state/readings/events changes; RLS applies to channels.
-- =============================================================================
alter publication supabase_realtime add table public.device_state;
alter publication supabase_realtime add table public.device_readings;
alter publication supabase_realtime add table public.device_events;

-- Retention: keep 7 days of telemetry (requires pg_cron).
-- select cron.schedule('prune-telemetry', '0 3 * * *',
--   $$delete from public.device_telemetry where observed_at < now() - interval '7 days'$$);
