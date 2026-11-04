/* Glass Symphony: in-app purchases for the store app.
 *
 * The game talks only to window.GSStore (see "WALLET, SHOP ... PURCHASES" in index.html):
 *   GSStore.available()   -> true when the billing plugin is installed and the store answered
 *   GSStore.priceOf(id)   -> localised price string from the store, e.g. "2,99 €" (or null)
 *   GSStore.buy(id)       -> Promise<{ ok, txId, cancelled }>
 *   GSStore.restore()     -> Promise<[{ id, txId }]>   (non-consumables, i.e. gs_noads)
 * On a successful buy the game grants the product itself (crystals or "no interstitials"),
 * once per transaction id, and saves it.
 *
 * STATUS: no billing plugin is installed yet, so available() is false and the shop hides the
 * real-money products. To switch purchases on:
 *   1. Create the products in Play Console (Monetize > Products > In-app products) with exactly
 *      these ids. gs_noads is a one-time (non-consumable) product, the gem packs are consumables.
 *   2. Install a Capacitor billing plugin (for example @capgo/native-purchases or
 *      cordova-plugin-purchase), run `npm run sync`, and fill in the three adapter functions
 *      below (nativeLoad, nativeBuy, nativeRestore). Nothing in the game needs to change.
 *   3. Consume the gem packs after granting them, so they can be bought again.
 */
(function () {
  'use strict';
  var PRODUCTS = ['gs_noads', 'gs_gems_300', 'gs_gems_1000', 'gs_gems_3000'];
  var cap = window.Capacitor;
  if (!(cap && cap.isNativePlatform && cap.isNativePlatform())) return; // web: no store

  var ready = false, prices = {};

  // ---- adapter: the only part that depends on the billing plugin ----
  function plugin() { return null; /* e.g. return cap.Plugins.NativePurchases || null; */ }
  function nativeLoad(p) { // -> Promise<{ [id]: priceString }>
    return Promise.reject(new Error('billing plugin not installed'));
  }
  function nativeBuy(p, id) { // -> Promise<{ ok, txId, cancelled }>
    return Promise.reject(new Error('billing plugin not installed'));
  }
  function nativeRestore(p) { // -> Promise<[{ id, txId }]>
    return Promise.resolve([]);
  }
  // -------------------------------------------------------------------

  var p = plugin();
  if (p) nativeLoad(p).then(function (map) { prices = map || {}; ready = true; }, function () { ready = false; });

  window.GSStore = {
    available: function () { return ready; },
    priceOf: function (id) { return prices[id] || null; },
    buy: function (id) {
      if (!ready || PRODUCTS.indexOf(id) < 0) return Promise.resolve({ ok: false });
      return nativeBuy(p, id).catch(function () { return { ok: false }; });
    },
    restore: function () { return ready ? nativeRestore(p) : Promise.resolve([]); }
  };
})();
