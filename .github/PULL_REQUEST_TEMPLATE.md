## Summary

<!-- What changed and why. -->

## Out of scope

<!-- What was intentionally left out of this change. -->

## Checklist

- [ ] Tests pass: `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1`
- [ ] CI checks pass (or known/unrelated failures are noted), as listed in `CONTRIBUTING.md`:
  - [ ] `pwsh -NoProfile -File tools/Test-TextEncoding.ps1`
  - [ ] `pwsh -NoProfile -File tools/Test-PsScriptsParse.ps1`
  - [ ] `pwsh -NoProfile -File tools/Test-PyScriptsParse.ps1`
  - [ ] `pwsh -NoProfile -File tools/Test-MarkdownFences.ps1`
  - [ ] `pwsh -NoProfile -File tools/Test-MarkdownLinks.ps1`
  - [ ] `pwsh -NoProfile -File tools/Test-ScriptInventory.ps1`
  - [ ] `pwsh -NoProfile -File tools/Test-CodeLanguage.ps1`
- [ ] For a behavior change: RED observed before the fix, GREEN after (strict TDD)
- [ ] A file that is moved, translated, or condensed is changed in a commit of its own, so git history holds the untouched version
- [ ] Documentation updated (README, `docs/`, `CHANGELOG.md` when user-visible) for any behavior or contract change
- [ ] Commit messages follow Conventional Commits, in English, with no AI attribution
- [ ] No real KB data, customer data, or credentials in any example, fixture, or test
