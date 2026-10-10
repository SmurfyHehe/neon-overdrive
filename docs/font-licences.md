# Font licences

Every font in the game is under the SIL Open Font License 1.1 (OFL). That means
free to use and bundle in a game, no payment, no on-screen credit, and the fonts
may not be sold on their own. The full licence text is in
`THIRD_PARTY_LICENSES.txt`; each font file lives in `assets/fonts/`.

Source: official upstream releases (Google Fonts repository, `ofl/` folder; DSEG
from its GitHub release v0.46).

## Roles

Every text takes one role through `UiTheme.font(role)` (`scripts/ui/ui_theme.gd`).
`tests/ui/fonts.gd` fails on any system font or Godot default font.

| Role | Used for | Font |
|---|---|---|
| `logo` | BOOST SIMCADE wordmark (outlined in SVG) | Barlow Condensed SemiBold |
| `display` | screen titles, "NIGHT 7 OVER", big HUD speed and gear, slot headers, credits headings | Big Shoulders Display |
| `menu` | menu rows, Settings rows, summary rows, credits names, loading tip | Barlow Semi Condensed Regular |
| `menu_strong` | buttons, tabs | Barlow Semi Condensed SemiBold |
| `numbers` | tuner values, deltas, cash/bank, key names, benchmark | Share Tech Mono |
| `lcd` | head-unit clock, steering-wheel LCD, AFR/boost pod | DSEG7 Classic |
| `dial` | analogue gauge numbers, dash lamp labels | Barlow Semi Condensed |
| `subtitle` | Dale, scanner, people talking (dark outline, amber speaker name) | Barlow Semi Condensed SemiBold |
| `tv` | Graveyard TV text, scanner ticker | VT323 |
| `hand` | Walt's notes, whiteboard | Caveat |
| `road` | road and area signs, exit and distance signs | Overpass |
| `plate` | number plates (for now) | Share Tech Mono |

Shop signs and billboards use our own 5x7 pixel font in `building_signs.gd`. It is
a bitmap table, not a font file, so it has no licence entry.

## Adding a font

1. Download it from the official OFL source, keep its licence file.
2. Add the copyright line to `THIRD_PARTY_LICENSES.txt` and a row above.
3. Give it a role in `UiTheme`; do not call it by file path anywhere else.
