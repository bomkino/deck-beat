# Deck Beat

Your deck, lit up by your music. A native Mac app from [pitch.dog](https://pitch.dog).

Drop in your slides and a song. Deck Beat lays the slides out in a grid, listens to the song (tempo, bars, drops and what each instrument is doing) and lights the slides up in time with it. Then it exports a finished video, 1080×1920 for Reels, TikTok and Shorts by default.

It is built on the same engine as Drift, Galileo Gallery and Backdrop, and it is free and open source under the AGPL.

## What it does

**Slides.** Drag in images, PDFs (each page becomes a slide) or video clips, or use File › Add Slides (⇧⌘I). Slides of any shape work, including decks made for wide screens such as 1920×1080 and 2576×1080. A Keynote or PowerPoint file gets a pointer to save it as a PDF first. Reorder slides in the sidebar. Star a slide to feature it more often; the first starred slide becomes the cover. A new window opens on a 15-slide sample deck so there is something to play with straight away.

**A song.** Drag in any audio file, or a video whose sound you want (MP3, AAC, WAV, AIFF, MOV, MP4), or use File › Choose Song (⇧⌘O). Deck Beat finds the tempo, the beats, the bars and the drops. Until you add one, a synthesised 34-second demo groove plays.

**Fixing the beat.** If Deck Beat hears a song at half or double its real speed, set it to ½× or 2×. *Bars start on beat* moves bar one to the second, third or fourth beat, and *Nudge* slides the whole grid up to 150 ms earlier or later.

**Looks.** Seven starting points, each a complete set of the settings below:

| Look | What it does |
| --- | --- |
| Screening Room (default) | Slides wait in the dark and come up in colour on the beat. Every fourth bar, one steps forward to be read. |
| Night Shift | A block of flats after dark. The music decides who is home. |
| Ripple | Each kick sends a ring out from the middle. Snares start smaller rings of their own. |
| Read-through | The light reads the deck in order, one slide per beat. |
| Equaliser | Bass on the left, cymbals on the right. Each column fills to the level of its part of the song. |
| Gallery Wall | The grid hung on an angled wall above a polished floor. For slower songs and quieter work. |
| Light Box | A pale room for light decks. Resting slides go grey; playing slides come back in colour. |

**The grid.** Columns (1–12), rows (1–20), gap, corner radius, cell shape (auto, slide, fill or square), margins that keep the grid clear of each app's buttons and captions, an optional angled wall with a reflection, and slide order. A new project's grid follows the deck: it refits as you add or remove slides, change the canvas or add a caption, until you set its size by hand. The fit picks slide-shaped cells that fill the frame, or filled cells that keep at least 65% of each slide, so 15 slides at 2576×1080 get a 2×8 grid of whole slides in a 1080×1920 Reel. *Auto* keeps a slide whole wherever filling its cell would crop more than 40% of it. With more slides than cells, resting cells turn over on the downbeats so every slide gets seen; with fewer, every slide shows before any shows twice, and repeats are kept apart.

**Rest and lit.** Two states, each with its own size, brightness, colour, opacity, lift, tilt, glow, blur, shadow and tint. You set how quickly a slide lights (attack), how long it holds, how long it fades (tail), how much it bounces, and how it idles between beats (still, breathe, float or sway).

**Five ways to light up.**
- *Pulse:* a few slides on every beat, more on the bar.
- *Ripple:* rings from the middle on the kick.
- *Equaliser:* each column a level meter.
- *Read-through:* the deck in order, one slide per step.
- *Lights On:* bass lights the lower floors, hats the roof.

Every mode can *feature* a slide every 1–16 bars, bringing it forward, big enough to read and always inside the frame, then back to its own cell. Drops get a breath before them and a centre-out hit on them. The engine keeps it watchable: away from the drops and the intro, no more than 40% of the grid is lit at once.

**Intro and ending.** The video opens cold on the cover, never black, and deals the rest of the deck into place in time with the music. You choose the entrance (deal, rise, depth, flip, drop, assemble or unfold), the order (centre out, diagonal, reading, spiral, columns, rows or random) and the length. *Land on the drop* starts the clip so the cover lands on the song's first drop.

The ending can be:
- *Loop:* the last frame meets the first, so the video loops seamlessly.
- *Close:* the cards leave and the cover holds.
- *Lights Out:* the slides go dark one by one.
- *Auto:* Loop for clips of 30 seconds or less, Close for longer ones.

**Titles.** A title and a line above it, such as a date or a client, set large and centred or small in a corner. It can open the video, close it like an end card, or stay throughout as a caption, which the grid moves over to make room for.

**The room.** Eighteen Backdrop styles behind the grid, in your palette or in colours taken from your slides. *Atmosphere* lets the room answer the song: the backdrop lifts on the kick, the light flares on a drop. *Finish* sets the cards' surface (original, print, satin or gloss), bloom, grain, vignette, shadows and motion blur.

**A transport that knows the song.** The clip's waveform, beat and bar marks, bar numbers, drops, and the moments a slide steps forward, with the whole song below and the clip as a bracket you can drag along it. *Best Part* moves the clip to the strongest stretch of the song. Clips run 15, 30, 60 or 90 seconds, or the whole song.

**Export (⌘E).** MP4 (H.264), HEVC, ProRes 422 HQ, ProRes 4444, PNG frames or a still. In any of the frames the toolbar offers (Reel 1080×1920, portrait 1080×1350, square, landscape 1920×1080, cinema and 4K), at 24, 25, 30 or 60 fps, with motion blur and the song's sound. The preview and the export come from the same renderer, so what you see is what you get.

**New Variation (⇧⌘R)** re-rolls the seed. One seed drives every random choice, so the same seed always makes the same video.

## Build and run

You need macOS 14 or later on Apple silicon, and Xcode or the Command Line Tools with a macOS 26 SDK.

```sh
bash scripts/build.sh            # builds "Deck Beat.app" into ../dist
open "../dist/Deck Beat.app"
```

During development you can also run `swift run DeckBeat`.

## Check it

```sh
swift run -c release beat-lab check                  # song analysis, layout, plans and every scene, on the CPU
swift run -c release beat-lab bench                  # how long listening and planning take
swift run -c release beat-lab render --out lab       # contact sheets of every Look and of wide decks, a 15 s demo clip with sound,
                                                     # and export timings
bash scripts/verify.sh                               # all of the above, plus headless stills of every Look
```

The `verify` workflow runs `beat-lab check`, `bench` and `render` on every push, then opens the app on decks of 2576×1080 and 1920×1080 slides, and keeps the renders and captures as an artifact.

The app can also render a still without opening a window, which is how `verify.sh` checks the Looks:

```sh
"../dist/Deck Beat.app/Contents/MacOS/DeckBeat" --still out.png --look ripple --format reel --time 2
```

## How it is put together

| Module | What it holds |
| --- | --- |
| `RenderCore` | GPU context, colour, finishing, image and video writing |
| `BackdropKit` | the Backdrop engine: generative, loopable backgrounds in Metal |
| `StageKit` | the shared stage: cards in 3D, scenes, export |
| `StudioKit` | the shared design language, controls, inspector and export sheet |
| `BeatKit` | listening to the song (`Analysis.swift`), the grid (`Layout.swift`), the choreography (`Plan.swift`), the scene (`BeatScene.swift`), the Looks and the demo deck and groove |
| `DeckBeatApp` | the app |
| `DeckBeatLab` | `beat-lab`, the headless checks and renders |

A Deck Beat project (`.deckbeat`) is a package holding `project.json` and a `Media` folder with the slides and the song.

The choreography is planned once per clip, ahead of time, as a list of light triggers per cell. So playback, scrubbing and export are pure functions of time, and a loop's last frame meets its first exactly.

## Next

- Tap tempo, for songs with no clear beat.
- Words on the beat: a line of text, one segment per bar, above the grid.
- A muted preview, since most reels autoplay without sound.
- Covers exported with the video: frame 0 and the fully lit grid as PNGs.
- The top three Best Part choices, not just the first.

## Licence

Deck Beat is free software under the [GNU Affero General Public License v3.0](LICENSE). Third-party notices are in [NOTICES.md](NOTICES.md). The names and marks are covered in [TRADEMARKS.md](TRADEMARKS.md).
