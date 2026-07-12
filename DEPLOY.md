# Deploying RemoteX (SL Brothers)

This guide takes you from source code to *"a user downloads RemoteX, launches it,
and connects"* — the same flow as any remote-support product.

There are three pieces, and **the order matters** because the client build has to
know your server address before it is compiled:

```
[1] SERVER            [2] BAKE server into client       [3] BUILD + PUBLISH
    hbbs + hbbr   -->      config.rs constants      -->     tag -> GitHub Release
    (a VPS)               (address + public key)            (download links)
```

---

## Part 1 — Stand up your server

RemoteX connects users by **ID + one-time password** without exposing IP addresses.
That coordination is done by your own server (two small services), so no session
ever touches RustDesk's public servers.

1. **Rent a Linux VPS** with a public IP — about $4–6/month (Hetzner, DigitalOcean,
   Contabo; Oracle Cloud has a free tier). Optionally point a domain such as
   `relay.slbrothers.com` at its IP.
2. **Install Docker**, then copy [`server/docker-compose.yml`](server/docker-compose.yml)
   to the VPS. Edit it and replace `YOUR_HOST` with your public IP or domain.
3. Start it:
   ```bash
   docker compose up -d
   ```
4. **Open the firewall:** TCP `21115-21119` and UDP `21116`.
5. **Copy your server's public key** — you need it in Part 2:
   ```bash
   cat ./data/id_ed25519.pub
   # e.g. 9aX2p...long-base64-string...=
   ```

## Part 2 — Bake your server into the RemoteX client

So users never have to configure anything. Edit two constants in
[`libs/hbb_common/src/config.rs`](libs/hbb_common/src/config.rs) (around line 120):

```rust
pub const RENDEZVOUS_SERVERS: &[&str] = &["YOUR_HOST"];          // your IP or domain
pub const RS_PUB_KEY: &str = "the key from id_ed25519.pub";      // paste it here
```

Commit and push. Every RemoteX built from now on auto-connects to *your* server.
> Ask Claude to make this edit for you once you have the host + key.

## Part 3 — Build installers and publish a Release

Your repository already contains RustDesk's full build pipeline, and your repo is
**public**, so GitHub Actions build minutes are **free and unlimited**.

Pushing a version **tag** triggers **Flutter Tag Build**
([`.github/workflows/flutter-tag.yml`](.github/workflows/flutter-tag.yml)), which
compiles RemoteX on GitHub's servers and attaches the installers to a GitHub Release.
Code-signing steps skip automatically when you have no signing secrets.

**One-time setup:** GitHub repo → **Settings → Actions → General → Workflow
permissions → "Read and write permissions" → Save.** (Lets the build create the Release.)

**Cut a release:**
```bash
git tag v1.0.0
git push origin v1.0.0
```
Watch progress under the **Actions** tab. When the Windows job finishes, a
(pre)release appears under **Releases** with a Windows `.exe` (portable) and `.msi`
(installer).

### What builds on a fork, and what doesn't

| Platform | Result | Why |
|---|---|---|
| **Windows** x64 (exe + msi) | ✅ Builds & publishes | Your main target |
| **Android** apk | ✅ Usually builds | Self-signed, sideloadable |
| **Linux** deb / AppImage | ✅ Usually builds | Built on Linux runners |
| **macOS** dmg | ⚠️ Unsigned | Users must right-click → Open; signed needs Apple Developer ($99/yr) |
| **iOS** | ❌ | Requires the App Store + Apple Developer account |

Jobs that need Apple/private signing will show a red ✗ — that's expected on a fork and
does **not** stop the Windows/Android/Linux downloads from publishing. Once you see
which jobs pass, Claude can trim the pipeline to just those so future runs are all green.

> Note: asset filenames still read `rustdesk-<version>-...` (the internal build name).
> Cosmetic — the app itself is fully RemoteX. Ask Claude to rename the release assets.

## Part 4 — Let users download

1. Go to **Releases**, edit the one the build created, write the download table
   (Windows / Android / …), and mark it **"Set as the latest release."**
2. Optionally host the same installer on the SL Brothers website — the
   *"download from our portal"* flow — and link back to this repo for the source
   (AGPL-3.0 requires users can get the source).

## Part 5 — Trust (recommended)

Unsigned Windows apps trigger a SmartScreen **"unknown publisher"** warning. A
code-signing certificate (~$100–400/yr, or free via [SignPath](https://signpath.org)
for open-source) removes it — worth it for a remote-support tool people must trust.

---

## End-user experience

1. Download RemoteX for their platform and launch it.
2. It shows a **Session ID** and a **one-time password** (auto-generated).
3. They share those with the SL Brothers technician.
4. Technician enters the ID + password → connected. With permission, they control
   the desktop. Either side can disconnect anytime. No IP addresses are exposed.
