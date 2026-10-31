# Cozy Pal 🐱📚

A cozy room with a little pet that helps you:

The two main buttons:

| Button | What happens |
|---|---|
| **RECORD!** | Recording starts at once and the pet runs to the mic. The record panel floats over the room (the room never resizes): live timer and sound bars, pause/resume, cancel, auto-stop at 10 minutes. Whisper writes the words, you fix them on a review card, and the pet files the note in the notes box (and tells you if it goes with an email). |
| **Notes** | The notes box, and the place to search. Pick **Notes**, **Emails** or **Both**, then type or say what you're looking for: results appear as you type, and pressing search makes the pet answer out loud in up to 3 sentences. Emails mode also lists your last month of mail by day. Notes have filters (all / pinned / voice / typed), swipe to delete with undo, and a Write button. Each note opens full size: edit as you type, play the recording, pin, copy, read aloud, and see the emails that go with it. |

Also in the room: tap the **bookshelf** or the **pet** to open the talk box (type or speak):

- **Ask anything** ("Why do cats purr?"): the pet searches its books while your cloud AI writes the answer, then reads it to you in up to 3 sentences.
- **Message a friend** ("Text Ana I'm running late", "WhatsApp Leo see you at 7", "Email mom about dinner Sunday"): the pet finds them in your contacts, writes the message (your AI tidies the wording if one is set up) and shows a letter card you can edit. **Send** opens Messages / WhatsApp / your mail app with everything filled in, and you press send there. Nothing ever goes out on its own.
- **Cheer me up** ("I'm bored", "I feel sad", "play some Taylor Swift", "show me cat videos", "send me a meme", "let's play a game"): the pet says something kind, runs to the bookshelf and comes back with a present, picked from what it knows about you ("I love…" / "my favourite band is…" in what you say and in your notes, plus your 👍 / 👎; your cloud AI chooses when one is set up, otherwise simple on-phone rules):
  - **A song on YouTube.** The pet picks a real track for an artist or genre you like (Apple's free iTunes Search, no key), shows the cover, and **Play** opens YouTube in a browser window inside the app, searching for that exact song. "Open in the YouTube app" is there too.
  - **A video on YouTube.** Funny or cozy cat videos by default, or something from your likes ("Phoebe Bridgers live"), or whatever you asked for ("videos of otters"). Same in-app YouTube window.
  - **A wholesome meme** (r/wholesomememes, r/catmemes via meme-api.com; NSFW and spoilers skipped).
  - **A free browser game from itch.io.** The pet picks an itch.io tag from what you like ("I love cats" → cats) or your mood (cozy and relaxing when stressed, arcade and puzzle when bored) and reads itch.io's public feed of free web games for that tag (add `.xml` to any browse page; no key needed). Games mentioning horror, gore or adult themes are filtered out. Play opens it in the same kind of in-app window.

  **How Mochi learns what you like (the interest engine, `lib/services/interest_engine.dart`).** It works like the recommenders behind YouTube, Facebook or Amazon, but entirely on the phone:
  - *Features.* Everything Mochi brings is described by features: its kind (`kind:song`), the artist and genre (from Apple's song data), the topic (`topic:funny cat videos`) or the itch.io tag (`tag:cozy`).
  - *Signals.* Explicit: saying "I love…" (+3) or "I hate…" (−4), asking by name (+2), 👍 (+3) / 👎 (−3), muting. Implicit: opening (+1), how long you stay in the YouTube / itch.io window (under 10 s −0.7, up to 3 min +1.5, longer +2.5, like watch time), closing without opening (−0.4), "Another one" (the kind +0.3, that topic −0.4), "Something else" (−0.6), "I love…" in your notes (+1.5).
  - *Time decay.* Scores fade with a 30-day half-life and are capped, so new interests rise and old ones fade.
  - *Context.* For each mood (sad, bored…) and time of day, Mochi keeps a win/miss record per kind and chooses the kind by **Thompson sampling** (Beta distributions), starting from sensible mood defaults on day one. About 10% of the time it picks any kind, so it keeps learning instead of getting stuck.
  - *Ranking.* The topic is chosen by interest score + open rate + an exploration bonus for things rarely shown (UCB) − fatigue for things shown in the last few hours, then sampled (softmax) so picks vary. About 12% of picks are deliberately new ideas ("🧭 New to try").
  - *Transparency.* Each card shows "✨ 87% match" and why ("You've given Phoebe Bridgers a thumbs up 2 times"). Settings → *What Mochi knows about you* lists your top interests with scores, what you enjoy most, what helps per mood, and lets you mute or forget anything, pause learning, or wipe it all. When a cloud AI helps choose, it only gets this short summary.

  The in-app window is Safari View on iPhone and a Chrome Custom Tab on Android; close it to return to the room. Opening something earns a treat. Covers and memes live in a temporary folder and are **deleted when you close the card** (leftovers are swept on the next launch). YouTube itself isn't filtered by the app: turn on YouTube's Restricted Mode if younger people use the phone. You can see and remove what the pet has learned in Settings → *What Mochi knows about you*. If someone says something that sounds like they might hurt themselves, the pet doesn't send a meme: it answers gently and shows a helpline (988 in the US/Canada, Samaritans in the UK/Ireland, Lifeline in Australia, findahelpline.com elsewhere).
- **Get an app** ("Download Spotify"): on iPhone the pet shows the matching App Store apps; on Android it opens the Play Store search. Phones only let *you* press Get / Install.

The **mailbox** summarises unread mail (and points out mail that matches your notes), the **wardrobe** swaps pet friends, and tapping the **pet** says hi.

**On the phone (Cactus):** Needle 3 decides what you asked for and turns notes and emails into meaning fingerprints (embeddings) for search; Whisper turns speech into text. Search, the note index and the mail cache never leave the phone. Both are downloaded in Settings on first use.
**In the cloud (your choice):** Claude, ChatGPT, Gemini, or any OpenAI-compatible service (OpenRouter, Groq, a local Ollama…) writes the answers and email summaries.
**Email (your choice):** Gmail, Outlook/Microsoft 365, Yahoo, iCloud, or any IMAP mailbox. Read-only.

Notes and recordings never leave the phone.

---

## 0. Web version on Cloudflare Pages

The same app also runs in the browser. Cloudflare Pages builds it straight from this repo on every push.

**Set up (once):** Cloudflare dashboard → Workers & Pages → Create → Pages → *Connect to Git* → pick this repo, then:

| Setting | Value |
|---|---|
| Framework preset | None |
| Build command | `bash tool/cf_build.sh` |
| Build output directory | `build/web` |
| Root directory | *(leave empty)* |

The script installs Flutter, adds the web files and runs `flutter build web`. `functions/api/fetch.js` is deployed with it: a small allow-listed proxy so the browser can reach Apple's song search, meme-api.com and itch.io (browsers block those cross-site reads otherwise).

**What's different in the browser**

| | Phone app | Web |
|---|---|---|
| Understanding requests | Needle 3 on the phone | Keyword matching |
| Talking, voice notes | Whisper on the phone, audio kept | Your browser's speech recognition (Chrome, Edge, Safari), words only |
| Answers, summaries, picks | Your cloud AI | Your cloud AI (same key, called straight from the browser) |
| Email | Gmail, Outlook, IMAP | Gmail and Outlook (sign in about once an hour); IMAP needs the phone |
| Messages to friends | Picks from your contacts | Type the number or email (browsers can't read contacts) |
| Songs, videos, games | Opens in a window over the room | Opens in a new tab |
| Storage | Files on the phone | This browser's storage (clearing site data erases it) |

**Email in the browser:** Gmail needs a Google OAuth client of type *Web application* with your site (e.g. `https://cozy-pal.pages.dev`) as an authorized JavaScript origin and `https://cozy-pal.pages.dev/oauth.html` as a redirect URI. Outlook needs a *Single-page application* platform with the same redirect URI and "Access tokens" ticked.

## 1. Run it on your Android phone (Windows works)

You need Flutter 3.35 or newer and Android Studio.

```bash
cd cozy_pal
flutter create --org com.cozypal --project-name cozy_pal --platforms android,ios .
dart run tool/setup_platforms.dart
flutter pub get
flutter run            # with your phone plugged in (USB debugging on)
```

The app runs at this point. Without the Cactus engine it uses simple keyword matching instead of Needle, and saves voice notes as audio only. Step 2 adds the engine.

## 2. Add the Cactus engine (Needle 3 + Whisper)

The engine is a native library built from https://github.com/cactus-compute/cactus.

**Easiest — let GitHub build it:** push this folder to a GitHub repo, open **Actions → Build app → Run workflow**. You get an Android APK *with* the engine, and an unsigned iOS build. `.github/workflows/build.yml` does everything.

**Or build it yourself:**

- Android (Linux, macOS or WSL on Windows, with the Android NDK installed):
  ```bash
  git clone https://github.com/cactus-compute/cactus ../cactus
  bash ../cactus/android/build.sh
  ```
- iOS (Mac with Xcode):
  ```bash
  bash ../cactus/apple/build.sh
  ```
- Then copy the results in:
  ```bash
  dart run tool/setup_platforms.dart --cactus ../cactus
  ```

In the app: **Settings → On-device AI → Download** for Needle 3 and Whisper (from huggingface.co/Cactus-Compute).

## 3. Pick your AI

**Settings → AI for answers**: choose the service, paste your API key, tap **Choose** to pick a model from your account, then **Save & test**. Keys are stored in the phone's secure keychain.

## 4. Connect email

**Settings → Mailbox**, then pick one:

- **Yahoo / iCloud / other IMAP** — simplest. Make an *app password* in your account's security settings and paste it with your address.
- **Gmail** — in Google Cloud Console: create a project, enable the **Gmail API**, set up the OAuth consent screen (add yourself as a test user), then create an OAuth client ID of type **iOS** with bundle ID `com.cozypal.app`. That one client ID works on both iPhone and Android. Paste it in the app and sign in. (Publishing to the public later requires Google's verification for the `gmail.readonly` scope.)
- **Outlook / Hotmail / Microsoft 365** — in Microsoft Entra (portal.azure.com → App registrations): new registration, accounts in any organization + personal Microsoft accounts, platform **Mobile and desktop** with redirect URI `com.cozypal.app://oauth/redirect`, API permission **Mail.Read**. Paste the Application (client) ID in the app and sign in.

Email previews are sent to the AI you picked, only to write the summary.

## 5. iPhone — no Mac or Xcode needed

Apple's build tools only run on a Mac, but the Mac can be one in the cloud. Two ways:

**A. Free: GitHub builds it, Sideloadly installs it from Windows**
1. Push this folder to a GitHub repo and run **Actions → Build app**. Download the `cozy-pal-ios` artifact and unzip it to get `cozy-pal-unsigned.ipa`.
2. On Windows install iTunes and iCloud from apple.com (not the Microsoft Store versions), then install Sideloadly from sideloadly.io.
3. Plug in the iPhone, tap **Trust**, drag the `.ipa` into Sideloadly, sign in with your Apple ID and press **Start**.
4. On the iPhone turn on **Settings → Privacy & Security → Developer Mode** (iOS 16+), restart, and open the app.

With a free Apple ID the app stops opening after 7 days; repeat step 3 to refresh it (your notes stay). Free IDs can have 3 sideloaded apps at a time.

**B. Paid ($99/year Apple Developer account): Codemagic → TestFlight**
Codemagic builds Flutter apps on cloud Macs (500 free build minutes a month). Connect your GitHub repo at codemagic.io, add your App Store Connect API key, turn on automatic iOS code signing and publishing to TestFlight, and add these pre-build commands:
```bash
git clone --depth 1 https://github.com/cactus-compute/cactus.git ../cactus && bash ../cactus/apple/build.sh
flutter create --org com.cozypal --project-name cozy_pal --platforms android,ios .
dart run tool/setup_platforms.dart --cactus ../cactus
```
Install the TestFlight app on the iPhone and the build arrives there. No 7-day limit, and you can invite friends.

---

## Project map

```
lib/
  main.dart                  app start-up
  pet_controller.dart        what the pet does for each feature (record, find, mail)
  ai/
    cactus_bindings.dart     FFI to the Cactus engine
    local_ai.dart            Needle 3 routing + Whisper transcription (background isolate)
    model_manager.dart       downloads model bundles from Hugging Face
  services/
    llm_service.dart         Claude / OpenAI / Gemini / OpenAI-compatible, 3-sentence answers
    email_service.dart       Gmail API, Microsoft Graph, IMAP — unread mail only
    notes_service.dart       notes box storage (titles, pins, undo)
    memory_service.dart      on-device search over notes + mail, note↔email links
    voice_service.dart       recording (16 kHz WAV), text-to-speech, playback; browser dictation on the web
    settings_service.dart    choices + secure keys
    actions_service.dart     contacts, prefilled Messages/WhatsApp/Mail, App Store / Play Store
    interest_engine.dart     on-device recommender: signals, decay, Thompson sampling, ranking
    cheer_service.dart       cheer-up: learns your likes, picks a song/video (YouTube), meme or itch.io game, deletes after
  models/character.dart      the pet friends and how they unlock
  ui/                        the room, the pet, record panel, notes box, note page, letter card, app card, cheer card (YouTube song/video, meme, itch.io game), settings
  platform/                  phone vs browser: storage, speech, sign-in popup, CORS proxy helper
packages/cactus_native/      bundles the engine binary into the app
functions/api/fetch.js       Cloudflare Pages Function (web only): allow-listed CORS proxy
web/                         extra web files (oauth.html, _headers); Flutter adds the rest at build time
tool/cf_build.sh             Cloudflare Pages build script
tool/setup_platforms.dart    permissions, app id, iOS 16.4, copies the engine
```

Adding a friend: add a `PetCharacter` to `lib/models/character.dart` (colors, ears, tail, treats needed).
Adding a pet skill: add a tool in `LocalAi.toolsJson`, a `PetAction`, and a flow in `PetController`.

## Requirements

- iOS 16.4+ (Cactus engine minimum), Android 7.0+ (API 24). On-device AI runs on 64-bit ARM phones; elsewhere the app still works without it.
