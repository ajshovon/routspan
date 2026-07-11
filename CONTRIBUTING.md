# Contributing

Thanks for helping! Two kinds of contributions are especially valuable early on.

## 1. Complete the OLAX M100 API spec

Capture your unit's traffic (DevTools → Network) and fill in
[`docs/olax-m100-api.md`](docs/olax-m100-api.md). Paste redacted JSON responses into
`test/fixtures/`. This directly unblocks features.

## 2. Add a new router (future driver model)

The code intentionally ships **OLAX-only** today, with a thin seam ready for extraction:

- `lib/data/router_repository.dart` — the abstract `RouterRepository` interface + vendor-neutral
  domain models. **Do not** put vendor specifics here.
- `lib/data/olax/` — the OLAX/ZTE driver: `ZteApiTransport` (protocol) + `OlaxM100Client` (maps
  neutral calls ↔ `cmd`/`goformId`).

To add a router:

1. Create `lib/data/<vendor>/<model>_client.dart` implementing `RouterRepository`.
2. If it shares the ZTE protocol, reuse `ZteApiTransport` with a different `ZteConfig`.
   Otherwise add a new transport.
3. Introduce a small factory that picks a driver from a saved "connection profile" (this is the
   point where we formalize the driver registry — keep it minimal).

## Code style

- `flutter analyze` and `flutter test` must pass.
- Keep protocol/auth details out of the UI and out of the repository interface.
- Add unit tests for any crypto/parsing logic (these are the fragile parts).

## Licensing of contributions

Routspan is MIT-licensed. By submitting a contribution you agree to license it under the same
[MIT License](LICENSE) (inbound = outbound), and you confirm you have the right to do so. Don't
add dependencies under copyleft licenses (GPL/LGPL/AGPL) or commit vendor firmware, proprietary
assets, or unredacted device captures (IMEI, phone numbers, SMS, passwords).
