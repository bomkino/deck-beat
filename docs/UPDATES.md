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
| Private key, for signing in CI | The `SPARKLE_PRIVATE_KEY` secret of this repository's `release` environment, which only `main` may use |
| Private key, on the release Mac | `~/Library/Application Support/pitch.dog/Release Keys/sparkle-ed25519-private.key`, owner-only (`chmod 600`) |
| Backup | In the team's password manager, as a secure note holding the file's one line |

It is the same key as OOO, Drift, Galileo and Backdrop, and each of their repositories holds it the same way.

### Signing in CI, and what that costs

Since 6 October 2026 the release workflow signs every release itself, so nobody runs a command on a Mac to make an update reach people. Before that, the key never left the release Mac. Keeping it as a GitHub secret is a trade:

- **Gained:** a release is one click (or one request to Claude), and it goes out already signed. No release ever sits on the Latest slot with an empty feed.
- **Given up:** the key now also lives on GitHub, in five repositories. GitHub stores it encrypted and masks it in logs, and only a workflow job that names the `release` environment, on `main`, is given it. So anyone who can push a workflow to `main` of any of the five repositories, or who takes over the GitHub account, could sign an update for all five apps. Before, they would also have needed the Mac.

The release job keeps its exposure small: it uses only GitHub's own `actions/checkout`, writes the key to a file only the runner can read, uses it once through Sparkle's `--ed-key-file`, and deletes it.

Rules:

- **Never commit the private key, paste it into chat, or print it in a workflow.** It reaches GitHub only through `scripts/auto-signing-setup.sh`, which hands the file to `gh secret set`.
- **If it is lost:** the backup restores it. Without it, installed copies can no longer update themselves: make a new key, build the next version with the new public key, and install that version by hand once on each Mac.
- **If it leaks, or you suspect a repository or the account was compromised:** delete the secret from all five repositories at once (below), then rotate: release a version signed with the old key that carries the new public key, then sign only with the new one.
- **To go back to signing on the Mac only:** `for r in deck-beat ooo pitchdog-drift galileo-gallery backdrop; do gh secret delete SPARKLE_PRIVATE_KEY --env release -R bomkino/$r; done`. The release workflow then stops at its first step, and `sign-release.sh` signs on the Mac as before.

## Turning on automatic signing (once)

On the Mac that holds the key, with the GitHub CLI signed in:

```bash
cd ~/deck-beat && git pull && bash scripts/auto-signing-setup.sh
```

For each of the five app repositories it makes a `release` environment that only `main` may use and sets the key in it as `SPARKLE_PRIVATE_KEY`. `gh` prints `✓ Set Actions secret SPARKLE_PRIVATE_KEY for bomkino/<repo>` five times, then the script says Done. Running it again is harmless.

## Making a release

1. Raise `VERSION` in `scripts/build.sh` (always upwards) and add a section for it at the top of `CHANGELOG.md`, headed `## <version> (<date>)`. Merge to `main`.
2. Run the **release** workflow on `main` (Actions › release › Run workflow). It builds the app, packs the disk image and the ZIP, signs the update with the key, checks the signature with the public key inside the app (as Sparkle will), and publishes all four files on the release tagged `v<version>`, marked Latest, with the changelog section as its notes and in the update window. Then it downloads the release before it, opens that copy against the live feed, and waits for it to update itself to the new version.

Installed copies pick the update up within a day, or at once from Check for Updates….

**Rehearse** (a box in Run workflow) does everything except publish, and updates a copy of the release before Latest from the live feed. It's the way to check the key and the workflow without releasing anything.

Without CI, on a Mac that holds the key and Sparkle's tools (in `~/Library/Application Support/pitch.dog/Sparkle/2.10.0/bin`, from [Sparkle's 2.10.0 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0), checksum `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`): `bash scripts/build.sh release`, `bash scripts/pack-release.sh ../release`, `bash scripts/sign-release.sh ../release notes.md`, then publish the four files with `gh release create v<version> --latest`. `bash scripts/sign-release.sh <version>` signs a release that is already published.

Things that break updates:

- **The asset must be called exactly `appcast.xml`**, on the release marked **Latest**. Drafts and pre-releases don't count.
- **Versions only go up.** Sparkle compares `CFBundleVersion`, which `build.sh` derives from the version: 6.0.0 is 60000. Never reuse or lower a version.
- **Sign the ZIP that is published.** The workflow signs the ZIP it publishes, and `sign-release.sh <version>` signs the release's own ZIP. If the ZIP is replaced, sign again; a stale signature is refused, as it should be.
- Don't delete the newest release, or its `appcast.xml`, while people may still be updating.

## How CI proves it

`scripts/test-updates.sh` runs in the `verify` workflow on every push:

- It downloads Sparkle 2.10.0's tools and checks their checksum, and makes a throwaway key with CryptoKit. The real key is never used.
- It builds a copy at 9.0.0 under another name and identifier ("Deck Beat Update Test", `dog.pitch.deckbeat.updatetest`) with the throwaway public key, then builds 9.0.1, packs it and signs it with `pack-release.sh` and `sign-release.sh`, and serves the feed from a local web server.
- It opens the 9.0.0 copy with `STUDIO_UPDATE_TEST=1` (check at once, install as soon as ready) and `STUDIO_UPDATE_FEED` (the local feed), and waits for it to become 9.0.1.
- It then changes one byte of the served ZIP, starts again from 9.0.0, and checks the copy stays at 9.0.0.
- It signs 9.0.1 once more with a second throwaway key, which the app doesn't trust, and checks that `sign-release.sh` stops before writing a feed. That is the check that keeps a wrong key from ever publishing.

After every release, and in every rehearsal, the release workflow runs `scripts/test-live-update.sh`: it downloads the release before Latest, opens it against the real feed with `STUDIO_UPDATE_TEST=1`, and waits for it to update itself to the Latest version, as every installed copy will.

Both variables are read only from the environment, and a feed can't install anything that isn't signed with the key the app was built with. Command-line runs of the app (`--still`, `--snapshot`, `--export`) never start the updater.
