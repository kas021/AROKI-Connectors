# Windows connector workflow

There are two publication paths. Pick one before you start.

## 1. Signed official feed — recommended for existing AROKI users

This keeps the existing `main/index.json` intact. Older AROKI builds continue
to use it with no change.

1. Create a candidate branch and add only `connectors/<id>/connector.json`.
2. On Windows, run:

   ```powershell
   py scripts/validate-unsigned-connector.py <id>
   git add connectors/<id>/connector.json
   git commit -m "Candidate <id> <version>"
   git push origin HEAD
   ```

3. In GitHub Actions, run **Publish Aroki connector** with your candidate
   branch/commit and connector ID.

The protected macOS runner performs native AROKI validation, signing and the
atomic update to `main`. Your Windows machine never needs the private key.
If that workflow fails, do not hand-edit `index.json` or its signatures.

## 2. Unsigned personal or test feed — new bridge builds only

Create a separate GitHub repository or branch containing an unsigned
`index.json` and connector manifests. Push normally from Windows; no signing
key is required. In the bridge build, the person installing it must paste the
exact raw GitHub `index.json` URL, enable **Allow unsigned collection**, and
confirm the warning.

Unsigned feeds are not compatible with older AROKI builds. They never replace
or weaken the signed feed automatically. AROKI still validates JSON structure,
HTTPS hosts, checksums, request bounds and native media rules, but cannot prove
who changed an unsigned repository.

## Required checks before any release claim

- `py scripts/validate-unsigned-connector.py <id>` passes.
- The connector has no JavaScript, WebView, credentials, proxy, local host or
  executable behavior.
- Native AROKI certification passes on macOS before describing playback as
  verified.
- A physical-iPhone playback test is recorded separately from HTTP success.
