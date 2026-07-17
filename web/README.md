# RemoteX download page — deployment

**For:** DevOps
**What:** the public page customers use to download RemoteX, replacing GitHub Releases
**Why:** the source repo is going private. Once it does, every GitHub download link
returns 404. This page must be live **before** the repo visibility is changed.

`index.html` is self-contained — no build step, no CDN, no external requests. All
links are **relative**, so it works on any domain without editing the file.

---

## 1. Directory layout

```
/var/www/remotex/
├── index.html                       <- this page
├── download/                        <- installers
│   ├── RemoteX-Windows-x86_64.msi
│   ├── RemoteX-Windows-x86_64.exe
│   ├── RemoteX-macOS-AppleSilicon.dmg
│   ├── RemoteX-macOS-Intel.dmg
│   ├── RemoteX-Android-universal.apk
│   ├── RemoteX-Linux-x86_64.deb
│   ├── RemoteX-Linux-x86_64.rpm
│   └── RemoteX-Linux-x86_64.AppImage
└── source/                          <- REQUIRED, see §4
    └── RemoteX-<version>-source.tar.gz
```

> ⚠️ **Filenames must match exactly** — the page links to these names. If a file is
> missing its link 404s. Keep the names stable across releases so the page never
> needs editing.

## 2. nginx

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name get.slbrothers.co.uk;      # adjust to the chosen hostname
    root /var/www/remotex;
    index index.html;

    location / { try_files $uri $uri/ =404; }

    # installers: force download, allow resume, don't cache stale builds forever
    location /download/ {
        add_header Content-Disposition "attachment";
        add_header Cache-Control "public, max-age=300";
    }

    # source tarball must stay reachable -- licence requirement, see §4
    location /source/ { autoindex on; }

    # privacy statement (PRIVACY.md rendered or a static page)
    location = /privacy { try_files /privacy.html =404; }
}
```

Then TLS:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d get.slbrothers.co.uk
```

## 3. Publishing a release

```bash
# installers (rename to the exact names above)
scp RemoteX-*.msi RemoteX-*.exe RemoteX-*.dmg RemoteX-*.apk \
    RemoteX-*.deb RemoteX-*.rpm RemoteX-*.AppImage \
    root@vps:/var/www/remotex/download/

# matching source tarball for that exact build
git archive --format=tar.gz -o RemoteX-1.1.0-source.tar.gz v1.1.0
scp RemoteX-1.1.0-source.tar.gz root@vps:/var/www/remotex/source/
```

## 4. The source tarball is not optional

RemoteX is a fork of [RustDesk](https://github.com/rustdesk/rustdesk), licensed
**AGPL-3.0**. Anyone we give the app to is entitled to the corresponding source of
**that exact build** (§6), as is anyone who uses it over a network (§13).

A private repo is lawful — the licence requires source to **recipients**, not to the
public. The `/source/` tarball is what discharges that duty. So:

- regenerate it **for every release**, matched to the shipped build,
- keep `/source/` **publicly reachable**, and
- keep the **"Source code" link** in the page footer.

Removing that link, or letting `/source/` rot, puts us in breach.

## 5. Acceptance checks

Run these from a machine with **no GitHub access**:

- [ ] `https://<host>/` loads over HTTPS and shows the RemoteX page
- [ ] The big button downloads the right file for the OS you're on
- [ ] Every link in the "All downloads" table returns **200**, not 404
- [ ] `https://<host>/source/` serves the tarball
- [ ] The downloaded `.msi` installs and RemoteX comes online **without** any manual
      server configuration (it ships pointing at `relay.slbrothers.co.uk`)

Quick link check:

```bash
for f in RemoteX-Windows-x86_64.msi RemoteX-Windows-x86_64.exe \
         RemoteX-macOS-AppleSilicon.dmg RemoteX-macOS-Intel.dmg \
         RemoteX-Android-universal.apk RemoteX-Linux-x86_64.deb \
         RemoteX-Linux-x86_64.rpm RemoteX-Linux-x86_64.AppImage; do
  printf '%-40s %s\n' "$f" "$(curl -s -o /dev/null -w '%{http_code}' https://<host>/download/$f)"
done
```

## 6. Only then: make the repo private

Do **not** flip repository visibility until §5 passes. See
[`../DEVOPS.md`](../DEVOPS.md) for the full runbook, including the in-app links that
must be repointed off GitHub first, and the Actions minute budget a private repo
drops us to.
