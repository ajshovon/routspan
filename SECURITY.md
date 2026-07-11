# Security Policy

## Scope and threat model

Routspan is a client that talks **only to your router's admin API on your local network** —
there is no backend server, no analytics, and no telemetry. Nothing about your device, SIM, or
network leaves your phone except the requests you make to the router itself.

Two things worth understanding, which are properties of the router's own firmware rather than
something this app introduces:

- **The router's admin API is plain HTTP, not HTTPS.** This is how the OLAX M100 (and ZTE-lineage
  firmware generally) exposes its API — the app can't upgrade that. In practice this means anyone
  else on the same WiFi network as you and the router could potentially observe or interfere with
  that traffic. Only connect to routers on networks you trust.
- **Saved router passwords are stored in the platform secure store** (Keychain on iOS/macOS,
  Keystore on Android) via `flutter_secure_storage` — never in plaintext files, `SharedPreferences`,
  or logs.

## Supported versions

This project is pre-1.0 and evolving quickly. Security fixes land on `main`; there are no separate
maintained release branches yet.

## Reporting a vulnerability

Please **do not open a public issue** for security reports. Instead use GitHub's private
reporting flow:

**Repo → Security tab → "Report a vulnerability"**

This opens a private draft advisory visible only to the maintainer, so details (and any proof of
concept) aren't public until a fix is ready.

If you're reporting an issue with the *router's own firmware* (not this app) — e.g. an
authentication bypass in the device's HTTP API itself — please report that to the device vendor,
since this app can't fix vulnerabilities in firmware it doesn't control.
