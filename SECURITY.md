# Security reporting status

Fairpane is not a released browser.
This repository has no private security reporting channel yet.
The channel is an owner decision, and `engineering/decisions/0009-release-and-stewardship.md` records it as `open` until an owner record exists.
No email address or other contact in this repository is a security contact.
Until the owner enables a channel, do not put vulnerability details in a public issue or pull request.

## Requirements before a release

`docs/SECURITY.md` defines these requirements in full.
The owner approves the response targets below together with the reporting channel.

- A private channel keeps each report private until disclosure, reaches at least two maintainers with release authority, and records when each report arrives.
- Responders acknowledge each report within 3 business days and assign a severity of Critical, High, Medium, or Low within 7 days.
- Responders publish an advisory when a fixed release is available or 90 days after the report, whichever comes first, and within 7 days for an issue exploited in the wild.
- A patch release adds a regression test that fails before the fix, passes every applicable gate, and ships with its source archive, provenance statement, and reproducibility report.

Do not put credentials or private user data in issues or test fixtures.
Do not run hostile web content outside an appropriate sandbox.
The repository's threat model is in `docs/SECURITY.md`.
