# Glass Symphony backend (Supabase)

Leaderboards for the game: anonymous player accounts, nicknames, countries, server-checked runs and
world / country / weekly boards. Everything lives in one SQL migration; there is no server code to host.

```
supabase/
  config.toml                         local CLI settings (anonymous sign-ins on)
  migrations/20261105000000_leaderboards.sql
  tests/mock_supabase.sql             stands in for Supabase's auth schema on plain PostgreSQL
  tests/leaderboards_test.sql         assertions for every function (prints "all leaderboard tests passed")
```

## How it works

- **Accounts.** On first launch the game signs in anonymously (no email, no password) and keeps the
  session on the device. The player picks a nickname (3–16 letters, digits, space, `_ . -`, unique,
  word filter) and a country. Nickname changes every 7 days, country every 30 days.
- **No direct table access.** Row level security is on with no policies, and the tables are revoked
  from `anon` and `authenticated`. The app can only call the `gs_*` functions (SECURITY DEFINER,
  empty `search_path`). The publishable/anon key is therefore safe to ship inside the app.
- **Runs.** `gs_start_run(field)` is called when a game starts and returns a run id; the server's
  clock bounds the game length. `gs_submit_run(...)` checks the result and returns the player's best
  and their world / country / week rank. Runs with boosts are never sent (skill-to-win), and the
  Crown ball's point bonus does not count towards the leaderboard score.
- **Plausibility checks** (in `gs_submit_run`):
  - more than 6000 points per second, or a client time more than 5 s longer than the server's → `rejected`
  - more than 1500 points per second, too many breaks for the time, or a combo above the breaks → `review`
    (hidden from the boards until you accept it)
  - a run can be submitted once, within 3 hours; at most 120 runs started per player per hour
- **Boards.** `gs_leaderboard(field, 'world' | 'country' | 'week', country, limit)` returns the top
  list plus the caller's own row. Weeks start on Monday 00:00 Finnish time. Banned players and players
  without a nickname are never shown.
- **Privacy.** `gs_delete_me()` (the "Delete my account" button in the game) removes the account and
  all its runs at once. See `privacy.html`.

## One-time setup

1. **Separate account.** Sign out of the EV projects' Supabase account and create a new one at
   <https://supabase.com/dashboard/sign-up> (for example with a different email or GitHub account).
   Create an organization called *Glass Symphony* on the Free plan.
2. **Project.** New project `glass-symphony`, region **Central EU (Frankfurt)**. Save the database
   password in your password manager. Never paste it in a chat.
3. **Anonymous sign-ins.** Dashboard → Authentication → Sign In / Providers → turn on
   **Allow anonymous sign-ins**.
4. **GitHub secrets.** In the repository: Settings → Secrets and variables → Actions → New repository
   secret, add:
   - `SUPABASE_ACCESS_TOKEN`: Supabase dashboard → your avatar → Account preferences → Access Tokens → Generate
   - `SUPABASE_DB_PASSWORD`: the password from step 2
   - `SUPABASE_PROJECT_REF`: the id in the project URL, `https://supabase.com/dashboard/project/<this part>`
5. **Deploy the database.** Actions → *Supabase* → Run workflow on `main` (it also runs by itself on
   every push to `main` that touches `supabase/`).
6. **Connect the game.** Dashboard → Project Settings → API Keys: copy the project URL and the
   publishable (anon) key into `index.html`:
   ```js
   const GS_API = window.__GS_API__ || { url: 'https://<ref>.supabase.co', key: '<publishable key>' };
   ```
   While these are empty the leaderboard is switched off and the trophy button is hidden.
   Never put the `service_role` / secret key in the game.

A free project is paused after a week without any requests; while people play, that does not happen.

## Moderation

Use the dashboard's SQL editor (it runs as the database owner):

```sql
-- runs waiting for review, and players other people have reported
select * from public.gs_review;

-- accept a run that was held for review
update public.runs set status = 'accepted' where id = '<run id>';

-- remove an offensive nickname (the player is asked to pick a new one)
update public.players set nickname = null where lower(nickname) = lower('<nickname>');

-- ban a cheater: hides all their scores and blocks new runs
update public.players set banned = true where lower(nickname) = lower('<nickname>');
```

## Tests

CI (`.github/workflows/supabase.yml`) runs the migration and the tests on a plain PostgreSQL 17 for
every pull request that touches `supabase/`. Locally:

```sh
createdb gs_test
psql -d gs_test -v ON_ERROR_STOP=1 -f supabase/tests/mock_supabase.sql \
  -f supabase/migrations/20261105000000_leaderboards.sql -f supabase/tests/leaderboards_test.sql
```

New schema changes go in a new file in `migrations/` (never edit one that is already deployed).
