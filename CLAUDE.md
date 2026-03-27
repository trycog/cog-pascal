## Release Process

When the user says "release" (or similar), follow this procedure:

### 1. Determine the version

- If the user specifies a version, use it.
- *MUST* read the current version from `cog-extension.json` first and treat that manifest version as the canonical baseline for the next release. Do not derive the baseline version from git tags, commit messages, or GitHub releases when they disagree with the source tree.
- Do not bump to a new major version while the project is still on `0.x` unless the user explicitly instructs you to start a `1.x` (or higher) release. When the project is still on `0.x`, default to the appropriate `0.x` bump even if the changes would normally look "major" under full SemVer.
- Otherwise, analyze the unreleased commits since the last release commit/tag that matches the source-code version lineage and apply [Semantic Versioning](https://semver.org/):
  - **patch** (0.0.x): bug fixes, build fixes, documentation, dependency updates
  - **minor** (0.x.0): new features, new commands, non-breaking enhancements
  - **major** (x.0.0): breaking changes to CLI interface, config format, or public API
- If tags or history suggest a higher version than `cog-extension.json`, treat that as drift to be corrected instead of as the next release baseline.

### 2. Update version string

Update the version in the single source of truth:
- `cog-extension.json` - `"version": "X.Y.Z"`

No other files need updating — `cog-extension.json` is the single source of truth.

### 3. Review and update README.md

Ensure the README accurately reflects the current state of the project:
- New commands or features are documented
- Removed or renamed features are cleaned up
- Installation instructions are current
- Examples and usage sections match the actual CLI interface

### 4. Update CHANGELOG.md

Follow [Keep a Changelog](https://keepachangelog.com/):
- Add a new `## [X.Y.Z] - YYYY-MM-DD` section below `## [Unreleased]` (or below the header if no Unreleased section exists)
- Categorize changes under: Added, Changed, Deprecated, Removed, Fixed, Security
- Add a link reference at the bottom: `[X.Y.Z]: https://github.com/trycog/cog-pascal/releases/tag/vX.Y.Z`
- Each entry should be a concise, user-facing description (not a commit message)

### 5. Commit, tag, and push

```sh
git add cog-extension.json README.md CHANGELOG.md
git commit -m "Release X.Y.Z"
git tag vX.Y.Z
git push && git push origin vX.Y.Z
```

The GitHub Actions release workflow handles the rest: validating the tag matches `cog-extension.json`, running tests, and creating the GitHub Release.

Code intelligence, persistent memory, and interactive debugging.

**Truth hierarchy:** Current code > User statements > Cog knowledge.
<cog>
# Cog


## Code Intelligence

When you need a symbol definition, references, call sites, or type information:
use `cog_code_explore` or `cog_code_query`. Do NOT use Grep or Glob for symbol lookups.

- `cog_code_explore` — find symbols by name, return full definition bodies and file TOC
- `cog_code_query` — `find` (locate definitions), `refs` (find references), `symbols` (list file symbols)
- Include synonyms with `|`: `banner|header|splash`
- Glob patterns: `*init*`, `get*`, `Handle?`

Only fall back to Grep for string literals, log messages, or non-symbol text patterns.

## Debugging

Wrong output, unexpected state, or unclear crash: use the `cog-debug` sub-agent.
State your hypothesis before launching.
</cog>
