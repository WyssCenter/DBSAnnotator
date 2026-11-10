## What this changes

<!-- And why. If it fixes a bug, what the bug was. -->

## Checks

- [ ] `flutter analyze && flutter test` pass
- [ ] `uvx pre-commit@4.7.0 run --all-files` passes (this is what CI runs)
- [ ] If it changes the app: `newsfragments/<PR>.<type>.md` added
      (see `newsfragments/README.md`), or the `skip-changelog` label if nobody
      using the app would notice
- [ ] No real patient data anywhere in the diff, the tests, or a screenshot;
      the synthetic example at `test/fixtures/` is there for this
- [ ] If it changes the TSV format: `schema/*.json` and
      `lib/core/schema_columns.dart` updated (a test fails if they diverge)
- [ ] If it changes a report: checked what the PDF **and** the Word file
      actually look like. The tests assert the content model, not the
      rendering, so passing tests are not enough

## Tests

<!--
A test that would have caught the bug is worth far more than one asserting the
function runs. Several tests here exist because someone computed the expected
numbers independently and they disagreed with the code.
-->
