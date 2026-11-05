-- Glass Symphony, phase 1: players, runs and leaderboards.
--
-- Clients never touch the tables. Row level security is on with no policies, and every read or
-- write goes through the security-definer functions below, which check the caller (auth.uid())
-- and the data. Players are Supabase anonymous users: no email needed.

-- ---------------------------------------------------------------- tables
create table public.players (
  id          uuid primary key references auth.users (id) on delete cascade,
  nickname    text,
  country     text check (country ~ '^[A-Z]{2}$'),
  created_at  timestamptz not null default now(),
  nickname_at timestamptz,          -- last nickname change (once a week)
  country_at  timestamptz,          -- last country change (once every 30 days)
  banned      boolean not null default false
);
create unique index players_nickname_key on public.players (lower(nickname));

create table public.runs (
  id             uuid primary key default gen_random_uuid(),
  player_id      uuid not null references public.players (id) on delete cascade,
  field          text not null check (field in ('classic', 'storm', 'rush', 'abyss')),
  started_at     timestamptz not null default now(),   -- server clock, not the phone's
  submitted_at   timestamptz,
  score          integer,
  duration_ms    integer,
  breaks         integer,
  max_combo      integer,
  client_version text,
  summary        jsonb,
  status         text not null default 'open' check (status in ('open', 'accepted', 'review', 'rejected')),
  flags          text[] not null default '{}'
);
create index runs_board_idx  on public.runs (field, status, score desc);
create index runs_player_idx on public.runs (player_id, started_at desc);

create table public.reports (
  reporter   uuid not null references public.players (id) on delete cascade,
  target     uuid not null references public.players (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reporter, target)
);

alter table public.players enable row level security;
alter table public.runs    enable row level security;
alter table public.reports enable row level security;
revoke all on public.players, public.runs, public.reports from anon, authenticated;

-- ---------------------------------------------------------------- helpers
-- Week boards run Monday 00:00 to Sunday 23:59, Finnish time.
create function public.gs_week_start() returns timestamptz
language sql stable set search_path = '' as $$
  select (date_trunc('week', now() at time zone 'Europe/Helsinki')) at time zone 'Europe/Helsinki'
$$;

create function public.gs_require_player() returns public.players
language plpgsql security definer set search_path = '' as $$
declare p public.players;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  insert into public.players (id) values (auth.uid()) on conflict (id) do nothing;
  select * into p from public.players where id = auth.uid();
  if p.banned then raise exception 'banned'; end if;
  return p;
end $$;

-- nickname rules: 3 to 16 letters, digits, space, _ . -; no edge spaces; no slurs or staff names
create function public.gs_nickname_problem(n text) returns text
language plpgsql immutable set search_path = '' as $$
declare l text := lower(n); w text;
begin
  if n is null or char_length(n) < 3 or char_length(n) > 16 then return 'nickname_length'; end if;
  if n <> btrim(n) or n ~ '  ' then return 'nickname_chars'; end if;
  if n !~ '^[[:alnum:]_ .-]+$' then return 'nickname_chars'; end if;
  foreach w in array array['fuck', 'shit', 'cunt', 'nigg', 'fagg', 'hitler', 'nazi', 'rape', 'porn',
    'vittu', 'huora', 'kyrpä', 'kyrpa', 'mulkku', 'kusipää', 'kusipaa', 'neekeri', 'paska', 'perse',
    'admin', 'moderator', 'glasssymphony', 'glass symphony'] loop
    if position(w in l) > 0 then return 'nickname_blocked'; end if;
  end loop;
  return null;
end $$;

-- best accepted score per player on one field, optionally since a time
create function public.gs_bests(p_field text, p_since timestamptz)
returns table (player_id uuid, nickname text, country text, score integer)
language sql stable security definer set search_path = '' as $$
  select r.player_id, p.nickname, p.country, max(r.score)
  from public.runs r join public.players p on p.id = r.player_id
  where r.field = p_field and r.status = 'accepted' and not p.banned and p.nickname is not null
    and (p_since is null or r.submitted_at >= p_since)
  group by r.player_id, p.nickname, p.country
$$;

-- ---------------------------------------------------------------- API (called by the game)
create function public.gs_me() returns json
language plpgsql security definer set search_path = '' as $$
declare p public.players := public.gs_require_player();
begin
  return json_build_object('id', p.id, 'nickname', p.nickname, 'country', p.country,
    'nickname_next', case when p.nickname_at is null then null else p.nickname_at + interval '7 days' end,
    'country_next',  case when p.country_at  is null then null else p.country_at  + interval '30 days' end);
end $$;

create function public.gs_set_profile(p_nickname text, p_country text) returns json
language plpgsql security definer set search_path = '' as $$
declare p public.players := public.gs_require_player(); problem text; c text := upper(p_country);
begin
  if p_nickname is not null and p_nickname is distinct from p.nickname then
    problem := public.gs_nickname_problem(p_nickname);
    if problem is not null then raise exception '%', problem; end if;
    -- a case-only fix ("joel" -> "Joel") is always allowed
    if p.nickname_at is not null and lower(p_nickname) <> lower(p.nickname)
       and p.nickname_at > now() - interval '7 days' then raise exception 'nickname_too_soon'; end if;
    begin
      update public.players set nickname = p_nickname, nickname_at = now() where id = p.id;
    exception when unique_violation then raise exception 'nickname_taken';
    end;
  end if;
  if c is not null and c is distinct from p.country then
    if c !~ '^[A-Z]{2}$' then raise exception 'country_invalid'; end if;
    if p.country_at is not null and p.country_at > now() - interval '30 days' then raise exception 'country_too_soon'; end if;
    update public.players set country = c, country_at = now() where id = p.id;
  end if;
  return public.gs_me();
end $$;

-- A run must be started on the server: its clock, not the phone's, bounds how long it lasted.
-- A player without a nickname may play ranked runs too: they show on the boards once a nickname is set.
create function public.gs_start_run(p_field text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare p public.players := public.gs_require_player(); rid uuid;
begin
  if p_field not in ('classic', 'storm', 'rush', 'abyss') then raise exception 'field_invalid'; end if;
  if (select count(*) from public.runs where player_id = p.id and started_at > now() - interval '1 hour') >= 120 then
    raise exception 'rate_limited';
  end if;
  insert into public.runs (player_id, field) values (p.id, p_field) returning id into rid;
  return rid;
end $$;

-- Plausibility limits come from the game's own rules: at most about 5 glass a second, and even
-- with the best multipliers and chains a glass is worth well under 1 000 points. A score rate
-- above REVIEW_RATE waits for a person; above REJECT_RATE it is impossible.
create function public.gs_submit_run(p_run uuid, p_score integer, p_duration_ms integer, p_breaks integer,
  p_max_combo integer, p_version text, p_summary jsonb default null) returns json
language plpgsql security definer set search_path = '' as $$
declare
  REVIEW_RATE constant numeric := 1500;  -- points per second
  REJECT_RATE constant numeric := 6000;
  p public.players := public.gs_require_player();
  r public.runs; elapsed_ms bigint; secs numeric; st text := 'accepted'; fl text[] := '{}';
  my_best integer; wk timestamptz := public.gs_week_start();
  world_rank integer; country_rank integer; week_rank integer;
begin
  select * into r from public.runs where id = p_run and player_id = p.id for update;
  if not found then raise exception 'run_unknown'; end if;
  if r.status <> 'open' then raise exception 'run_used'; end if;
  if r.started_at < now() - interval '3 hours' then raise exception 'run_expired'; end if;
  if p_score is null or p_score < 0 or p_duration_ms is null or p_duration_ms < 0
     or coalesce(p_breaks, 0) < 0 or coalesce(p_max_combo, 0) < 0 then raise exception 'bad_values'; end if;
  if p_summary is not null and length(p_summary::text) > 4000 then raise exception 'summary_too_big'; end if;

  elapsed_ms := (extract(epoch from now() - r.started_at) * 1000)::bigint;
  if p_duration_ms > elapsed_ms + 5000 then fl := array_append(fl, 'duration'); st := 'rejected'; end if;
  secs := greatest(p_duration_ms / 1000.0, 5);
  if p_score / secs > REJECT_RATE then fl := array_append(fl, 'rate'); st := 'rejected';
  elsif p_score / secs > REVIEW_RATE and st = 'accepted' then fl := array_append(fl, 'rate'); st := 'review'; end if;
  if coalesce(p_breaks, 0) > secs * 10 + 20 then fl := array_append(fl, 'breaks'); st := 'rejected'; end if;
  if coalesce(p_max_combo, 0) > coalesce(p_breaks, 0) + 1 then fl := array_append(fl, 'combo'); st := 'rejected'; end if;

  update public.runs set submitted_at = now(), score = p_score, duration_ms = p_duration_ms, breaks = p_breaks,
    max_combo = p_max_combo, client_version = left(p_version, 32), summary = p_summary, status = st, flags = fl
  where id = r.id;

  if st <> 'accepted' then return json_build_object('status', st); end if;
  select b.score into my_best from public.gs_bests(r.field, null) b where b.player_id = p.id;
  select 1 + count(*) into world_rank from public.gs_bests(r.field, null) b where b.score > my_best;
  if p.country is not null then
    select 1 + count(*) into country_rank from public.gs_bests(r.field, null) b where b.score > my_best and b.country = p.country;
  end if;
  select 1 + count(*) into week_rank from public.gs_bests(r.field, wk) b
    where b.score > (select w.score from public.gs_bests(r.field, wk) w where w.player_id = p.id);
  return json_build_object('status', st, 'best', my_best, 'world', world_rank, 'country', country_rank, 'week', week_rank);
end $$;

-- Top N of a board, plus the caller's own row when they are below it.
-- scope: 'world' (all time), 'country' (all time, p_country or the caller's), 'week' (this week, world)
create function public.gs_leaderboard(p_field text, p_scope text, p_country text default null, p_limit integer default 50)
returns table (rank integer, nickname text, country text, score integer, me boolean)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare c text := upper(p_country); lim integer := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  if p_scope = 'country' and c is null then select pl.country into c from public.players pl where pl.id = auth.uid(); end if;
  if p_scope = 'country' and c is null then return; end if;
  return query
    with b as (
      select * from public.gs_bests(p_field, case when p_scope = 'week' then public.gs_week_start() end)
      where p_scope <> 'country' or gs_bests.country = c
    ), ranked as (
      select (rank() over (order by b.score desc))::integer as rnk, b.player_id, b.nickname, b.country, b.score from b
    )
    select ranked.rnk, ranked.nickname, ranked.country, ranked.score, coalesce(ranked.player_id = auth.uid(), false)
    from ranked where ranked.rnk <= lim or ranked.player_id = auth.uid()
    order by ranked.rnk, ranked.nickname
    limit lim + 1;
end $$;

create function public.gs_report(p_nickname text) returns void
language plpgsql security definer set search_path = '' as $$
declare p public.players := public.gs_require_player(); t uuid;
begin
  select id into t from public.players where lower(nickname) = lower(p_nickname);
  if t is null or t = p.id then return; end if;
  insert into public.reports (reporter, target) values (p.id, t) on conflict do nothing;
end $$;

-- Google Play requires that players can delete their account and data from inside the app.
create function public.gs_delete_me() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  delete from auth.users where id = auth.uid(); -- cascades to players, runs and reports
end $$;

-- ---------------------------------------------------------------- moderation view (dashboard only)
create view public.gs_review with (security_invoker = true) as
  select r.id, p.nickname, p.country, r.field, r.score, r.duration_ms, r.breaks, r.status, r.flags, r.submitted_at,
    (select count(*) from public.reports x where x.target = p.id) as reports
  from public.runs r join public.players p on p.id = r.player_id
  where r.submitted_at is not null and (r.status = 'review' or exists (select 1 from public.reports x where x.target = p.id))
  order by r.submitted_at desc nulls last;
revoke all on public.gs_review from anon, authenticated;

-- ---------------------------------------------------------------- who may call what
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.gs_leaderboard(text, text, text, integer) to anon, authenticated;
grant execute on function public.gs_me(), public.gs_set_profile(text, text), public.gs_start_run(text),
  public.gs_submit_run(uuid, integer, integer, integer, integer, text, jsonb), public.gs_report(text),
  public.gs_delete_me() to authenticated;
