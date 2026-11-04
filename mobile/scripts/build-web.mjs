// Copies the web game (repo root) into mobile/www for Capacitor and injects the ad layer.
// The web version on Vercel is untouched: only the copy in www/ gets ads.js.
import { readFileSync, writeFileSync, mkdirSync, rmSync, copyFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const mobile = join(here, '..');
const root = join(mobile, '..');
const www = join(mobile, 'www');

const cfg = JSON.parse(readFileSync(join(mobile, 'ads.config.json'), 'utf8'));
const pub = {
  testMode: cfg.testMode !== false,
  rewardedId: cfg.rewardedId,
  interstitialId: cfg.interstitialId,
  interstitialEveryNthGame: cfg.interstitialEveryNthGame,
  interstitialFirstAfterGames: cfg.interstitialFirstAfterGames,
  interstitialMinSeconds: cfg.interstitialMinSeconds,
};
const TEST_PREFIX = 'ca-app-pub-3940256099942544';
if (!pub.testMode && [cfg.appId, cfg.rewardedId, cfg.interstitialId].some(id => String(id).startsWith(TEST_PREFIX))) {
  console.error('ads.config.json: testMode is false but some IDs are still Google test IDs. Put your own AdMob IDs in first.');
  process.exit(1);
}

rmSync(www, { recursive: true, force: true });
mkdirSync(www, { recursive: true });

let html = readFileSync(join(root, 'index.html'), 'utf8');
const marker = '<script>\n(function () {';
if (!html.includes(marker)) { console.error('Could not find the game script in index.html'); process.exit(1); }
const inject = `<script>window.__GS_ADS_CONFIG__ = ${JSON.stringify(pub)};</script>\n<script src="ads.js"></script>\n`;
html = html.replace(marker, inject + marker);
html = html.replace(/<link rel="manifest"[^>]*>\n?/, ''); // no PWA install prompt inside the app
writeFileSync(join(www, 'index.html'), html);

copyFileSync(join(mobile, 'src', 'ads.js'), join(www, 'ads.js'));
for (const f of ['icon.svg', 'icon-192.png', 'icon-512.png']) copyFileSync(join(root, f), join(www, f));

console.log(`www/ ready (${pub.testMode ? 'TEST ads' : 'LIVE ads'})`);
