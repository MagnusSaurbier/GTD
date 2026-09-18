# GTDMarkdown

Markdown ⇄ model: YAML frontmatter and `# Heading` body sections, via Yams. The only target that parses or produces note text.

**Owned by T10** — T00 created only the public signatures listed in `docs/ARCHITECTURE.md` §4
so that dependants compile. The bodies throw `notImplemented` or return empty values.

## Platform guards (ARCHITECTURE §5)

Foundation-only; no SwiftUI, no file system. Everything here must compile on Linux — the round-trip tests (N2) are the most valuable tests in the repo and have to run in CI without Xcode.

## Testing

`cd Packages/GTDKit && swift test --filter GTDMarkdownTests`
