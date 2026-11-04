# Security and clinical-safety reporting

## What to report privately

Two kinds of problem, and the second is the one people forget:

1. **A security vulnerability** in the usual sense.
2. **Anything that could make a filed document wrong**: a report that
   misattributes a rating to the wrong configuration, a stimulation parameter
   rendered incorrectly, a number that loses precision, a silently truncated
   note. This app writes PDFs and Word documents that go into a patient record,
   so a correctness bug in that path has consequences a crash does not.

Report either through
[GitHub's private advisory form](https://github.com/neuromodulation/DBSAnnotator/security/advisories/new),
or by email to lucia.poma@wysscenter.ch if you would rather not use GitHub.

Please do **not** open a public issue for these first, and please do not attach
real patient data to a report of any kind. A synthetic example session ships at
`test/fixtures/`.

## What is in scope

The application is **offline by design**: it makes no network connection, has no
account, no server and no telemetry. It stores the files you save, one small
preferences file, a working copy of the session in progress in its own storage,
and short-lived copies made when you share or export a file. That removes most
of the usual attack surface: there is no endpoint to attack and no credential
to steal. Android backup is disabled for the app's own storage; on iOS and
iPadOS the in-app working copies are excluded from device and iCloud backup.
The realistic threats are local:

- data written somewhere the user did not intend, or reported as saved when it
  was not
- a crafted TSV causing incorrect parsing rather than a clean rejection
- a dependency shipping malicious code inside a release build
- an installer or package that is not what it claims to be

Distribution is in scope too. If you find a build attributed to this project
that we did not publish, that is a security report.

## What is not a vulnerability

- The app not preventing you from typing a real patient identifier. It records
  what you type; the naming convention is designed for pseudonymous labels, and
  choosing one is the user's decision.
- Files being readable by anyone who can read the device's filesystem. The app
  writes plain TSV on purpose, so the data outlives the software. Encryption at
  rest is the operating system's job, and full-disk encryption is worth having
  on any device used in clinic.
- Unsigned desktop builds warning on first launch. That is expected and
  documented; see the installation page.

## Supported versions

This is research software with one maintainer. Fixes land on `main` and go out
in the next release; there is no backport branch. If you need a fix in a build
you have already deployed, say so in the report.
