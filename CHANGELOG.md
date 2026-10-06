# Changelog

## 6.0.0 (2026-10-06)

The board builds on the beat. A video can now open on the empty room and put one slide down on each beat, scattered, each slide answering afterwards to the sound that placed it. Three new endings, idle and active presets, collages for decks of mixed shapes, walls of fifty slides or more, titles in pitch.dog type, four starter songs, and transparent exports like Drift's. 6.0 follows 3.0.1; there was no 4 or 5.

- **Building on the beat.** *In & out* sets how the board comes in: *Together* (dealt over the opening bars, as before), *Beat by beat* or *On every hit*. A build opens on the empty room and lands a slide on each beat (a bar down to a sixteenth, to suit the size of the deck) or on the song's own kicks, snares and hats. Each lands far from the ones before it, and the cover lands last, on the drop. The landing is always on the beat.
- **Voices.** Each slide keeps the sound that placed it. With the *By sound* entrance a kick slide drops in with weight, a snare slide snaps in from the side, a hat slide pops up and glints. The new *Voices* mode carries this on after the build, so kick slides thump on the kick, snare slides on the snare and hat slides glint with the hats.
- **Three endings.** *Leave on the beat* empties the board the way it filled, back to the empty room, so the clip loops. *Curtain call* bows across the board in a wave, then each slide leaves in its own time and the cover takes the last bow. *Drift away* lifts the slides off like paper in a draught, slower and slower, while the room dims round the cover. *Auto* picks Leave on the beat or Curtain call for a board that builds. Every ending is a card on the *In & out* page.
- **Idle and active.** Rest and lit are now called idle and active. The Slides page opens on eight pairs, each shown on your cover: Dim to bright, Grey to colour, Soft to sharp, Ghost, Spotlight, Neon, Paper and Pop.
- **Feel**, from tight to human: take-offs a touch early or late, every slide overshooting and turning a little differently, curved paths, and each slide idling at its own pace. The landings stay exactly on the beat.
- **Four new Looks**, eleven in all. *Beat by Beat* builds on the beat and leaves on it. *Paste-up* pins prints to a paper wall on the song's hits, a little crooked, and lets them float away. *Mosaic* is for fifty slides or more: rings of light cross the wall, the camera reads one slide every four bars, and the rows take a bow. *Afterglow* is slow and warm, for ballads and thank-yous, and drifts away round the cover.
- **Collage.** The Grid page offers *Grid* or *Collage*. A collage keeps every slide at its own shape, in rows or columns that fill the frame, with even gaps and nothing cropped. A new project whose slides come in mixed shapes lays itself out as a collage, up to 100 slides; a deck of one shape still gets its grid. Every move works on a collage.
- **Loose**, from tidy to a paste-up: each slide a little turned, off its mark and smaller. A slide held up to be read is always square.
- **Fifty slides or more.** Fitting goes up to 12 across with a finer gap for big decks, and the Grid page offers sizes of about 15, 30, 60 and 100.
- **Titles in pitch.dog type.** PD Head and PD Eyebrow from pitch.dog's type system are built in, and new titles use them: the title in PD Head 600 (upright or italic), the line above in PD Eyebrow. Saved titles keep their face. *Words on the beat* can *Land* (as before), *Pop* (each group grows in with a small overshoot, full size on its beat) or *Reveal* (each group rises from behind its own line). The type moves, but its weight never changes.
- **Starter songs.** Four CC0 songs come with the app: Retro Synths, Make Funk and Machines With Feelings by HoliznaCC0, and Roller Fever by Loyalty Freak Music. A new window starts on the first, and the Song card offers the others and the demo groove. Where each came from, and how its licence was checked, is in [docs/SONGS.md](docs/SONGS.md).
- **Transparent exports, like Drift's.** The Stage page and the export sheet offer a *Background* of Backdrop or Transparent. Transparent HEVC is a .mov with alpha, ProRes 4444 has straight alpha, and PNG frames and stills keep the shadows as soft alpha. The stage shows a checkerboard where the room would be. The vignette and the mirror floor stay out of transparent frames, and a title card's dimming is halved.
- **The latest Backdrop.** The engine now matches Backdrop 2.2 and Drift 2.5: 35 Backdrop styles in eight families on the Stage page, PNG frames compressed on four cores, and the fixes since Galileo's Backdrop 2.0.
- **Clear of the buttons.** A new *Clear* margin keeps the whole grid off a Reel's button column and caption, not just the slide being read.
- **Show Safe Areas** (View menu, ⇧⌘') draws where a Reel's buttons and caption sit.
- **Sound off.** A speaker switch in the transport mutes the preview, since most Reels first play silent. Exports keep their sound.
- Big decks load gently, three slides at a time, and files that can't be read are named in one note. Exports are named after the document and the Look. ⌘P plays and pauses.
- A project saved by a newer Deck Beat opens with a note and is never saved over. Projects from 1.0, 2.0 and 3.0 open as they were.
- `beat-lab`: thirteen new checks (the build on the beat and on every hit, voices, restraint after a build, every ending, the loop seam of Leave on the beat, collage shapes and poses, fitting 50 to 150 slides, Loose, the presets, 3.0 projects in 6.0, words that pop and reveal) and transparent exports checked as Drift checks them. `beat-lab bench` times Mosaic on collages of 60 and 100 mixed slides. CI captures the new Looks, builds, endings, collages and titles in a 1080×1920 Reel with 2576×1080, 1920×1080 and mixed slides.

## 3.0.1 (2026-10-06)

- In a Reel with Safe margins, a slide held up to be read stays clear of the platform's buttons and caption. A featured slide stepping out, a zoom and the cover at the start now sit in the room the app's interface leaves, a little left of centre and a little smaller. In 3.0.0 they ran up to 111 px under the like and comment buttons. The grid stays centred, so its right-hand edge can still pass under the buttons. Other canvases change little or not at all.
- `beat-lab`: a new check keeps a held-up slide clear of the platform's interface in a Reel, for 2576×1080 and 1920×1080 decks.

## 3.0.0 (2026-10-06)

The first public release, with everything from 1.0 and 2.0 below. New in 3.0: drops that re-form the grid, a zoom on a featured slide, new ways to turn over, a room that takes the slides' colour, words that land on the beat, and updates that install themselves.

- Drops: besides lighting from the middle out, a drop can *weave* (each slide comes apart into threads over the bar before and knits back on the hit), or break the grid into a *tunnel*, a *fan* like a hand of cards, or a *strip* that steps along on every beat, coming home on a later downbeat. A drop too close to the intro, the ending or the next drop falls back to lighting up.
- A featured slide can be zoomed into where it hangs, the camera moving straight in and the grid falling away round the edges, inside the safe area for every canvas and slide shape. A slide that steps out now starts from its cell exactly as shown.
- Cells turn over as blinds, a wipe or a page, as well as a flip. The intro gains Blinds, Page and Weave entrances.
- *Slide colour*: the room leans towards the colours of the slides in view, as the camera sees them, so it follows a zoom or a slide out front.
- *Words land on the beat*: the line above lands first, then the title a few words at a time, each falling onto a beat (half beats when there are more words than beats). A looping caption lifts them off in reverse before the loop turns. Title lines are balanced, so a title never ends on one stray word.
- The seven Looks use the new moves: Screening Room zooms and fans, Ripple opens a tunnel, Read-through lays slides down like pages and runs them past as a strip, Equaliser weaves, Gallery Wall walks up to each slide, Night Shift and Light Box turn over as blinds.
- In-app updates with Sparkle: Deck Beat checks this repository's latest release once a day and on *Check for Updates…*, and installs an update only when it is signed with pitch.dog's update key. This version has to be installed by hand once; later versions arrive by themselves.
- Projects from 1.0 and 2.0 open with the moves they had.
- `beat-lab`: seven new checks (every drop move, turn and feature style on small and large decks, the loop seam, the zoom inside the frame and the safe area, words on the beat, restraint round the new drops, and 2.0 projects in 3.0) and two sheets of the new moves. CI captures each move in a 1080×1920 Reel with 2576×1080 and 1920×1080 slides, and proves an update end to end with a throwaway key.

## 2.0.0 (not released on its own)

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

## 1.0.0 (not released on its own)

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
