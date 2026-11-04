# Glass Symphony: Android-sovellus (Capacitor)

Tämä kansio paketoi selainpelin (`../index.html`) Android-sovellukseksi Capacitorilla. Pelin koodia ei
ole kirjoitettu uusiksi: sama `index.html` kopioidaan sovelluksen sisään, ja vain sovellusversioon
lisätään mainoskerros `src/ads.js`. Vercelin selainversiossa ei ole mainoksia.

## Mitä sovellukseen tulee

- **Palkittu jatko**: kun peli päättyy (vähintään 50 pistettä), näkyy nappi *JATKA ♥ – katso lyhyt mainos*.
  Pelaaja jatkaa samasta pistemäärästä yhdellä elämällä. Kerran per peli.
- **Välimainos**: aikaisintaan kolmannen pelin jälkeen, korkeintaan joka 3. uusi peli ja vähintään 2 min
  edellisestä mainoksesta. Näytetään vasta kun pelaaja napauttaa "pelaa uudelleen", ei koskaan kesken pelin.
- **EU-suostumus** (Googlen UMP-lomake) ennen mainoksia, ja *Mainosten tietosuoja-asetukset* -linkki
  Ohjeet-ikkunassa (Googlen vaatimus EU:ssa).
- Koko ruudun tila, pystysuunta, näyttö pysyy päällä pelatessa, oma kuvake ja aloitusruutu.

Kaikki mainosasetukset ovat tiedostossa [`ads.config.json`](ads.config.json).

## Omat AdMob-tunnukset (kun AdMob-tili on valmis)

1. AdMobissa: *Apps → Add app → Android* ("not published yet" käy). Kopioi **App ID** (`ca-app-pub-…~…`).
2. Luo kaksi mainosyksikköä: **Rewarded** (nimeksi esim. "Continue") ja **Interstitial** ("Between games").
   Kopioi niiden tunnukset (`ca-app-pub-…/…`).
3. Vaihda ne `ads.config.json`-tiedostoon ja aseta `"testMode": false`.
4. AdMobissa *Privacy & messaging → GDPR*: luo ja julkaise suostumusviesti tälle sovellukselle.

Älä koskaan klikkaa omia oikeita mainoksiasi. Testaa omalla puhelimella testitunnuksilla, tai lisää
puhelimesi AdMobiin testilaitteeksi.

## Rakentaminen

**GitHub Actions (suositus, ei asennettavaa):** jokainen muutos `main`-haaraan tai `mobile/`-kansioon
käynnistää *Android build* -ajon. Valmiit tiedostot löytyvät ajon sivulta kohdasta *Artifacts*:

- `glass-symphony-debug-apk`: asennettava testi-APK omaan puhelimeen.
- `glass-symphony-release-aab`: allekirjoitettu `.aab` Google Playhin. Tämä syntyy vain, kun repoon on
  lisätty latausavaimen salaisuudet (alla).

**Latausavain (upload key)** GitHubin *Settings → Secrets and variables → Actions*:

| Salaisuus | Sisältö |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `upload.jks` base64-muodossa |
| `ANDROID_KEYSTORE_PASSWORD` | avainsäilön salasana |
| `ANDROID_KEY_ALIAS` | avaimen alias (esim. `upload`) |
| `ANDROID_KEY_PASSWORD` | avaimen salasana |

Ota Play Consolessa käyttöön *Play App Signing* (oletus uusille sovelluksille). Silloin Google säilyttää
varsinaisen allekirjoitusavaimen, ja kadonneen latausavaimen voi vaihtaa.

**Omalla koneella (Android Studio):**

```
cd mobile
npm install
npm run sync      # kopioi pelin www/-kansioon ja päivittää android/-projektin
npm run open      # avaa Android Studion
```

Android Studiossa: *Build → Generate Signed App Bundle*. Paikallista allekirjoitusta varten voit luoda
tiedoston `android/keystore.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); se on
`.gitignore`ssa.

Jokainen Play-julkaisu tarvitsee suuremman `versionCode`n. GitHub Actions käyttää ajon numeroa
automaattisesti. Päivitä `versionName` tiedostossa `android/app/build.gradle`.

## iOS

Sama projekti toimii iOS:lle (`npx cap add ios`), mutta rakentaminen vaatii Macin ja Xcoden sekä Apple
Developer -jäsenyyden (99 USD/v). AdMob tarvitsee iOS:llä lisäksi App Tracking Transparency -kysymyksen.
