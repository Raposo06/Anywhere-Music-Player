# Release automation — one-time setup checklist

Work through this once, then delete the file. It wires up
`.github/workflows/release.yml` so `git tag vX.Y.Z && git push --tags` builds and
publishes Android + Windows + Linux to GitHub Releases.

Permanent reference for all of this lives in
[docs/operations.md](docs/operations.md) → "Automated releases" and
[docs/decisions.md](docs/decisions.md) (2026-09-01). This file is just the
actionable punch-list.

Repo: `Raposo06/Anywhere-Music-Player` (public).

---

## What you need first

- [ ] `keytool` available. It ships with any JDK. On this machine try, in order:
  - `keytool` (if a JDK is on PATH)
  - `& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"` (Android Studio's bundled JBR)
  - `flutter doctor -v` → find the "Java binary at:" path → `keytool.exe` sits next to `java.exe`
- [ ] Admin access to the GitHub repo settings (Settings → Secrets and variables → Actions)
- [ ] Vaultwarden open, to store two passwords

---

## Step 1 — Generate the upload keystore

Run from the repo root. Replace `<KEYTOOL>` with whatever resolved above.

```powershell
<KEYTOOL> -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It prompts for:

| Prompt | What to enter |
|---|---|
| Enter keystore password | **pick a strong password → save to Vaultwarden as `AMP keystore password`** |
| Re-enter new password | same |
| First and last name, org, etc. | anything (e.g. name = `Anywhere Music Player`, rest blank/`.`) — not verified |
| Enter key password for `<upload>` | press **RETURN** to reuse the keystore password (simplest), or set a separate one and save it too |

Produces `android/app/upload-keystore.jks`.

- [ ] Keystore generated
- [ ] Password(s) in Vaultwarden

### Confirm it won't be committed

```powershell
git status --porcelain android/
```

Should show **nothing** for `upload-keystore.jks` or `key.properties` — both are
covered by `android/.gitignore` (`**/*.jks`, `key.properties`). If either shows
up, stop and fix `.gitignore` before continuing.

- [ ] `git status` confirms both are ignored

---

## Step 2 — Back up the keystore (do this now, not later)

If this file is ever lost, **every installed copy of the app must be uninstalled
and reinstalled** to take another update — Android rejects an update signed by a
different key.

- [ ] Copy `android/app/upload-keystore.jks` somewhere off the repo — Vaultwarden
      file attachment, or the Hetzner Storage Box, or both
- [ ] Note in Vaultwarden which alias (`upload`) and which password goes with it

---

## Step 3 — Local signed builds (optional)

Only if you want `flutter build apk --release` on this machine to produce a
Play-key-signed APK too. CI does **not** need this file — it builds `key.properties`
from secrets.

Create `android/key.properties` (gitignored):

```
storePassword=<keystore password from Step 1>
keyPassword=<key password, or same as storePassword if you pressed RETURN>
keyAlias=upload
storeFile=upload-keystore.jks
```

- [ ] Done, or deliberately skipped

---

## Step 4 — Base64-encode the keystore for the secret

GitHub secrets are text, so the `.jks` goes in base64, single line, no wrapping.

**PowerShell:**

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks")) | Set-Clipboard
```

**or Git Bash:**

```bash
base64 -w0 android/app/upload-keystore.jks | clip
```

The value is now on the clipboard for Step 6.

- [ ] Base64 string copied

---

## Step 5 — Add the repo variable

Settings → Secrets and variables → **Actions** → **Variables** tab → **New repository variable**

| Name | Value |
|---|---|
| `API_BASE_URL` | `https://navidrome.foxcore.dev` |

This is baked into every build's asset bundle by `flutter_dotenv`. It's a public
DNS name, so a *variable*, not a secret. The `meta` job fails fast if it's missing.

- [ ] `API_BASE_URL` variable added

---

## Step 6 — Add the four secrets

Settings → Secrets and variables → **Actions** → **Secrets** tab → **New repository secret**, ×4

| Name | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the base64 string from Step 4 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password from Step 1 |
| `ANDROID_KEY_PASSWORD` | key password from Step 1 (same as above if you pressed RETURN) |
| `ANDROID_KEY_ALIAS` | `upload` |

- [ ] All four secrets added
- [ ] Names match exactly (the workflow references them literally)

---

## Step 7 — Commit the pipeline

The workflow + supporting edits are already in the working tree from the drafting
session. Commit them:

```powershell
git add .github scripts android/app/build.gradle installer.iss docs RELEASE_SETUP.md
git commit -m "CI: build and publish releases on tag"
git push
```

- [ ] Pushed to `main`

---

## Step 8 — Smoke test without publishing

GitHub → **Actions** → **Release** → **Run workflow** (uses `workflow_dispatch`,
`publish=false`, so it builds all three platforms but creates no release).

Watch for:

- [ ] `android` job green — APK built and signed
- [ ] `windows` job green — installer built (Inno Setup 6.5.4+ downloaded from jrsoftware.org)
- [ ] `linux` job green — `.tar.gz` produced (the AppImage step is `continue-on-error`, amber is fine)
- [ ] Artifacts appear on the run summary page

If a job fails, see Troubleshooting below, fix, push, re-run.

---

## Step 9 — First real release

```powershell
git tag v1.1.0
git push origin v1.1.0
```

- [ ] All build jobs green
- [ ] `release` job green
- [ ] `github.com/Raposo06/Anywhere-Music-Player/releases` shows `v1.1.0` with:
      `.apk`, `-setup.exe`, `-linux-x64.tar.gz`, maybe `.AppImage`, and `SHA256SUMS`
- [ ] Download the APK on the phone, confirm it installs and runs
- [ ] Download + run the Windows installer (click through SmartScreen)

---

## Step 10 — Downloads page

`downloads-section.html` (from the drafting session — re-generate if lost, it's a
small static snippet) drops into the foxcore.dev presenter page. It reads
`releases/latest` from the GitHub API client-side, so future tags need no redeploy.

- [ ] Section pasted into the presenter page
- [ ] Page shows the `v1.1.0` download buttons

---

## Step 11 — Clean up

- [ ] Delete this file: `git rm RELEASE_SETUP.md && git commit -m "drop release setup checklist"`

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `meta` job fails immediately | `API_BASE_URL` variable not set (Step 5) |
| `android` job fails at "Restore keystore" / gradle signing error | one of the `ANDROID_*` secrets missing or wrong; base64 has newlines (re-do Step 4 with the exact command) |
| `android` fails on AGP/Kotlin version floor | `FLUTTER_VERSION` in the workflow drifted from what the tree builds against — see docs/operations.md "three version floors". Pin to the version `flutter --version` reports locally |
| `windows` job fails at "Build installer" | `installer.iss` compile error. If it mentions `WizardStyle`, the jrsoftware.org download wasn't 6.5.4+ (unlikely) |
| `windows` fails at MAX_PATH | `git config --system core.longpaths true` step should cover it; if not, the runner image changed |
| `linux` AppImage step amber/red | expected — it's `continue-on-error`. The `.tar.gz` is the real Linux artifact. To fix the AppImage, iterate `scripts/package-linux-appimage.sh` on the Omarchy box, not in CI |
| `release` job skipped | you used "Run workflow" (dispatch), not a tag push. `publish=true` only on `v*` tags |
| Release created but no notes | `generate_release_notes: true` needs commits since the last tag; first release may be sparse |

---

## Reference: files touched by the pipeline

| File | Role |
|---|---|
| `.github/workflows/release.yml` | the pipeline |
| `scripts/package-linux-appimage.sh` | AppImage packaging (best-effort) |
| `android/app/build.gradle` | `signingConfigs.release` from `key.properties`, debug fallback |
| `installer.iss` | `#ifndef MyAppVersion` so CI passes the tag via `/DMyAppVersion=` |
| `android/key.properties` | **gitignored**, local only — CI rebuilds it from secrets |
| `android/app/upload-keystore.jks` | **gitignored**, never committed anywhere |
