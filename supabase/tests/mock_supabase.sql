-- Minimal stand-in for the parts of Supabase the migration uses (roles, auth.users, auth.uid()),
-- so the migration and its tests run on a plain PostgreSQL in CI.
do $$ begin create role anon nologin; create role authenticated nologin; exception when duplicate_object then null; end $$;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
