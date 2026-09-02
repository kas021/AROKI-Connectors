# AROKI Connectors

Public, signed connector repository for **AROKI — Made by Synthetiq**.

This repository contains only bounded declarative JSON manifests and the
signed `index.json` required by AROKI's repository importer. It does **not**
contain the AROKI iOS application, executable modules, JavaScript, WebViews,
browser automation, credentials, media files, or a proxy/backend service.

## Import into AROKI

1. Open **Profile → Sources**.
2. In **Add verified repository**, enter:

   `kas021/AROKI-Connectors`

3. Tap **Add verified sources**.
4. Review the repository and signing-key fingerprint.
5. Choose the active source from the source picker.

Adding a repository verifies its repository signature, every manifest
signature, SHA-256 digest, schema and manifest identity before a connector is
stored locally on the device. AROKI then lets the user choose its active
source at any time.

## Published connectors

- AniKoto
- One Pace
- AnimeGG

The repository also contains **Update Flow Test**, a non-catalogue fixture used
to verify source-update handling. It is not a recommended content source.

The index contains the exact compatibility track for every connector. A source
can change independently of AROKI, so availability is not guaranteed. Users
and source publishers remain responsible for ensuring they have permission to
access and distribute the content they configure.

AniNeko, AniLol, and AnimeAV1 were retired from the public index after the
August 2026 Aroki certification sweep found no Aroki-compatible playback path.
Previously installed copies remain under the user's control and can be removed
on-device. Their historical manifests remain recoverable through Git history.

Senshi, ToonTales, DonghuaWorld, and Archive Classics were withdrawn in earlier
reviews. Previously installed copies remain under the user's control and can be
removed on-device.

## Safety boundary

Connectors describe a finite set of HTTPS requests and typed extraction steps.
They cannot add executable behavior to AROKI. The native app continues to own
validation, request limits, host policy, parsing, caching and AVPlayer playback.

The repository signing key is held outside Git and is never committed here.

## Windows publishing

Windows contributors do not need the signing key for the official feed. Push a
candidate branch, run the structural preflight, then dispatch the protected
GitHub publishing workflow. For the optional bridge-build unsigned-feed path,
see [Windows connector workflow](docs/WINDOWS_CONNECTOR_WORKFLOW.md).
