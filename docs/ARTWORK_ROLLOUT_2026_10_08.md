# Optional module logos

Cosmetic rollout for Aroki 2.1.36. Ten images are taken from the owner-tested
Testing-Modules-AR/module-logos snapshot
`8547d99bfdedd0cdc1ec82ef27b88c1540eb1511`.

The signed primary index and all manifests remain byte-for-byte unchanged from
`04b60e7b8d6ed4ca1f0bdba753143cf58da4c48a`. No test IDs, test provider graphs,
retirement changes or minimum-version increases are promoted.

`artwork.json` is signed with the existing collection key and binds each image
to its production ID, family, version and complete manifest descriptor. Existing
installations receive images during source checks; no duplicate module is added.
Use Profile > Sources > Check for Updates to request a refresh. Slow connections
may need a subsequent check because cosmetic work has a bounded time budget.

Older readers (including inspected 2.0.42 revision `5b2c857`) do not request this
sidecar. Their index/manifests remain unchanged. New readers use the existing
name/icon fallback for absent, invalid or unavailable artwork. Saved shows,
preferences, downloads and module activation are not changed by artwork backfill.
Separately installed Logo Test modules are separate identities and are not
automatically removed or migrated by this publication.

The publication workflow runs native repository/icon tests, verifies the signed
catalogue and images, validates every production manifest and simulates adding
artwork to existing installations. It only commits the signed sidecar after those
checks. Re-run it when production manifest descriptors change, otherwise the
old artwork binding safely falls back for changed modules.

This is not a new provider/playback certification or a playback repair release.
No claim is made that artwork improves upstream provider reliability.

Rollback: revert the sidecar publication commit without changing index.json or
connectors. Valid images already cached may remain; that is intentional.
