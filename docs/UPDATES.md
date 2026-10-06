# In-app updates

How Deck Beat updates itself from this repository's GitHub releases, and how to make a release. It works the way pitch.dog's other Mac apps do (Drift 2, Galileo 2 and Backdrop; see [Drift's guide](https://github.com/bomkino/pitchdog-drift/blob/main/docs/UPDATES.md)), from Deck Beat 3.0.0 on.

No Apple Developer account is needed. Deck Beat is signed ad hoc. Updates are trusted because they carry a signature that only pitch.dog's private key can make, and the app has the matching public key built in.

## How it works

1. Every release carries four files: the disk image (for people), a ZIP of the app (for the updater), `appcast.xml` and `SHA256SUMS.txt`.
2. `appcast.xml` describes the newest version: its version number, its notes, the address of the ZIP, and an EdDSA signature of the ZIP.
3. The app's `Info.plist` names the feed `https://github.com/bomkino/deck-beat/releases/latest/download/appcast.xml`. GitHub always redirects that address to the `appcast.xml` of the release marked **Latest**.
4. Once a day, and whenever someone chooses **Deck Beat › Check for Updates…**, Sparkle reads the feed. If the version there is newer, it shows the notes and an Install button.
5. Sparkle downloads the ZIP and checks its signature against the public key in `Info.plist` (`SUPublicEDKey`). It refuses an archive that doesn't match. CI proves both on every push (below).
6. Sparkle swaps the app in place and relaunches it. The update isn't marked as downloaded from the web, so macOS doesn't ask for **Open Anyway** again.

The first version with updates, 3.0.0, has to be installed by hand once on each Mac. Every version after it arrives by itself.

## The key

| | Where |
|---|---|
| Public key (in `scripts/build.sh`, and so in the app's `Info.plist`) | `P43E8I+FgVyAW3QkS4J9bnDRRhAnsS4y3dT2WDce1lQ=` |
| Private key (signs releases) | `~/Library/Application Support/pitch.dog/Release Keys/sparkle-ed25519-private.key` on the release Mac, owner-only (`chmod 600`) |
| Backup | In the team's password manager, as a secure note holding the file's one line |

It is the same key as Drift, Galileo and Backdrop. Rules:

- **Never commit the private key, paste it into chat, or put it in a GitHub secret.** Releases are built by CI and signed on the Mac, so the key never comes near GitHub.
- **If it is lost:** installed copies can no longer update themselves. Make a new key, build the next version with the new public key, and install that version by hand once on each Mac.
- **If it leaks:** someone could sign a fake update, but they would also need to publish it as the Latest release here. Rotate anyway: release a version signed with the old key that carries the new public key, then sign only with the new one.

## Setting up the release Mac (once)

1. Sparkle's tools, from its official release, checked against its checksum:
   ```bash
   gh release download 2.10.0 -R sparkle-project/Sparkle -p "Sparkle-2.10.0.tar.xz"
   shasum -a 256 Sparkle-2.10.0.tar.xz   # c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
   mkdir -p ~/Library/Application\ Support/pitch.dog/Sparkle/2.10.0
   mkdir -p /tmp/sparkle && tar -xf Sparkle-2.10.0.tar.xz -C /tmp/sparkle && ditto /tmp/sparkle/bin ~/Library/Application\ Support/pitch.dog/Sparkle/2.10.0/bin
   ```
2. The private key file in `~/Library/Application Support/pitch.dog/Release Keys/`, from the password manager, with `chmod 700` on the folder and `chmod 600` on the file. A Mac already set up for Drift releases has both.
3. The GitHub CLI, signed in: `gh auth login`.

## Making a release

1. Raise `VERSION` in `scripts/build.sh` (always upwards) and add a section for it at the top of `CHANGELOG.md`, headed `## <version> (<date>)`. Merge to `main`.
2. Run the **release** workflow on `main` (Actions › release › Run workflow). It builds the app, packs the disk image and the ZIP, and publishes them on the release tagged `v<version>`, marked Latest, with the changelog section as its notes. Its `appcast.xml` offers no update yet, so nothing installs until the next step.
3. On the release Mac, from this repository:
   ```bash
   bash scripts/sign-release.sh 6.0.0 update-notes.md
   ```
   It downloads the release's ZIP, checks it against `SHA256SUMS.txt`, signs it, replaces the release's `appcast.xml` with the signed one, and prints the version the feed now offers. `update-notes.md` is optional: a few lines of Markdown for the update window.

Installed copies pick the update up within a day, or at once from Check for Updates…. Signing 3.0.0 itself isn't needed: no earlier version has the updater.

To make a whole release on the Mac instead, without CI: `bash scripts/build.sh release`, `bash scripts/pack-release.sh ../release`, `bash scripts/sign-release.sh ../release notes.md`, then publish the four files with `gh release create v<version> --latest`.

Things that break updates:

- **The asset must be called exactly `appcast.xml`**, on the release marked **Latest**. Drafts and pre-releases don't count.
- **Versions only go up.** Sparkle compares `CFBundleVersion`, which `build.sh` derives from the version: 6.0.0 is 60000. Never reuse or lower a version.
- **Sign the ZIP that is published.** `sign-release.sh` signs the release's own ZIP. If the ZIP is replaced, sign again; a stale signature is refused, as it should be.
- Don't delete the newest release, or its `appcast.xml`, while people may still be updating.

## How CI proves it

`scripts/test-updates.sh` runs in the `verify` workflow on every push:

- It downloads Sparkle 2.10.0's tools and checks their checksum, and makes a throwaway key with CryptoKit. The real key is never used.
- It builds a copy at 9.0.0 under another name and identifier ("Deck Beat Update Test", `dog.pitch.deckbeat.updatetest`) with the throwaway public key, then builds 9.0.1, packs it and signs it with `pack-release.sh` and `sign-release.sh`, and serves the feed from a local web server.
- It opens the 9.0.0 copy with `STUDIO_UPDATE_TEST=1` (check at once, install as soon as ready) and `STUDIO_UPDATE_FEED` (the local feed), and waits for it to become 9.0.1.
- It then changes one byte of the served ZIP, starts again from 9.0.0, and checks the copy stays at 9.0.0.

Both variables are read only from the environment, and a feed can't install anything that isn't signed with the key the app was built with. Command-line runs of the app (`--still`, `--snapshot`, `--export`) never start the updater.
