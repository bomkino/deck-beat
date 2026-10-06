# pitch.dog fonts

Titles set in **pitch.dog** and **pitch.dog Italic** use these two fonts, copied unchanged from
[pitch.dog type system](https://github.com/bomkino/pitchdog-type-system) v3.0.0,
`pitchdog-font-handoff/02-NATIVE-VARIABLE`:

| File | Family | Axes | Used for | SHA-256 |
| --- | --- | --- | --- | --- |
| `pd-head.ttf` | PD Head | weight 265–900, italic 0–1 | the title, at 600 (`social.display`) | `9015430e7dd334d0b0fd88021e023990cec6b683e37852581a3f3559c93c9c3e` |
| `pd-eyebrow-full.ttf` | PD Eyebrow | weight 100–900, width 87.5–100, italic 0–1 | the line above, at 500 and width 87.5 (`social.metadata`) | `a591f8497e9e2043fd5e0ffa2f922ad8a25e261763232493ba352f0d525d8f92` |

The font binaries are dedicated to the public domain under CC0 1.0 Universal; see
[LICENSE-CC0-NOTE.md](LICENSE-CC0-NOTE.md). The names pitch.dog, PD Head and PD Eyebrow are
not covered by CC0; see [TRADEMARKS.md](../../TRADEMARKS.md).

The app loads them straight from its bundle for its own use and never installs them. Following
the type system's rules, it sets them only at its anchor weights and never animates the weight.
