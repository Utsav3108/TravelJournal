---
name: reproduce-and-bisect
description: Use when the user reports a bug, crash, visual glitch or "it doesn't work" and the cause is not obvious; reproduce it in code, compare with a clean baseline, and bisect by reverting changed files before proposing a fix.
---

# Reproduce, baseline, bisect

Guessing at fixes cost several rounds in past sessions. Do this instead.

1. **Reproduce in code first.** Write the smallest test that fails the way the user describes: a unit test for logic, or a view hosted off screen in a test (`NSHostingController` in an `NSWindow`, then measure what matters) for visual bugs. No fix before something fails. Never drive the running app.
2. **Check a clean baseline.** Add a throwaway worktree of the last good commit (`git worktree add --detach <path> HEAD`), copy the new test in, and run it there. Passing means the bug is in your changes; failing means it already existed and is not yours to fix silently. Remove the worktree afterwards (`git worktree remove --force`).
3. **Bisect by file.** In the working tree, restore one changed file at a time to its committed version (`git show HEAD:<path> > <path>`, back up the current copy first) and rerun the test. The file whose revert makes it pass holds the cause. Then bisect inside that file.
4. **Fix and keep the test.** The reproduction becomes a regression test. Run the related suites and the full suite once.
5. **Report honestly.** Say what you reproduced and what you only inferred. If the bug is intermittent and you could not reproduce it, say so and describe what you changed and why it should help, without claiming it is fixed.

Read test failures from an `.xcresult` (see `CLAUDE.md`). Compare before and after numbers (frame sizes, counts) instead of eyeballing.
