# Changelog

## 3.0.1 (unreleased)

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
