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

3. Tap **Preview repository**.
4. Review the repository and signing-key fingerprint.
5. Tap **Install** beside each connector you want.

Previewing never installs anything. Installation is explicit, verifies the
repository signature, manifest signature, SHA-256 digest, schema and manifest
identity, then stores that connector locally on the device.

## Published connectors

- AniKoto
- Senshi
- One Pace
- ToonTales
- AnimeGG
- AniLol
- DonghuaWorld
- Archive Classics

The index contains the exact compatibility track for every connector. A source
can change independently of AROKI, so availability is not guaranteed. Users
and source publishers remain responsible for ensuring they have permission to
access and distribute the content they configure.

## Safety boundary

Connectors describe a finite set of HTTPS requests and typed extraction steps.
They cannot add executable behavior to AROKI. The native app continues to own
validation, request limits, host policy, parsing, caching and AVPlayer playback.

The repository signing key is held outside Git and is never committed here.
