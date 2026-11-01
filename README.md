# startupaid_studio

StartupAid's Create studio as a Flutter widget. Your app's signed-in users
make AI pictures, video clips, voices, presenter videos and whole films.
They're paid from your StartupAid AI credits, within the daily limits you set
on the widget key, and each user only ever sees their own work.

## Install

```sh
flutter pub add startupaid_studio
```

Or straight from GitHub:

```yaml
dependencies:
  startupaid_studio:
    git:
      url: https://github.com/StartupAid-Org/startupaid-flutter.git
      ref: v0.1.0
```

Picking a photo to animate uses `image_picker`, and Film Maker uses
`webview_flutter`: on iOS add `NSPhotoLibraryUsageDescription` to
`Info.plist`, and on Android make sure the app has the `INTERNET` permission.

## Set up

1. In StartupAid, open **Developers → Studio widget** and make a widget key.
   Copy the public key (`pk_live_…`) and the signing secret (`sks_…`).
2. On your server, behind your own sign-in, sign each user's id with an
   expiry: `v2.<expiry>.<hex(HMAC-SHA256(signingSecret, userId + "." + expiry))>`,
   where expiry is a Unix time in seconds, up to a day ahead (an hour is
   plenty). Never put the secret in the app. Use a `signer`, so the widget
   asks your server again whenever it starts a new session:

   ```js
   const expires = Math.floor(Date.now() / 1000) + 3600;
   const mac = crypto.createHmac("sha256", secret).update(`${userId}.${expires}`).digest("hex");
   const signature = `v2.${expires}.${mac}`;
   ```

   Keys made before expiring signatures also take the old, never-expiring
   `hex(HMAC-SHA256(signingSecret, userId))` until you switch that off.
3. In the app:

```dart
final client = StudioClient(
  publicKey: 'pk_live_…',
  userId: me.id,
  signer: (userId) => myApi.studioSignature(),
);

final picked = await StartupAidStudio.show(
  context,
  client: client,
  features: const [StudioFeature.images, StudioFeature.video],
  prompt: 'A poster for my show',
);
if (picked != null) useIt(picked.url);
```

`StartupAidStudio` is also a plain widget (`onSelected` gets the pick), and
`StudioClient` can be used without any UI: `createImages`, `createVideo`,
`upload`, `waitFor`, `assets`.

## What it offers

Whatever the widget key allows, in tabs: **Pictures**, **Video** (from a
description or a picture), **Voice** (speech in the stock voices, or music),
**Presenter** (a ready-made presenter, or the user's own from a photo, says a script on camera) and **Film
Maker** (below). Pass
`features:` to show fewer. Voices made of real people and an account's own
avatars are never offered to an app's users.

## Film Maker

With **Films** on the widget key, the studio gets a **Film Maker** tab, with
the editor right there in the tab. You can also open it on its own:

```dart
final film = await StartupAidStudio.movieMaker(context, client: client);
if (film != null) useIt(film.url); // kind "film"
```

`StartupAidStudio.show(features: [StudioFeature.movies])` does the same. It
wears the studio's Look (the key's, with your `theme` over it) and shows
prices the same way the other tabs do: hidden when the key hides credits, or
in your own words through `priceLabel`, which it calls for each figure it
shows. It's
StartupAid's own film editor (stories or screenplays, a cast, scenes, voices,
music), in a web view signed in as the client's user, through the same
signature as everything else. The user sees only their own films, and what it
spends counts against their daily credits. Films cost the most, so raise the
key's daily credits to use it. `StudioClient(webUrl: …)` points it at a
StartupAid site other than startupaid.org.

Needs `webview_flutter`'s platform setup (it's a dependency of this package):
nothing on iOS, and the `INTERNET` permission on Android.

## Prices and what's left

The key's "What users see" setting (in the dashboard) shows or hides credit
figures, and turns the low-allowance warning on or off. Hidden, users see no
numbers at all; limits are still explained in words.

To show prices in your own terms instead (say you charge in coins), give a
`priceLabel`. It shows even when the key hides credits. `onBudget` tells you
what the user has left whenever it changes, so you can offer more your way:

```dart
StartupAidStudio.show(
  context,
  client: client,
  priceLabel: (credits) => '${credits * 2} coins',
  onBudget: (b) {
    if (b.remaining < 20) showTopUp();
  },
);
```

## How it looks

Set the Look on the widget key in **Developers → Studio widget**: a light
palette and a dark palette (brand colour, button fade, background, cards),
whether to match the phone or stay light or dark, and sharp, rounded or round
corners. The widget picks it up the next time it opens; no app release.

To fix any of it in code, pass a `StudioTheme`. Anything set here wins over
the dashboard; anything left unset follows it, then your app's own theme:

```dart
StartupAidStudio.show(
  context,
  client: client,
  theme: const StudioTheme(
    mode: StudioThemeMode.system,
    corners: StudioCorners.round,
    fontFamily: 'Inter', // a font your app already bundles
    light: StudioPalette(accent: Color(0xFF7C3AED), accentEnd: Color(0xFFDB2777)),
    dark: StudioPalette(accent: Color(0xFFA78BFA), background: Color(0xFF0B0A12)),
  ),
);
```

Button text is white or near-black, whichever reads better on your colours.

## Try it

`example/` runs the widget against a pretend studio, with no key needed:
`cd example && flutter run`. Film Maker needs a real key: add
`--dart-define=STUDIO_KEY=pk_live_…`, `STUDIO_USER` and `STUDIO_SIG` (and
`STUDIO_WEB`/`STUDIO_API` for a site and API other than startupaid.org's),
and the studio and its "Make a film" button use it. Add `--dart-define=LOOK=dark` (or `light`) to
fix the mode.

## What to expect

- Pictures come back in seconds. Clips take a minute or two. The widget
  checks on them, and `studio.asset.ready` / `studio.asset.failed` go to your
  webhook if you've added one.
- A clip can start from a picture the user uploaded or made in the studio.
  Pictures from anywhere else are refused, so every face that's animated is
  on record against the user who sent it.
- Refusals arrive as `StudioException` in words fit to show the user.
  `outOfCredits` is true when their daily credits, or the key's, are used up.
