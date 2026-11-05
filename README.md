# Glass Symphony

One-finger glass-shattering arcade game. Every break plays a note; combos climb into a melody.

- Plain HTML5 canvas + Web Audio, no build step.
- Works offline (service worker) and installs to the home screen (web app manifest).
- Open `index.html` directly, or serve the folder with any static host.

## Store app

`mobile/` wraps this same game into an Android app with Capacitor and adds AdMob ads (rewarded
continue + occasional interstitial). The web version has no ads. See [mobile/README.md](mobile/README.md).
Privacy policy: [privacy.html](privacy.html).

## Leaderboards

World, country and weekly leaderboards run on Supabase (anonymous accounts, server-checked scores,
no server code to host). They stay switched off until `GS_API` in `index.html` has the project URL
and publishable key. Setup, moderation and tests: [supabase/README.md](supabase/README.md).
