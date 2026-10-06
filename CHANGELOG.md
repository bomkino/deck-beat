# Changelog

## 2.0.0 (unreleased)

Made for wide decks in tall videos, and faster.

- Decks of 1920×1080 and 2576×1080 slides fit a 1080×1920 Reel. A new project's grid follows the deck as slides come and go, the canvas changes or a caption is added, until you set it by hand. Fitting keeps slides whole, or keeps at least 65% of each. *Auto* cells keep a slide whole wherever filling would crop more than 40% of it. The Grid page offers sizes of about 15, 24, 30 and 60 slides and says how much of each slide a filled cell crops.
- The slide stepping forward stays inside the frame for every canvas, slide shape, wall and spotlight.
- A featured slide comes home to its own cell, never shows twice at once, and is never swapped out while it is away.
- A deck smaller than the grid shows every slide before any repeats. It used to skip some: 20 slides on a 3×7 grid showed only 12 of them, and 14 on 3×5 only 11.
- Fixing the beat: half or double time, which beat bars start on, and a nudge.
- Titles: a title card that opens or closes the video, or a caption that stays, which the grid makes room for.
- Keynote and PowerPoint files get a pointer to save them as PDF. Slides' real shapes are read as they are added.
- Backdrop 2.0: six new styles (solid, linear, radial, conic, caustics and iris), and seamless loops.
- Projects from 1.0 open, with every new setting at its default, and unknown or missing settings never stop a project opening.
- Faster: planning a 12×20 grid takes 3–7 ms instead of 33–41 ms on the same machine, plans and compositions are remembered between frames, Look previews are worked out off the main thread, flat cards draw as two triangles, and export encodes the next frame while the GPU draws the last.
- `beat-lab bench`, wide-deck contact sheets, export timings and nine new checks.

## 1.0.0 (unreleased)

The first version of Deck Beat.

- Slides from images, PDFs and video clips, by drag and drop or from the File menu, with reordering and stars. A new window opens on a 15-slide sample deck.
- Any song or video's sound, by drag and drop. Deck Beat finds the tempo, beats, bars and drops. A synthesised demo groove plays until a song is added.
- Seven Looks: Screening Room, Night Shift, Ripple, Read-through, Equaliser, Gallery Wall and Light Box.
- Five lighting modes (Pulse, Ripple, Equaliser, Read-through and Lights On), featured slides every 1–16 bars, and a breath and a hit on every drop. Away from the drops, no more than 40% of the grid is lit at once.
- A grid of 1–12 columns and 1–20 rows, with gap, corners, cell shape, safe margins, an angled wall and slide order. *Fit the Grid to My Deck* picks the grid for you. Larger decks rotate through the cells.
- Rest and lit states, each with size, brightness, colour, opacity, lift, tilt, glow, blur, shadow and tint, plus attack, hold, tail, bounce and idle motion.
- An intro that opens cold on the cover and deals the deck in on the beat, with seven entrances and seven orders. It can land on the song's first drop.
- Loop, Close and Lights Out endings. A loop's last frame meets its first.
- Twelve Backdrop styles, deck colours, and an atmosphere that answers the song.
- A transport that shows the clip's waveform, bars, drops and featured moments, with the whole song below it, a draggable clip and Best Part.
- Export to MP4, HEVC, ProRes 422 HQ, ProRes 4444, PNG frames or a still, with the song's sound, at 1080×1920 by default.
- `beat-lab`, headless checks and renders, run by CI on every push.
