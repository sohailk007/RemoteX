# RemoteX Privacy Statement

**Last updated:** 2026-07-16
**Provider:** SL Brothers

> ⚠️ **Template — review before you rely on it.** This is a starting point written to
> match how RemoteX actually behaves. Have it reviewed by a legal professional and
> adjust it to your jurisdiction and your actual deployment before publishing it to
> customers.

## What RemoteX is

RemoteX is a remote desktop and remote support application. A support session is
established between two devices using a **Session ID** and a **one-time password**.

## What we collect

RemoteX is designed to keep your data with you:

- **We do not collect the contents of your remote sessions.** Screen contents,
  keystrokes, mouse input, files transferred, and clipboard data are transmitted
  between the two devices and are **not stored** by us.
- **IP addresses are not shared between the two parties.** Neither the customer nor
  the technician sees the other's public IP address. Connections are made using the
  Session ID only.
- **No account is required** to use RemoteX.

## What our server processes

To connect two devices, RemoteX uses a rendezvous/relay server operated by SL Brothers:

- **Session ID and network address** are processed so the two devices can find each
  other and establish a connection. This is required for the service to function.
- **Relay traffic:** if a direct peer-to-peer connection cannot be established, session
  traffic is relayed through our server. This traffic is **end-to-end encrypted** and is
  **not stored or inspected**; it is passed through only for the duration of the session.
- **Connection logs** may be retained for a limited period for security,
  troubleshooting, and abuse prevention.

## Encryption

Connections are end-to-end encrypted. Sessions require the Session ID **and** the
password; a session cannot be established without both.

## Your control

- Either party can end a session at any time by clicking Disconnect or closing the app.
- The controlled device shows an indicator while a session is active.
- Remote control requires the permission of the person at the controlled device.

## Third parties

We do not sell or share session data with third parties.

If you use a build of RemoteX that is configured to use a **public/default server**
rather than an SL Brothers server, connection coordination is handled by that server's
operator instead, under their terms.

## Open source

RemoteX is open-source software licensed under the **AGPL-3.0**, based on the RustDesk
project. The complete corresponding source code, including our modifications, is
available at:

https://github.com/sohailk007/RemoteX

## Contact

For privacy questions, contact SL Brothers.
