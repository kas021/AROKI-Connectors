# Source recovery: AniKoto 0.3.10, Synthetiq Anime Direct/Testing 0.1.2

Candidate only. Not signed or published. No app or engine code changed; each
manifest keeps its existing minimum app version.

## Root causes (verified live 2026-09-26)

- AniKoto: every MegaPlay server (`getSources`, `getSourcesNew`, videojs) now
  returns only an encrypted `enc` field, and the player also decrypts segment
  tokens client-side. No declarative route through MegaPlay exists.
- Synthetiq Anime Direct/Testing (Flux): Vidhawk resolve/play still answer, but
  `proxy.vidhawk.buzz/hls.m3u8` returns HTTP 502 (`upstream 403, cf_waf`) on both
  servers.

## Recovery route

AniKage's public `koto` provider is AniKoto's own feed, already unlocked and
proxied through `og.bakayaro.live`. Both connectors now resolve through it:

- AniKoto (base schema, 4 steps): AniKoto watch page (title `data-jp`, type,
  premiere season and year) -> AniKoto server list (episode number) -> AniKage
  browse filtered by `q`, `format`, `season`, `yearMin`, `yearMax` -> AniKage
  sources. Titles AniKoto lists without a season fail closed.
- Flux (graph-post-v1, within 2.0.38): AniList by MAL ID (romaji title, format,
  season, seasonYear) -> the same filtered AniKage browse -> AniKage sources.
  Vidhawk is removed from the stream route while its relay is down.

Sub and Dub carry every published caption track. No-match fails closed.

## Evidence

- Android engine live sweep and iOS 2.0.43 VireoCore (`vireo-tool probe-title`,
  built from a80c525): AniKoto Medaka Box Abnormal sub ep 1 / dub middle
  MEDIA_OK; Flux Frieren, Solo Leveling, Attack on Titan sub/dub first/middle
  MEDIA_OK. Media verified as TS segment bytes.
- Flux matching, proven by AniList ID equality on 50 popular titles: 48 correct,
  0 wrong, 2 fail closed.
- AniKoto matching on 57 titles: season filter 38 correct, 0 wrong, 19 fail
  closed (the unfiltered search had 1 wrong-cour match, so the season filter is
  required).

## Publishing prerequisites

- `scripts/align-anikoto-038-fixtures.py` admits only reviewed AniKoto versions;
  0.3.10 needs its reviewed SHA-256 and `active` status added, and the pinned
  `AniKotoConnectorTests.swift` fixtures must be aligned to the new route.
- The retirement record requires a tested, higher-version active release and a
  freshly signed forward index to restore AniKoto; 0.3.10 is that candidate.
