-- IronLens — Supabase schema
-- Run in Supabase SQL Editor. auth.users is managed by Supabase Auth.

-- ── Profiles ─────────────────────────────────────────────────────────────────
create table public.profiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  name           text not null,
  weight_kg      float,
  height_cm      float,
  goal           text check (goal in ('strength', 'hypertrophy', 'endurance', 'general')),
  training_days  text[] default array['monday','wednesday','friday'],
  medical_notes  text,
  created_at     timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Users manage own profile"
  on public.profiles for all
  using (auth.uid() = id);

-- ── Machines (catalog, seeded manually) ──────────────────────────────────────
create table public.machines (
  id                           serial primary key,
  name                         text not null unique,
  muscle_group                 text not null,
  description                  text,
  is_default                   boolean default false,
  baseline_1rm_kg              float,
  base_recommended_weight_kg   float
);

-- No RLS — public read, no user writes
alter table public.machines enable row level security;

create policy "Public read machines"
  on public.machines for select
  using (true);

-- ── Scanned machines (user collection) ───────────────────────────────────────
create table public.scanned_machines (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  machine_id  int  not null references public.machines (id),
  scanned_at  timestamptz default now(),
  unique (user_id, machine_id)
);

alter table public.scanned_machines enable row level security;

create policy "Users manage own scanned machines"
  on public.scanned_machines for all
  using (auth.uid() = user_id);

-- ── Workout sessions ──────────────────────────────────────────────────────────
create table public.workout_sessions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  machine_id  int  not null references public.machines (id),
  started_at  timestamptz default now(),
  ended_at    timestamptz                -- null = session still active
);

alter table public.workout_sessions enable row level security;

create policy "Users manage own sessions"
  on public.workout_sessions for all
  using (auth.uid() = user_id);

-- ── Routines (one active per user, regenerated weekly) ───────────────────────
create table public.routines (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade unique,
  week_start  date not null,
  created_at  timestamptz default now()
);

alter table public.routines enable row level security;

create policy "Users manage own routine"
  on public.routines for all
  using (auth.uid() = user_id);

create table public.routine_days (
  id             uuid primary key default gen_random_uuid(),
  routine_id     uuid not null references public.routines (id) on delete cascade,
  day_of_week    text not null,
  day_label      text not null,
  order_index    int  not null,
  scheduled_date date  -- routines.week_start + weekday offset; drives done/today/missed/upcoming status
);

alter table public.routine_days enable row level security;

create policy "Users manage own routine days"
  on public.routine_days for all
  using (
    auth.uid() = (select user_id from public.routines where id = routine_id)
  );

create table public.routine_exercises (
  id                   uuid primary key default gen_random_uuid(),
  routine_day_id       uuid not null references public.routine_days (id) on delete cascade,
  machine_id           int  not null references public.machines (id),
  sets                 int  not null,
  reps_range           text not null,
  suggested_weight_kg  float,
  order_index          int  not null
);

alter table public.routine_exercises enable row level security;

create policy "Users manage own routine exercises"
  on public.routine_exercises for all
  using (
    auth.uid() = (
      select r.user_id from public.routines r
      join public.routine_days rd on rd.routine_id = r.id
      where rd.id = routine_day_id
    )
  );

-- ── AI recommendations (weekly, per machine) ─────────────────────────────────
create table public.ai_recommendations (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  machine_id   int  not null references public.machines (id),
  week_start   date not null,
  content      text not null,
  generated_at timestamptz default now(),
  unique (user_id, machine_id, week_start)
);

alter table public.ai_recommendations enable row level security;

create policy "Users manage own recommendations"
  on public.ai_recommendations for all
  using (auth.uid() = user_id);

-- ── Routine execution logs ───────────────────────────────────────────────────
create table public.routine_logs (
  id             uuid primary key default gen_random_uuid(),
  routine_id     uuid not null references public.routines (id) on delete cascade,
  user_id        uuid not null references auth.users (id) on delete cascade,
  routine_day_id uuid not null references public.routine_days (id),
  started_at     timestamptz default now(),
  ended_at       timestamptz,
  completed_pct  float
);

alter table public.routine_logs enable row level security;

create policy "Users manage own routine logs"
  on public.routine_logs for all
  using (auth.uid() = user_id);

create table public.routine_log_items (
  id                  uuid primary key default gen_random_uuid(),
  routine_log_id      uuid not null references public.routine_logs (id) on delete cascade,
  routine_exercise_id uuid not null references public.routine_exercises (id),
  session_id          uuid references public.workout_sessions (id) on delete set null,
  status              text check (status in ('pending', 'done', 'skipped')) default 'pending'
);
-- session_id: on delete set null (not cascade) — deleting the underlying
-- session must not un-mark a completed exercise; the 'done'/'skipped'
-- status here is the source of truth for routine completion, independent
-- of whether the linked session still exists.

alter table public.routine_log_items enable row level security;

create policy "Users manage own routine log items"
  on public.routine_log_items for all
  using (
    auth.uid() = (
      select user_id from public.routine_logs where id = routine_log_id
    )
  );

-- ── Weight logs (user body weight history) ───────────────────────────────────
create table public.weight_logs (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  weight_kg  float not null,
  logged_at  timestamptz default now()
);

alter table public.weight_logs enable row level security;

create policy "Users manage own weight logs"
  on public.weight_logs for all
  using (auth.uid() = user_id);

-- ── User machine stats (weight guidance, refreshed weekly) ───────────────────
create table public.user_machine_stats (
  user_id               uuid not null references auth.users (id) on delete cascade,
  machine_id            int  not null references public.machines (id) on delete cascade,
  recommended_weight_kg float,
  safe_max_weight_kg    float,
  computed_at           timestamptz not null default now(),
  primary key (user_id, machine_id)
);

alter table public.user_machine_stats enable row level security;

create policy "Users manage own machine stats"
  on public.user_machine_stats for all
  using (auth.uid() = user_id);

-- ── Workout sets ──────────────────────────────────────────────────────────────
create table public.workout_sets (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid  not null references public.workout_sessions (id) on delete cascade,
  machine_id  int   not null references public.machines (id),
  set_number  int   not null,
  reps        int   not null,
  weight_kg   float,                        -- null = bodyweight
  logged_at   timestamptz default now()
);

alter table public.workout_sets enable row level security;

create policy "Users manage own sets"
  on public.workout_sets for all
  using (
    auth.uid() = (
      select user_id from public.workout_sessions
      where id = session_id
    )
  );
