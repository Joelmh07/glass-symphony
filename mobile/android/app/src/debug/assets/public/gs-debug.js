// Only in the DEBUG app build (Android merges src/debug/assets into the debug APK only).
// Turns on testing helpers in the game, such as the "+10 000 crystals" button in the shop.
// The release build for Google Play never contains this file, so its <script> tag just fails to load.
window.__GS_DEBUG__ = true;
