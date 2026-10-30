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
