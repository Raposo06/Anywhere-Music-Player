# Release automation — one-time setup checklist

Work through this once, then delete the file. It wires up
`.github/workflows/release.yml` so `git tag vX.Y.Z && git push --tags` builds and
publishes Android + Windows + Linux to GitHub Releases.

Order matters: **Phase A** proves the Windows + Linux jobs build with no
credentials, **Phase B** adds Android signing, **Phase C** ships.

Permanent reference: [docs/operations.md](docs/operations.md) → "Automated
releases" and [docs/decisions.md](docs/decisions.md) (2026-09-01). This file is
just the punch-list.

Repo: `Raposo06/Anywhere-Music-Player` (public).

---

# Phase A — Windows + Linux dry run (no secrets)

## A1 — Commit the workflow

The pipeline is already committed (`f20a614`). If the `include_android`
dispatch input isn't in yet:

```powershell
git add .github docs RELEASE_SETUP.md
git commit -m "CI: workflow_dispatch builds Windows+Linux only unless include_android"
git push
```

- [ ] Workflow on `main` has the `include_android` input

## A2 — Add the repo variable

Settings → Secrets and variables → **Actions** → **Variables** tab → **New repository variable**

| Name | Value |
|---|---|
| `API_BASE_URL` | `https://navidrome.foxcore.dev` |

`flutter_dotenv` bakes this into every build's asset bundle. Public DNS name, so
a *variable*, not a secret. The `meta` job hard-fails if it's missing.

- [ ] `API_BASE_URL` variable added

## A3 — Run the dry run

GitHub → **Actions** → **Release** → **Run workflow**. Leave **include_android
unchecked**. This builds Windows + Linux, publishes nothing, creates no tag.

- [ ] `meta` green (proves the variable is set)
- [ ] `test` green — `flutter analyze` + `flutter test` gate every build; if it's
      red the build jobs never start. Check locally first with `flutter test`
- [ ] `windows` green — `flutter build windows`, then Inno Setup 6.7.3 (pinned by
      SHA256) compiles `installer.iss` → `-setup.exe` artifact
- [ ] `linux` green — `.tar.gz` artifact produced. The AppImage step is
      `continue-on-error`; amber there is fine
- [ ] `android` shows as **skipped** (not failed)
- [ ] download both artifacts from the run summary, confirm the installer runs
      and the tarball extracts + launches

If a job fails, see Troubleshooting, fix, push, re-run. Don't start Phase B until
this is green.

---

# Phase B — Android signing

## B1 — Find keytool

**Already located on this machine** (verified 2026-09-02) — note the `Studio1`,
not `Studio`:

```
C:\Program Files\Android\Android Studio1\jbr\bin\keytool.exe
```

It is **not** on `PATH`, so it must be called by full path. On another machine:
`flutter doctor -v` → "Java binary at:" → `keytool.exe` sits next to `java.exe`.

- [x] `keytool` resolved

## B2 — Generate the upload keystore

From the repo root, in PowerShell:

```powershell
& "C:\Program Files\Android\Android Studio1\jbr\bin\keytool.exe" -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Prompts:

| Prompt | Enter |
|---|---|
| Enter keystore password | **strong password → Vaultwarden as `AMP keystore password`** |
| Re-enter new password | same |
| Name / org / etc. | anything (name = `Anywhere Music Player`, rest `.`) — not verified |
| Enter key password for `<upload>` | **RETURN** to reuse the keystore password (simplest), or set + save a separate one |

⚠️ **Avoid `\` in the password.** CI writes it into `android/key.properties`, and
Java's `.properties` format treats a backslash as an escape character — it would
be silently swallowed and signing would fail with a wrong-password error. `$`,
backticks and spaces are safe (the workflow passes secrets through `env` and
`printf`, so the shell never re-expands them). Long + alphanumeric + `!@#%^&*-_`
is fine.

- [ ] `android/app/upload-keystore.jks` created
- [ ] Password(s) in Vaultwarden, no backslash

## B3 — Confirm it's gitignored

**Already verified 2026-09-02** — `git check-ignore -v` resolves both paths to
explicit rules, and nothing matching `*.jks` / `key.properties` is tracked:

```
android/.gitignore:14:**/*.jks        android/app/upload-keystore.jks
android/.gitignore:12:key.properties  android/key.properties
```

Re-check after B2 if you want belt and braces:

```powershell
git status --porcelain android/
```

- [x] Ignore rules confirmed (nothing to do unless `git status` surprises you)

## B4 — Back up the keystore (now, not later)

Lose it and **every installed app must be uninstalled + reinstalled** to take
another update — Android rejects an update signed by a different key.

- [ ] `upload-keystore.jks` copied off the repo — Vaultwarden attachment and/or
      Hetzner Storage Box
- [ ] Vaultwarden note records alias (`upload`) + which password

## B5 — Local signed builds (optional)

Only if you want `flutter build apk --release` on this machine to be Play-key
signed. CI does **not** need this — it rebuilds `key.properties` from secrets.

`android/key.properties` (gitignored):

```
storePassword=<keystore password>
keyPassword=<key password, or same if you pressed RETURN>
keyAlias=upload
storeFile=upload-keystore.jks
```

- [ ] Done, or deliberately skipped

## B6 — Base64-encode for the secret

Single line, no wrapping.

**PowerShell:**

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks")) | Set-Clipboard
```

**or Git Bash:**

```bash
base64 -w0 android/app/upload-keystore.jks | clip
```

- [ ] Base64 string on the clipboard

## B7 — Add the four secrets

Settings → Secrets and variables → **Actions** → **Secrets** tab → **New repository secret**, ×4

| Name | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the base64 string from B6 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password from B2 |
| `ANDROID_KEY_PASSWORD` | key password from B2 (same as above if you pressed RETURN) |
| `ANDROID_KEY_ALIAS` | `upload` |

- [ ] All four added, names exact

## B8 — Dry run with Android

**Actions** → **Release** → **Run workflow**, this time **tick include_android**.

- [ ] `android` green
- [ ] `windows` + `linux` still green

### Verify the APK is actually upload-signed

A green job is **not** proof. `android/app/build.gradle` falls back to debug
signing when `key.properties` is missing, and that path builds fine — so a
missing secret looks identical to success until users can't take an update.

Download the `android` artifact, unzip, and read the certificate with
**`apksigner`** (path verified on this machine 2026-09-02):

```powershell
& "C:\Android\Sdk\build-tools\36.1.0\apksigner.bat" verify --print-certs AnywhereMusicPlayer-0.0.0-dev.apk
```

| `Signer #1 certificate DN:` | Meaning |
|---|---|
| the DN you typed in B2 (e.g. `CN=Anywhere Music Player`) | ✅ upload-signed, proceed |
| `CN=Android Debug, O=Android, C=US` | ❌ secrets never reached the build — fix before tagging |

⚠️ **Don't use `keytool -printcert -jarfile` here.** It only reads the old v1
(JAR) signature scheme. With `minSdk 21+` AGP signs v2/v3 and skips v1, so
keytool reports **"Not a signed jar file"** on a perfectly well-signed APK —
a false alarm, not a finding.

- [ ] Certificate shows the upload key, not the Android debug key

---

# Phase C — Ship

## C1 — First real release

```powershell
git tag v1.1.0
git push origin v1.1.0
```

- [ ] all build jobs green
- [ ] `release` job green
- [ ] `github.com/Raposo06/Anywhere-Music-Player/releases` shows `v1.1.0` with
      `.apk`, `-setup.exe`, `-linux-x64.tar.gz`, maybe `.AppImage`, `SHA256SUMS`
- [ ] APK installs + runs on the phone
- [ ] Windows installer runs (click through SmartScreen)

## C2 — Downloads page

`downloads-section.html` (drafting-session snippet — small, re-generate if lost)
drops into the foxcore.dev presenter page. Reads `releases/latest` from the
GitHub API client-side, so future tags need no redeploy.

- [ ] section pasted into the presenter page
- [ ] page shows the `v1.1.0` buttons

## C3 — Clean up

- [ ] `git rm RELEASE_SETUP.md && git commit -m "drop release setup checklist"`

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `meta` fails immediately | `API_BASE_URL` variable not set (A2) |
| `android` fails at "Restore keystore" / gradle signing | an `ANDROID_*` secret missing or wrong; base64 has newlines (re-do B6 with the exact command) |
| `android` fails on an AGP/Kotlin version floor | `FLUTTER_VERSION` in the workflow drifted from what the tree builds against — see docs/operations.md "three version floors". Pin to what `flutter --version` reports locally |
| `windows` fails at "Build installer" | `installer.iss` compile error, or the pinned Inno Setup SHA256 no longer matches (a new 6.x point release) — bump URL + hash per the comment in the workflow step |
| `windows` fails at MAX_PATH | the `core.longpaths` step should cover it; if not, the runner image changed |
| `linux` AppImage step amber/red | expected — `continue-on-error`. The `.tar.gz` is the real artifact. Fix the AppImage by iterating `scripts/package-linux-appimage.sh` on the Omarchy box, not in CI |
| `release` skipped | you used "Run workflow", not a tag push — `publish` is only `true` on `v*` tags |
| dispatch run and `android` skipped | expected unless you ticked **include_android** |

---

## Reference: files the pipeline touches

| File | Role |
|---|---|
| `.github/workflows/release.yml` | the pipeline |
| `scripts/package-linux-appimage.sh` | AppImage packaging (best-effort) |
| `android/app/build.gradle` | `signingConfigs.release` from `key.properties`, debug fallback |
| `installer.iss` | `#ifndef MyAppVersion` so CI sets it via `/DMyAppVersion=` |
| `android/key.properties` | **gitignored**, local only — CI rebuilds from secrets |
| `android/app/upload-keystore.jks` | **gitignored**, never committed |
