-- Tests for the leaderboard migration. Run after mock_supabase.sql and the migration on an empty
-- database (see .github/workflows/supabase.yml). Any failed check raises and stops psql.
\set ON_ERROR_STOP 1

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false), null::void $$;
create function pg_temp.expect_error(q text, msg text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then
    if sqlerrm <> msg then raise exception 'expected % from [%], got %', msg, q, sqlerrm; end if;
    return;
  end;
  raise exception 'expected % from [%], got no error', msg, q;
end $$;
create function pg_temp.check(ok boolean, what text) returns void language plpgsql as $$
begin if not coalesce(ok, false) then raise exception 'check failed: %', what; end if; end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

insert into auth.users values ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b');
create temp table ids (who text primary key, id uuid);
grant all on ids to authenticated;

set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select pg_temp.expect_error('select * from public.runs', 'permission denied for table runs');
select pg_temp.expect_error('select * from public.players', 'permission denied for table players');
insert into ids select 'a0', public.gs_start_run('classic'); -- allowed before a nickname is set
select pg_temp.expect_error($$select public.gs_set_profile('ab', 'fi')$$, 'nickname_length');
select pg_temp.expect_error($$select public.gs_set_profile('VittuMies', 'fi')$$, 'nickname_blocked');
select pg_temp.expect_error($$select public.gs_set_profile('<b>x</b>', 'fi')$$, 'nickname_chars');
select pg_temp.expect_error($$select public.gs_set_profile(' Joel', 'fi')$$, 'nickname_chars');
select pg_temp.expect_error($$select public.gs_set_profile('Joel', 'Finland')$$, 'country_invalid');
select pg_temp.check((public.gs_set_profile('Jääkuningas', 'fi') ->> 'country') = 'FI', 'profile saved, country upper-cased');
select pg_temp.expect_error($$select public.gs_set_profile('Toinen', null)$$, 'nickname_too_soon');
select pg_temp.check((public.gs_set_profile('JÄÄKUNINGAS', null) ->> 'nickname') = 'JÄÄKUNINGAS', 'case-only change allowed');
select pg_temp.expect_error($$select public.gs_set_profile(null, 'SE')$$, 'country_too_soon');
select pg_temp.expect_error($$select public.gs_start_run('moon')$$, 'field_invalid');

select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select pg_temp.expect_error($$select public.gs_set_profile('jääkuningas', 'se')$$, 'nickname_taken');
select public.gs_set_profile('Lasimestari', 'se');

select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into ids select 'a1', public.gs_start_run('classic');
insert into ids select 'a2', public.gs_start_run('classic');
insert into ids select 'a3', public.gs_start_run('classic');
insert into ids select 'a4', public.gs_start_run('classic');
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
insert into ids select 'b1', public.gs_start_run('classic');
insert into ids select 'b2', public.gs_start_run('rush');
reset role;
update public.runs set started_at = now() - interval '120 seconds';
delete from public.runs where id = (select id from ids where who = 'a0');
update public.runs set started_at = now() - interval '4 hours' where id = (select id from ids where who = 'a4');
set role authenticated;

select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select pg_temp.check((public.gs_submit_run((select id from ids where who = 'a1'), 12000, 110000, 150, 40, 't') ->> 'status') = 'accepted', 'normal run accepted');
select pg_temp.expect_error($$select public.gs_submit_run((select id from ids where who = 'a1'), 1, 1000, 1, 1, 't')$$, 'run_used');
select pg_temp.check((public.gs_submit_run((select id from ids where who = 'a2'), 9000, 300000, 150, 40, 't') ->> 'status') = 'rejected', 'longer than the server clock: rejected');
select pg_temp.check((public.gs_submit_run((select id from ids where who = 'a3'), 900000, 100000, 150, 40, 't') ->> 'status') = 'rejected', 'impossible score rate: rejected');
select pg_temp.expect_error($$select public.gs_submit_run((select id from ids where who = 'a4'), 100, 1000, 1, 1, 't')$$, 'run_expired');
select pg_temp.expect_error($$select public.gs_submit_run((select id from ids where who = 'b1'), 100, 1000, 1, 1, 't')$$, 'run_unknown');

select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select pg_temp.check((public.gs_submit_run((select id from ids where who = 'b1'), 15000, 115000, 160, 30, 't') ->> 'world') = '1', 'b is first in the world');
select pg_temp.check((public.gs_submit_run((select id from ids where who = 'b2'), 200000, 100000, 300, 30, 't') ->> 'status') = 'review', 'suspicious rate waits for review');
select pg_temp.check((select count(*) = 2 from public.gs_leaderboard('classic', 'world')), 'world board has both players');
select pg_temp.check((select nickname = 'Lasimestari' and me from public.gs_leaderboard('classic', 'world') where rank = 1), 'b on top, marked as me');
select pg_temp.check((select count(*) = 1 from public.gs_leaderboard('classic', 'country')), 'own country board (SE) has one');
select pg_temp.check((select nickname = 'JÄÄKUNINGAS' from public.gs_leaderboard('classic', 'country', 'fi')), 'FI board');
select pg_temp.check((select count(*) = 2 from public.gs_leaderboard('classic', 'week')), 'week board');
select pg_temp.check((select count(*) = 0 from public.gs_leaderboard('rush', 'world')), 'runs under review are hidden');
select public.gs_report('jääkuningas');

reset role; set role anon; select pg_temp.as_user('');
select pg_temp.check((select count(*) = 1 from public.gs_leaderboard('classic', 'world', null, 1)), 'anyone can read a board');
select pg_temp.expect_error($$select public.gs_start_run('classic')$$, 'permission denied for function gs_start_run');

reset role;
select pg_temp.check((select count(*) = 4 from public.gs_review), 'review view: the run under review and the 3 runs of the reported player');
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select public.gs_delete_me();
reset role;
select pg_temp.check((select count(*) = 1 from public.players), 'deleted player is gone');
select pg_temp.check((select count(*) = 2 from public.runs), 'their runs are gone too');
select 'all leaderboard tests passed';
