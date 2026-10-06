# Notices

Deck Beat is released under the GNU AGPL 3.0 (see `LICENSE`). It has no package dependencies beyond the Swift toolchain and the macOS SDK. The work credited below keeps its MIT licence.

## Type

No fonts are bundled. The interface is set in the system font. Titles set into exported video use faces that ship with macOS (Avenir Next, Helvetica Neue, Didot and Futura), drawn by the operating system at render time.

## Sound

No recordings or samples are bundled. The demo groove a new project opens with is synthesised in code (`Sources/BeatKit/DemoGroove.swift`). Songs you add are decoded with Apple's AVFoundation, part of macOS.

## webgl-noise

Simplex noise in `Sources/RenderCore/ShaderPrelude.swift` is ported from webgl-noise.

Copyright (C) 2011 Ashima Arts. Copyright (C) 2011–2016 Stefan Gustavson. Released under the MIT License:

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## LUMEN

The Soft Bloom look in `Sources/BackdropKit/BackdropShaders.swift` follows the region structure and distributions of LUMEN's "bloom" mode (Leonxlnx/lumenshaders), re-authored with OKLab over-painting and exact integer orbits.

Copyright (c) 2026 Leonxlnx. Released under the MIT License (text as above).

## Research sources

Look and scene designs draw on the pitch.dog Batch One research collection, the Drift 0.5.1 creative catalogue and the Galileo scene-atelier prototypes (the scenes live in StageKit and the backgrounds in BackdropKit, which Deck Beat shares with Drift, Galileo and Backdrop). Their maths was re-implemented; no code from those projects is included.
