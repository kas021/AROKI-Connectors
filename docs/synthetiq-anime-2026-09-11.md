# Synthetiq Anime 0.1.0 — beta publication

Requires **Aroki 2.0.38 (51)** or newer with contextual-hls-v1,
numbered-catalogue-v1 and catalogue-fallback-v1. Older apps keep their existing
sources but cannot install this new connector. This publication does not update
the app itself.

Refresh the collection, add **Synthetiq Anime (BETA - Testing only)** and select
it. The existing tested identity `synthetiq-anime-testing` is retained so moving
from the testing collection does not invent another source identity. Synthetiq
One and all previously published entries are unchanged.

Manifest version 0.1.0 SHA-256:
`f83d4fb3a28b69f275e388b62c4816c74c93bfce5eee5ea2f3163b175b1a8fed`.
The candidate bytes are identical to the owner-tested testing release.

## Evidence and limitations

- Earlier frozen 30-title matrix: 166/168 episode/audio routes returned validated
  HTTP media; 156 also returned nonempty parsed captions. Two unavailable routes:
  One Piece episode1177 Dub and Gintama episode201 Dub.
- Fresh pre-publication middle-episode Sub probes: Naruto, One Piece, Bleach,
  Death Note, Fullmetal Alchemist: Brotherhood, Attack on Titan, Demon Slayer,
  Jujutsu Kaisen, Spy × Family and Chainsaw Man passed exact catalogue-ID and
  HTTP media checks. A rate-limit signal on the next title stopped the run;
  20 of the planned 30 therefore remain blocked/unrun in this rerun, not passed.
- iPhone 15 Pro Max short playback/seek checks passed for Naruto episode1 Sub/Dub,
  Death Note episode1 Sub and Spy × Family episode1 Dub-labelled route. The owner
  also reports successful use. Automated playback tests were muted and do not
  prove correct spoken language or visible caption rendering.
- Local regression: 499 tests, zero failures, 24 intentional skips (includes
  three unrelated preserved prototype tests). CI runs the committed subset.
- Known historical Spy × Family Dub/Japanese-dialogue concern is not independently
  cleared. Listen to dialogue rather than trusting a Dub label. Your Name,
  A Silent Voice and sampled Fighting Spirit episodes returned no selectable
  captions; burned-in subtitles have not been checked.
- Actual language correctness, all subtitle languages, ten-minute reliability,
  downloads/offline reopening, PiP and AirPlay remain unverified. Flow/Zuri can
  share upstream media. Catalogue counts do not guarantee playable copies.

This remains a beta, not full playback certification. No JavaScript execution,
access-control workaround or AniCrowd/MegaPlay fallback is introduced.

## Publication safeguards

Native validator pinned to reviewed private Vireo commit
`7765c852157944201fdc07d1712b8be7ecccc05e`. It supports the declared features;
the previous publisher did not. Signing stays in the existing protected GitHub
environment; no key is placed in candidate files or logs. Existing signed
artifacts are retained, the new artifact is content-addressed, and the root
index is re-signed with an increasing timestamp. No stable source is replaced.
