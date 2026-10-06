# Starter songs

Deck Beat comes with four songs you can use in anything you make, including client work, without
asking or crediting anyone. Each one is dedicated to the public domain under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/), and each was checked on
its own track page, not by artist or search filter. A new window starts on the first; the others
are under **Starter Songs** on the Song card.

| Song | Artist | Feel | Tempo | Length |
| --- | --- | --- | --- | --- |
| Retro Synths | HoliznaCC0 | bright synth-pop, a big drop at 0:16 | about 120 BPM | 3:43 |
| Roller Fever | Loyalty Freak Music | upbeat roller disco | about 130 BPM | 2:26 |
| Make Funk | HoliznaCC0 | steady, bass-led funk | about 99 BPM | 2:43 |
| Machines With Feelings | HoliznaCC0 | night-drive synthwave, a breakdown at 1:18 | about 100 BPM | 3:18 |

Credit isn't required, but both artists say they're glad of it.

## Where each licence is stated

All four come from the [Free Music Archive](https://freemusicarchive.org). On each track page, the
licence box under the play counts shows the CC0 badge and the sentence quoted below; the badge and
the words "CC0 1.0 Universal License" both link (`rel="license"`) to the CC0 1.0 deed. No other
Creative Commons licence appears on any of the four pages, and each page says "AI generated? No".
Checked on 6 October 2026.

| Song | Track page | On the page |
| --- | --- | --- |
| Retro Synths | [freemusicarchive.org/music/holiznacc0/power-pop/retro-synths](https://freemusicarchive.org/music/holiznacc0/power-pop/retro-synths/) | "Retro Synths by HoliznaCC0 is licensed under a CC0 1.0 Universal License." |
| Roller Fever | [freemusicarchive.org/music/Loyalty_Freak_Music/ROLLER_DISCO_DANCE_DANCE/…](https://freemusicarchive.org/music/Loyalty_Freak_Music/ROLLER_DISCO_DANCE_DANCE/Loyalty_Freak_Music_-_ROLLER_DISCO_DANCE_DANCE_-_01_Roller_Fever/) | "Roller Fever by Loyalty Freak Music is licensed under a CC0 1.0 Universal License." The artist's bio adds: "Do whatever you want with this, it's CC0." |
| Make Funk | [freemusicarchive.org/music/holiznacc0/bassic/make-funk](https://freemusicarchive.org/music/holiznacc0/bassic/make-funk/) | "Make Funk by HoliznaCC0 is licensed under a CC0 1.0 Universal License." |
| Machines With Feelings | [freemusicarchive.org/music/holiznacc0/waves-of-nostalgia-2/machines-with-feelings](https://freemusicarchive.org/music/holiznacc0/waves-of-nostalgia-2/machines-with-feelings/) | "Machines With Feelings by HoliznaCC0 is licensed under a CC0 1.0 Universal License." |

## The files

Each song was taken from the 320 kbps MP3 its page plays, and encoded once to AAC-LC at 160 kbps,
44.1 kHz stereo, with its tags removed. The masters are loud and peak above full scale, so each was
turned down by a fixed amount, with no compression, to sit near −14 LUFS with headroom (Machines
With Feelings also passed through a gentle peak limiter). No song was otherwise edited.

| File in `Resources/Songs` | Source MP3 (SHA-256) | Turned down | Loudness | File (SHA-256) |
| --- | --- | --- | --- | --- |
| `HoliznaCC0 - Retro Synths.m4a` | `0aba9efcd8b2d6b127ac69676e15c7364ba5e2ed0adc811a19aa2da2eb2ed1d7` | 3.5 dB | −13.9 LUFS | `954d2274924402997bd94cba1f29788db24ea1c10d979884a6432308df4a66b6` |
| `Loyalty Freak Music - Roller Fever.m4a` | `fa9986971c76189754b6592b83424b453dcb581fb1394f935f678eb4dba3d98f` | 1 dB | −14.0 LUFS | `7a0a61a62e279d2368f63d5cee02f6321939f3a6828e140f8feccb7cde6ba117` |
| `HoliznaCC0 - Make Funk.m4a` | `4631f55b7fc2a021f24b22f60ec87735cf9163638b3a79ac1719ea3515949f9c` | 5 dB | −13.8 LUFS | `3400fa7f058f3a1466e0936cae2848230c84fdde249fff0888835e8ab8b401dd` |
| `HoliznaCC0 - Machines With Feelings.m4a` | `abe5a49446af9a06514277dd4e585694cd0be70a4191ed9932a419f3086a4930` | 1.5 dB | −15.1 LUFS | `0c8dbd6a32d23ed50396924f8115233efcaefa4781f5c9c044d2bba5f82d78d3` |

`Resources/Songs/songs.json` lists them in menu order. To add a song, check its licence on its own
page, add the file and a line to `songs.json`, and record it here.
