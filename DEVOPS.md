# RemoteX — DevOps Deployment & Go-Private Runbook

**Owner:** SL Brothers
**Audience:** DevOps / infrastructure team
**Goal:** Run RemoteX entirely on SL Brothers infrastructure, and take the source
repository private without breaking distribution or the software licence.

---

## 0. Read this first — order matters

> ⚠️ **Do NOT make the repository private until Step 4 is live.**
> All current downloads are served from GitHub Releases. The moment the repo goes
> private, every release asset returns **404** and nobody — including you — can
> install RemoteX. Stand up the VPS download page **first**, then flip visibility.

Correct order:

```
1. Provision VPS
2. Deploy server (hbbs + hbbr)
3. Bake server config into the client + build
4. Publish downloads + source tarball on the VPS   <-- distribution now independent of GitHub
5. THEN make the repo private
6. Trim CI to fit the private-repo minute budget
```

---

## 1. Provision the VPS

**Minimum spec** (fine for ~10–50 concurrent devices):

| Resource | Minimum | Notes |
|---|---|---|
| CPU | 1–2 vCPU | Relay is I/O bound, not CPU bound |
| RAM | 1–2 GB | |
| Disk | 20 GB | |
| Network | **Unmetered / high transfer** | Relay traffic is the real cost driver |
| OS | Ubuntu 22.04 / 24.04 LTS | |
| IP | **Static public IPv4** | Required |

Suggested providers: Hetzner (best price/transfer), DigitalOcean, Vultr, Contabo.
Budget ~$5–10/month.

**DNS:** point a record at the VPS, e.g. `relay.slbrothers.com` → `<VPS_IP>`.
Use the hostname everywhere below rather than a bare IP.

### Firewall

Open these ports:

| Port | Proto | Purpose |
|---|---|---|
| 21115 | TCP | NAT type test |
| 21116 | **TCP + UDP** | ID registration / heartbeat / hole punching |
| 21117 | TCP | Relay |
| 21118 | TCP | Web client (optional) |
| 21119 | TCP | Web client relay (optional) |
| 80 / 443 | TCP | Download page (Step 4) |
| 22 | TCP | SSH — restrict to your admin IPs |

```bash
sudo ufw allow 22/tcp
sudo ufw allow 21115:21119/tcp
sudo ufw allow 21116/udp
sudo ufw allow 80,443/tcp
sudo ufw enable
```

> ⚠️ **21116/udp is mandatory.** Missing it is the single most common cause of
> "clients never come online".

---

## 2. Deploy the server (hbbs + hbbr)

Install Docker, then use [`server/docker-compose.yml`](server/docker-compose.yml)
from this repo. Edit `YOUR_HOST` to your domain first.

```bash
sudo apt update && sudo apt install -y docker.io docker-compose-plugin
mkdir -p /opt/remotex && cd /opt/remotex
# copy server/docker-compose.yml here, set YOUR_HOST=relay.slbrothers.com
docker compose up -d
docker compose ps          # both hbbs and hbbr should be Up
```

### Capture the public key — you need it in Step 3

```bash
cat /opt/remotex/data/id_ed25519.pub
```

> 🔐 `data/id_ed25519` is the **private** key. Back it up and never publish it.
> If you lose it, every deployed client must be reconfigured.

### Verify

```bash
docker compose logs --tail=50 hbbs
ss -tulpn | grep -E '2111[5-9]'
```
From another machine: `nc -vz relay.slbrothers.com 21116`

---

## 3. Bake the server into the client

So users never configure anything. Edit
[`libs/hbb_common/src/config.rs`](libs/hbb_common/src/config.rs) (~line 152):

```rust
pub const RENDEZVOUS_SERVERS: &[&str] = &["relay.slbrothers.co.uk"];
pub const RS_PUB_KEY: &str = "<contents of id_ed25519.pub>";
```

Done in **v1.1.0** (`relay.slbrothers.co.uk`). Build via tag push.

**Acceptance test:** install the built client on a **clean** machine. It must show
an ID and go **online without any manual server entry**. Confirm on the server:
`docker compose logs hbbs | grep -i register`

### 3a. Rollout to machines that already ran an older build  ⚠️

RemoteX caches the last server it used (`rendezvous_server` in the config), and
that cache **outranks the value baked into the binary** (`get_rendezvous_server`
checks the cache before the built-in default). So:

- **Clean machines** — a v1.1.0 install points at `relay.slbrothers.co.uk` on its
  own. Nothing to do.
- **Machines that ran an earlier build** — a plain upgrade will **not** switch
  them; the cached `rs-ny.rustdesk.com` wins. You must set the server explicitly.

Push [`deploy/set-remotex-server.ps1`](deploy/set-remotex-server.ps1) to those
machines via MDM/GPO/RMM (as SYSTEM/admin). It sets `custom-rendezvous-server`
(priority #2, which beats the cache) + `relay-server` + `key` using RemoteX's own
`--option` CLI, then restarts the service and verifies:

```powershell
# on each machine, elevated:
powershell -ExecutionPolicy Bypass -File .\set-remotex-server.ps1 -ClearCache
```

Verify per machine (prints the active server):

```powershell
& "$env:ProgramFiles\RemoteX\RemoteX.exe" --option custom-rendezvous-server
# -> relay.slbrothers.co.uk
```

---

## 4. Serve downloads + source from the VPS

This is what frees you from GitHub. Two things must be published:

1. **The installers** — what customers download.
2. **The source tarball** — **legally required** (see §7).

```bash
sudo apt install -y nginx
sudo mkdir -p /var/www/remotex/{download,source}
```

Publish artifacts (from CI or manually):

```bash
# installers
scp RemoteX-Windows-x86_64.msi  root@vps:/var/www/remotex/download/
scp RemoteX-macOS-AppleSilicon.dmg root@vps:/var/www/remotex/download/
# ... etc

# source tarball for the exact release
git archive --format=tar.gz -o RemoteX-1.1.0-source.tar.gz v1.1.0
scp RemoteX-1.1.0-source.tar.gz root@vps:/var/www/remotex/source/
```

Minimal nginx site:

```nginx
server {
    listen 80;
    server_name get.slbrothers.com;
    root /var/www/remotex;
    autoindex on;
    location /download/ { }
    location /source/   { }   # must stay reachable — licence requirement
}
```

Add TLS: `sudo apt install certbot python3-certbot-nginx && sudo certbot --nginx -d get.slbrothers.com`

**The download page must carry a visible "Source code" link to `/source/`.**

**Acceptance test:** from a machine with no GitHub access, download and install
the MSI, and download the source tarball.

---

## 5. Make the repository private

Only once Step 4 passes.

1. `https://github.com/sohailk007/RemoteX/settings`
2. **Danger Zone** → **Change repository visibility** → **Make private**
3. Confirm by typing the repo name

### Immediately after

- [ ] Verify the VPS download page still serves installers (it does not depend on GitHub)
- [ ] Verify `/source/` still serves the tarball
- [ ] Update any docs/links pointing at `github.com/sohailk007/RemoteX/releases`
- [ ] Re-check in-app links in `desktop_home_page.dart`, `connection_page.dart`,
      `desktop_setting_page.dart`, `install_page.dart`, mobile `settings_page.dart`
      — they currently point at the GitHub repo and will 404 for users.
      Repoint them at `https://get.slbrothers.com`.
- [ ] Rotate any tokens/secrets that were used while public

> ⚠️ **History is not erased.** Anything ever committed publicly (keys, tokens)
> must be treated as compromised and rotated, regardless of visibility.

---

## 6. CI after going private — budget warning

| Repo | Actions minutes |
|---|---|
| **Public** | Unlimited, free |
| **Private (Free plan)** | **2,000 min/month**, then billed |

A full matrix build consumes **~5–8 hours of runner minutes** (15+ parallel jobs;
macOS minutes bill at **10×**). That is roughly **3–4 full builds/month** before
you start paying — and macOS alone can exhaust it.

**Recommended:** trim `.github/workflows/flutter-build.yml` to the targets you
actually ship (Windows x64, and Android if needed). Remove macOS/iOS/Linux-ARM
matrix legs. Alternatively self-host a runner on the VPS.

---

## 7. Licence obligations — non-negotiable

RemoteX is a fork of [RustDesk](https://github.com/rustdesk/rustdesk), licensed
**AGPL-3.0**. A private repo **does not** remove these duties:

- **§6 — conveying binaries:** anyone you give the app to is entitled to the
  **corresponding source** of *that exact build*.
- **§13 — network use:** anyone interacting with it over a network is entitled to
  the source.

**A private repo is lawful** — AGPL requires source to **recipients**, not to the
public. The `/source/` tarball on the download page discharges this. Keep it:

- **matched to each released build** (regenerate the tarball per release),
- **reachable by every user**, and
- **complete** — including `LICENCE` and `NOTICE.md`.

Do **not** remove `LICENCE`, `NOTICE.md`, or the "Powered by RustDesk" attribution.

---

## 8. Operations

**Backup** (critical — losing the key breaks every deployed client):
```bash
tar czf remotex-server-$(date +%F).tar.gz -C /opt/remotex data
```
Store the server key off-box, encrypted.

**Update the server:**
```bash
cd /opt/remotex && docker compose pull && docker compose up -d
```

**Monitor:** hbbs/hbbr container health, port 21116/udp reachability, disk, and
**relay bandwidth** (your main cost).

**Scale:** relay traffic is the bottleneck. If sessions are slow, check that
direct P2P is succeeding — heavy relay use means hole punching is failing
(usually a blocked 21116/udp).

---

## 9. Sign-off checklist

- [ ] VPS provisioned, static IP, DNS record
- [ ] Firewall: 21115–21119/tcp **and 21116/udp**
- [ ] hbbs + hbbr running, survive reboot
- [ ] Server key backed up off-box
- [ ] `RENDEZVOUS_SERVERS` + `RS_PUB_KEY` baked in; clean client comes online unaided
- [ ] Download page live over HTTPS
- [ ] **Source tarball published and linked**
- [ ] In-app links repointed off GitHub
- [ ] Repo made private (only after the above)
- [ ] CI trimmed to fit minute budget
- [ ] Public-era secrets rotated
