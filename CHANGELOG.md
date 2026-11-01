## 0.1.2

- Presenter: users can add their own presenter from a photo (a name, a stock
  voice, and their word that they may use the likeness), and remove it. Needs
  the StartupAid API from this release; older servers just don't offer it.
- Long price words from `priceLabel` no longer overflow: model cards grow to
  fit, the make button puts the price under its label, and the balance moves
  under the title instead of cutting it off.
- Words in the accent colour stay readable on pale brand colours.
- Film Maker scrolls in apps that listen for drags around the whole app, such as
  a keyboard dismisser. Its web view now takes its own touches.

## 0.1.1

- Docs: signatures now expire (`v2.<expiry>.<hex>`), and new widget keys
  take only those. Nothing changes in the API: return the new form from your
  `signer`.

## 0.1.0

First release.

- `StartupAidStudio.show()` and the `StartupAidStudio` widget: Pictures, Video
  (from a description or a picture), Voice (stock voices and music), Presenter
  (ready-made presenters) and Film Maker, in tabs, as the widget key allows.
- Film Maker: StartupAid's film editor in a web view, as its own tab or on its
  own with `StartupAidStudio.movieMaker()`.
- Looks: the key's light and dark themes from StartupAid's dashboard, with
  `StudioTheme` over them in code. Film Maker wears the same Look.
- Prices: shown as credits, hidden when the key hides them, or in your app's
  own words with `priceLabel`, in every tab. `onBudget` tells you what the user
  has left.
- `StudioClient` for use without the UI: `createImages`, `createVideo`,
  `upload`, `waitFor`, `assets` and the rest. Requests give up after `timeout`
  (30 seconds by default) with a `StudioException`, never a hang.
