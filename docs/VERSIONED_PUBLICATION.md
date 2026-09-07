# Version-aware publication

The app and repository URL remain unchanged for existing users. Index entries
already carry `minimumAppVersion`. New app releases must pass the installed
bundle marketing version to ConnectorStore; Aroki 2.0.1 implements this.

New connectors may declare a higher minimum. Do not claim support for older
apps when a manifest uses capabilities their validator does not implement.
The app update must ship before users of that version can use the connector.

The publishing workflow is pinned to an audited app-code commit. Candidate
authors on Windows submit `connectors/<id>/connector.json` on a candidate
branch and dispatch Publish Aroki connector with that branch and ID. Keys
remain in the existing protected GitHub environment.

Published manifests now use immutable SHA-256 release paths. Legacy paths are
not overwritten by the publisher. This protects cached indexes and rollback.
Do not manually delete old release files or replace index signatures.

The publisher rejects raising the minimum version of an existing connector.
This is intentional: retaining an installed old module is not the same as
allowing a new user on an old app to install it. A future multi-track migration
must preserve that legacy listing before raising its minimum. Until then,
publish only compatible fixes to existing connectors. Do not bypass this guard.

HiAnime remains unpublished: its new extraction operation is not yet integrated
into this pinned validator or the current Aroki app checkout. Version gating
does not implement extraction capabilities by itself.

No existing index entries or connector releases changed in this rollout.
