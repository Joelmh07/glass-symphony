/* Glass Symphony: AdMob layer for the store app (Capacitor).
 * Loaded before the game script, only in the native build (scripts/build-web.mjs injects it).
 * It exposes window.GSAds, which the game uses for two things:
 *   - a rewarded "continue" once per run (player chooses to watch)
 *   - an interstitial between runs, at most every Nth game and never too often
 * Everything fails safe: if ads cannot load, the game just runs without them. */
(function () {
  'use strict';
  var CFG = window.__GS_ADS_CONFIG__ || {};
  var cap = window.Capacitor;
  var AdMob = cap && cap.isNativePlatform && cap.isNativePlatform() && cap.Plugins && cap.Plugins.AdMob;
  if (!AdMob) return; // not in the app: window.GSAds stays undefined

  var STORE_KEY = 'glassSymphony.ads';
  var st = { runs: 0, lastAdAt: 0 };
  try { Object.assign(st, JSON.parse(localStorage.getItem(STORE_KEY) || '{}')); } catch (e) {}
  function persist() { try { localStorage.setItem(STORE_KEY, JSON.stringify(st)); } catch (e) {} }

  var ready = false;          // consent done + SDK initialised
  var rewardLoaded = false, rewardLoading = false;
  var interLoaded = false, interLoading = false;
  var showing = false;        // an ad is on screen right now
  var privacyRequired = false;
  var npa = false;            // non-personalised ads if the player did not consent

  var testing = CFG.testMode !== false;
  var everyNth = CFG.interstitialEveryNthGame || 3;
  var firstAfter = CFG.interstitialFirstAfterGames || 3;
  var minGapMs = (CFG.interstitialMinSeconds || 120) * 1000;

  function log() { if (testing && window.console) console.log.apply(console, ['[ads]'].concat([].slice.call(arguments))); }

  function loadReward() {
    if (!ready || rewardLoaded || rewardLoading) return;
    rewardLoading = true;
    AdMob.prepareRewardVideoAd({ adId: CFG.rewardedId, isTesting: testing, npa: npa, immersiveMode: true })
      .then(function () { rewardLoaded = true; }, function (e) { log('reward load failed', e); retry(loadReward); })
      .then(function () { rewardLoading = false; });
  }
  function loadInter() {
    if (!ready || interLoaded || interLoading) return;
    interLoading = true;
    AdMob.prepareInterstitial({ adId: CFG.interstitialId, isTesting: testing, npa: npa, immersiveMode: true })
      .then(function () { interLoaded = true; }, function (e) { log('interstitial load failed', e); retry(loadInter); })
      .then(function () { interLoading = false; });
  }
  var retryDelay = {};
  function retry(fn) { // back off 15 s, 30 s, 60 s ... up to 5 min
    var d = retryDelay[fn.name] = Math.min(300000, (retryDelay[fn.name] || 7500) * 2);
    setTimeout(fn, d);
  }

  function start() {
    // 1) EU/UK consent (Google UMP). Required before personalised ads in the EEA.
    AdMob.requestConsentInfo({})
      .then(function (info) {
        if (info.isConsentFormAvailable && info.status === 'REQUIRED') return AdMob.showConsentForm();
        return info;
      })
      .then(function (info) {
        privacyRequired = info && info.privacyOptionsRequirementStatus === 'REQUIRED';
        npa = !!info && info.status !== 'OBTAINED' && info.status !== 'NOT_REQUIRED';
        if (info && info.canRequestAds === false) return Promise.reject('cannot request ads');
        addPrivacyButton();
      }, function (e) { log('consent failed', e); })
      // 2) start the SDK and preload one ad of each kind
      .then(function () { return AdMob.initialize({ initializeForTesting: testing }); })
      .then(function () {
        ready = true; loadReward(); loadInter();
        try { AdMob.setApplicationVolume({ volume: 0.5 }); } catch (e) {}
      }, function (e) { log('init failed', e); });
  }

  // Google requires a way to reopen the consent choices when they apply: add it to "How to play".
  function addPrivacyButton() {
    if (!privacyRequired) return;
    var panel = document.querySelector('#howto .panel');
    if (!panel || document.getElementById('gsPrivacy')) return;
    var fi = (document.documentElement.lang || '').indexOf('fi') === 0;
    var b = document.createElement('button');
    b.id = 'gsPrivacy'; b.type = 'button';
    b.textContent = fi ? 'Mainosten tietosuoja-asetukset' : 'Ad privacy settings';
    b.style.cssText = 'display:block;margin:14px auto 0;background:none;border:0;color:rgba(255,255,255,.6);text-decoration:underline;font:inherit;font-size:13px;padding:8px;';
    b.addEventListener('click', function () { AdMob.showPrivacyOptionsForm().catch(function () {}); });
    panel.appendChild(b);
  }

  // Shows a full-screen ad and resolves once it has CLOSED (or failed to show), so the game never
  // runs behind an ad. Note: the plugin's show*() promises resolve at show time (interstitial) or on
  // reward (rewarded, and never if the player closes it early), so we wait for the events instead.
  function showFullScreen(kind) {
    var ev = kind === 'reward'
      ? { closed: 'onRewardedVideoAdDismissed', failed: 'onRewardedVideoAdFailedToShow', reward: 'onRewardedVideoAdReward' }
      : { closed: 'interstitialAdDismissed', failed: 'interstitialAdFailedToShow' };
    return new Promise(function (resolve) {
      var earned = false, handles = [], finished = false, timer;
      function finish() {
        if (finished) return; finished = true;
        clearTimeout(timer);
        handles.forEach(function (h) { try { h.remove(); } catch (e) {} });
        resolve(earned);
      }
      function on(name, fn) { return AdMob.addListener(name, fn).then(function (h) { handles.push(h); }); }
      var subs = [on(ev.closed, finish), on(ev.failed, finish)];
      if (ev.reward) subs.push(on(ev.reward, function () { earned = true; }));
      Promise.all(subs)
        .then(function () { return kind === 'reward' ? (AdMob.showRewardVideoAd().catch(function (e) { log('show failed', e); finish(); }), null) : AdMob.showInterstitial(); })
        .catch(function (e) { log('show failed', e); finish(); });
      timer = setTimeout(finish, 120000); // safety net: never leave the player stuck
    });
  }

  function showReward() {
    if (!rewardLoaded || showing) return Promise.resolve(false);
    showing = true; rewardLoaded = false;
    return showFullScreen('reward').then(function (earned) {
      showing = false; st.lastAdAt = Date.now(); persist();
      loadReward();
      return earned;
    });
  }

  // Called when the player taps "play again". Returns true if an ad is now showing;
  // then `next` (startGame) is called once it closes.
  function beforeRestart(next) {
    if (showing) return true; // ignore extra taps while an ad is up
    st.runs++; persist();
    var due = st.runs >= firstAfter && st.runs % everyNth === 0 && Date.now() - st.lastAdAt >= minGapMs;
    if (!due || !interLoaded) { if (due) loadInter(); return false; }
    showing = true; interLoaded = false;
    showFullScreen('inter').then(function () {
      showing = false; st.lastAdAt = Date.now(); persist();
      loadInter(); next();
    });
    return true;
  }

  window.GSAds = {
    rewardReady: function () { if (!rewardLoaded) loadReward(); return rewardLoaded && !showing; },
    showReward: showReward,
    beforeRestart: beforeRestart
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
