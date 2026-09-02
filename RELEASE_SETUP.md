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

Ships with any JDK. Try in order:

- `keytool` (if a JDK is on PATH)
- `& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"` (Android Studio's JBR)
- `flutter doctor -v` → "Java binary at:" path → `keytool.exe` sits next to `java.exe`

- [ ] `keytool` resolved

## B2 — Generate the upload keystore

From the repo root. Replace `<KEYTOOL>`:

```powershell
<KEYTOOL> -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
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

```powershell
git status --porcelain android/
```

**Nothing** should appear for `upload-keystore.jks` or `key.properties`
(`android/.gitignore` covers `**/*.jks`, `key.properties`). If either shows, stop
and fix `.gitignore` first.

- [ ] Both confirmed ignored

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

- [ ] `android` green — APK built and **signed with the upload key** (check the
      job log for `signingConfig` = release, not debug)
- [ ] `windows` + `linux` still green

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
