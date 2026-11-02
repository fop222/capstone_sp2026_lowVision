-- Run this in the Supabase SQL Editor (Dashboard → SQL) to turn on
-- dining scan history and "Report incorrect result".
--
-- Safe to run more than once; uses IF NOT EXISTS / DROP ... IF EXISTS.

-- ── Scan history ────────────────────────────────────────────────────────────
-- One row per finished dining scan. `foods` holds each food the scan found
-- (name, location, allergens, dietary preferences, confidence, source).
create table if not exists public.dining_scans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  food_count integer not null default 0,
  foods jsonb not null default '[]'::jsonb
);

create index if not exists dining_scans_user_created_idx
  on public.dining_scans (user_id, created_at desc);

alter table public.dining_scans enable row level security;

drop policy if exists "Users read own dining scans" on public.dining_scans;
create policy "Users read own dining scans" on public.dining_scans
  for select using (auth.uid() = user_id);

drop policy if exists "Users add own dining scans" on public.dining_scans;
create policy "Users add own dining scans" on public.dining_scans
  for insert with check (auth.uid() = user_id);

drop policy if exists "Users delete own dining scans" on public.dining_scans;
create policy "Users delete own dining scans" on public.dining_scans
  for delete using (auth.uid() = user_id);

-- ── Reports of incorrect results ────────────────────────────────────────────
-- One row each time a user taps "Report incorrect result" on a food.
-- Browse them in Table Editor → dining_reports (the dashboard sees every
-- row; users can only add their own).
create table if not exists public.dining_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  scan_id uuid references public.dining_scans (id) on delete set null,
  dish_name text not null,
  location text not null default '',
  problems text[] not null default '{}',
  note text not null default '',
  food jsonb not null default '{}'::jsonb
);

create index if not exists dining_reports_created_idx
  on public.dining_reports (created_at desc);

alter table public.dining_reports enable row level security;

drop policy if exists "Users add own dining reports" on public.dining_reports;
create policy "Users add own dining reports" on public.dining_reports
  for insert with check (auth.uid() = user_id);

drop policy if exists "Users read own dining reports" on public.dining_reports;
create policy "Users read own dining reports" on public.dining_reports
  for select using (auth.uid() = user_id);
