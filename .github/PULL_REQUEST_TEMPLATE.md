## What does this change?

<!-- One or two sentences. Link an issue if there is one. -->

## Why?

<!-- The motivation — what was broken, missing, or awkward before this? -->

## How was this tested?

- [ ] `flutter analyze` and `flutter test` pass locally
- [ ] Tested against a real device (model/firmware: ______), OR explain why that wasn't possible
- [ ] Added/updated unit tests for any new protocol mapping or parsing logic

## Checklist

- [ ] No real device data (password, IMEI, phone number, IMSI/ICCID, MAC address, etc.) in code, tests, docs, or commit messages
- [ ] No new dependency under a copyleft license (GPL/LGPL/AGPL) — see `CONTRIBUTING.md`
- [ ] Protocol/auth details stay out of the UI layer (`lib/features/`) and out of `RouterRepository`
