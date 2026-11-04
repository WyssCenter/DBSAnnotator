# Changelog fragments

`CHANGELOG.md` is built by [Towncrier](https://towncrier.readthedocs.io/) from one small
file per pull request in this folder, using the
[Types of changes](https://keepachangelog.com/en/1.1.0/) of *Keep a Changelog* 1.1.0:
**Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.

## Adding one

For pull request `123`, add `newsfragments/123.<type>.md`, where `<type>` is one of
`added`, `changed`, `deprecated`, `removed`, `fixed`, `security`. A second fragment of
the same type takes a counter: `123.fixed.1.md`.

The file holds one or two sentences for the person who uses the app, saying what
changed for them, for example:

`Notes on a day with no session get their own row in the Visits table.`

Write what a clinician or analyst would notice, not how it was done. A change to the TSV
format, or to what a report says, always gets a fragment: reports are filed in patient
records, and their readers need to know which version said what.

## When CI asks for one

A pull request that changes the app (`lib/`, `schema/`, `assets/`, a platform folder or
`pubspec.yaml`) must add a fragment named after its own number. Open the PR first to
learn the number. Changes nobody using the app would notice (tests, CI, refactors)
take the `skip-changelog` label instead. Dependabot updates are exempt.

## At release

For a final release, `dart run tool/release.dart` runs
`uvx towncrier build --version X.Y.Z --yes`, which moves every fragment into
`CHANGELOG.md` under the new version and deletes the files. Pre-releases (`-alpha.N`,
`-beta.N`, `-rc.N`) leave the fragments in place. `.github/RELEASING.md` has the full step.
