# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/) once it reaches 1.0.

## [0.1.0] — 2026-07-12

Initial public release. OLAX M100 (ZTE-lineage `reqproc` firmware) is the only supported driver.

### Added

- Multi-router support: save several routers, pick one on launch, stored passwords, and a default
  router that auto-connects.
- Live dashboard: signal, network type/band, battery level, mobile-data on/off, data usage and
  plan/limit.
- SMS as threaded conversations (grouped by number), with send/delete/mark-read and inbox capacity.
- WiFi view/edit, including password reveal + copy.
- Connected-devices list with rename.
- USSD codes, reboot, power off, and factory reset.
- OLAX M100 protocol fully documented in [`docs/olax-m100-api.md`](docs/olax-m100-api.md).
