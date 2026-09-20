# AniKage 0.3.4: fresh playback routes

Owner-authorized module-only repair for intermittent playback startup failures.
No Aroki app code, engine/schema, signing policy, host permissions, source/audio
selection, or account code changed.

## Root cause and repair

AniKage's public sources endpoint can return a cached temporary media route. A
route may stop working while the API still serves that cached value, so an Aroki
retry can receive the same unusable route. AniKage's own web client supports the
ordinary `refresh=1` query option to request a fresh provider result.

Version 0.3.4 adds that fixed option to the existing Koto source request. The
connector still uses the same bounded HTTPS request, provider, Sub/Dub variant,
subtitle mapping, playback headers, and allowlisted hosts.

## Evidence

- Candidate SHA-256:
  `14091d5d0b319a3c0bd0e1a83e37c113d842ac72db4345496955fd5ca1f1f183`
- Engine revision:
  `4ac3f4450c39144fe4228ee06592ea41bb89160c`
- Frozen corpus seed: `20260817`
- Frozen corpus SHA-256:
  `d9c309abfcd4712aaf878de86027711a421caa9aaeacf0559dc47c3a278c6ed5`
- Deterministic native suite: 298 tests passed, 13 intentional skips, 0 failures.
- Frozen 50-title certification: 46 passed, 4 failed, 0 absent, 0 blocked;
  92% pass rate; verdict PASS.
- Exact reported regression: Ghost Stories Episode 16 Dub resolved a fresh,
  non-stale route. macOS AVPlayer loaded the 1,416.8-second HLS asset, sought to
  387 seconds, and advanced more than 11 seconds in two consecutive runs.
- One Piece Episode 1: Sub and Dub each returned one English caption track;
  285 cues were parsed from each live response.

The four remaining corpus failures were Food Wars! The Fourth Plate, The
Disastrous Life of Saiki K., JoJo's Bizarre Adventure: Golden Wind, and That
Time I Got Reincarnated as a Slime Season 2. The first, second, and fourth
returned no playable candidate; Golden Wind returned one candidate whose media
probe failed. They remain source/provider gaps and are not hidden by this
release.

## Evidence boundaries

The wide run tests one representative episode and an automatically available
audio variant per title. It does not certify every episode, exhaustive Sub/Dub,
spoken-language correctness, visible iPhone captions, downloads, PiP, AirPlay,
or long playback. The exact playback repair is verified with macOS AVPlayer;
physical-iPhone acceptance remains pending after users refresh the collection.

## Publication and recovery

Publish through the protected `Publish Aroki connector` workflow with connector
ID `anikage` and the exact candidate commit. The workflow must run the native
tests, create immutable signed manifest bytes, sign the index, verify the full
repository, and push the resulting publication commit to `main`.

Recovery must use a newer signed connector version and a newly signed index.
Do not replace immutable release artifacts or replay an older index.
