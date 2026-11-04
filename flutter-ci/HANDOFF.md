# Flutter CI candidate

Frozen source-only mirror: `.github/workflows/dart.yml`. Active app untouched.

- Enforce the committed lock at the existing dependency install; later analyzer/tests use `--no-pub`.
- Analyzer errors/warnings are fatal; the accepted informational baseline is explicitly nonfatal.
- Add one serial Chrome gate naming exactly the three current `@TestOn('browser')` files (Stripe, callbacks, MFA). Default VM coverage discovery, native-only wallet/notification tests, Bash pipeline failure behavior, JUnit/coverage reports, dummy public config, toolchain and action versions remain unchanged. Browser step follows report uploads so a browser failure does not discard completed VM reports.
- No new dependencies/actions, application/native changes, privileged secrets or deployment.

Source evidence: pinned Flutter 3.38.10 `commands/test.dart` supports `chrome`; `test/flutter_web_platform.dart:648` launches headless unless paused; `web/chrome.dart:28` selects `google-chrome` on Linux. `commands/analyze.dart` supports both fatality flags. GitHub's Ubuntu runner inventory includes Chrome: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md#browsers-and-drivers

QA first: parse YAML with existing Ruby YAML; compare the candidate against active; assert enforced-lock install, analyzer flags, all three browser annotations matched exactly, no VM-only file in Chrome arguments, unchanged action/toolchain/config/report steps and fatal Bash pipeline semantics. No local browser, full suite, build or install authorized by this handoff. No author runtime checks or GitHub run claimed. Future hosted CI executes the commands in the workflow; headless browser execution remains unverified until that run.
