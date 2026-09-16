# Contributing to JawAtlas

Thank you for helping. JawAtlas is a free, offline CBCT study companion for dental students and educators, and it gets better every time someone who teaches, learns or builds adds to it.

There are two ways to contribute, and you do not need to write Swift for the first one.

## 1. Teaching cases and educational content (no code)

Annotated teaching cases are the single most valuable contribution this project can receive. If you are a dental educator, radiologist, resident or student:

1. Open a [teaching case proposal](https://github.com/Silvester969/JawAtlas/issues/new?template=teaching_case.yml).
2. Tell us which openly licensed scan you would like to use (CC BY, CC0 or similar) and what it should teach.
3. We will help you build it in the app: slice to each structure, mark it, caption it, save it as a moment, and export the case.

Ground rules for cases:

- Only openly licensed, fully de-identified data. Never share a scan from your own patients.
- Captions describe anatomy and radiological appearance. They are not diagnostic advice.
- Credit the dataset authors and license in the case notes.

You can also help by reporting unclear wording, suggesting a better explanation in the in-app explainer, or translating the interface.

## 2. Code

### Setup

You need macOS with Xcode 26 or newer, iOS 18 or newer on the target, and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/Silvester969/JawAtlas.git
cd JawAtlas
python3 scripts/fetch-demo-scan.py
scripts/generate.sh
open JawAtlas.xcodeproj
```

`fetch-demo-scan.py` downloads the single demo case (about 100 MB) from the public dataset. `generate.sh` creates the Xcode project from `project.yml`; the `.xcodeproj` is not committed, so rerun it whenever you add or remove files.

### Before you open a pull request

```bash
scripts/audit.sh
scripts/test.sh
```

Both must pass. `test.sh` uses the iPhone 17 Pro simulator by default; set `JAWATLAS_DESTINATION` to use another one.

### House rules

These are enforced by `scripts/audit.sh` and by review:

1. **No third-party dependencies.** Everything ships from this repository.
2. **No networking code of any kind** in `App`, `JawAtlasCore` or `Tests`. The app is offline by construction, and the audit greps for networking symbols.
3. **No comments in Swift sources.** Name things so the code explains itself; put reasoning in the pull request description.
4. **No patient identifiers.** The DICOM importer reads a whitelist of technical tags only. Any change near the importer needs a test proving no identifying string reaches storage.
5. **Education, not diagnosis.** Do not add features or wording that suggest clinical use.

### Good places to start

Look for issues labeled [`good first issue`](https://github.com/Silvester969/JawAtlas/labels/good%20first%20issue) or [`help wanted`](https://github.com/Silvester969/JawAtlas/labels/help%20wanted). Comment on an issue before starting larger work so we can agree on the approach.

### Pull request flow

1. Fork the repository and create a branch from `main`.
2. Keep each pull request focused on one change.
3. Add or update tests for behavior changes.
4. Fill in the pull request template, including screenshots for UI changes.
5. A maintainer will review, usually within a few days.

## Reporting bugs and ideas

- Bugs: use the [bug report form](https://github.com/Silvester969/JawAtlas/issues/new?template=bug_report.yml).
- Ideas: use the [feature request form](https://github.com/Silvester969/JawAtlas/issues/new?template=feature_request.yml).
- Questions and show-and-tell: use [Discussions](https://github.com/Silvester969/JawAtlas/discussions).
- Security issues: follow [SECURITY.md](SECURITY.md), not public issues.

By contributing you agree that your contributions are licensed under the [Apache License 2.0](LICENSE) and that you will follow the [Code of Conduct](CODE_OF_CONDUCT.md).
