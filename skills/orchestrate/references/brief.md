# Writing a delegate brief

Read this when composing a brief for a delegate, or when a delegate's output missed the mark
(the fix is almost always a better brief, not a different model).

A delegate is a fresh process with **zero** shared context: no conversation, no memory of the repo
tour you did, no idea what "done" means. The brief is the entire contract.

## Template

```markdown
# Task: <one-line goal, imperative>

## Context
- Repo: /abs/path (branch: <name>). Language/stack: <…>. Package manager / task runner: <…>.
- Relevant files: <paths, with one clause each on what they do>
- Conventions to follow: <error handling style, naming, test layout, lint rules — cite an exemplar file>
- Why this task exists / current behaviour: <2–5 lines>

## Requirements
1. <testable requirement>
2. <testable requirement>
3. Edge cases: <list>

## Constraints
- Do NOT modify: <paths>. Do NOT commit. Do NOT install global deps or change lockfiles unless required by the task.
- Stay within: <dir>. Keep the diff minimal and focused; no drive-by refactors.
- If something is ambiguous, choose the simplest interpretation consistent with existing code and say so in the report.

## Verification (run before finishing; include output in report)
- `<real test command>`      e.g. `pnpm test -- --filter foo`, `mix test test/foo_test.exs`, `pytest tests/foo`
- `<real lint/typecheck>`    e.g. `pnpm typecheck`, `ruff check .`, `mix format --check-formatted`

## Report (your final message MUST contain)
1. Files changed (list) and a 3–6 line summary of the approach.
2. Commands run for verification and their pass/fail results (paste key lines).
3. Anything you could not do, skipped, or are unsure about.
4. Open questions for the orchestrator.
```

## Rules of thumb
- **One task per brief.** Sprawling briefs drift; split and run in parallel instead.
- **Real gates only.** Discover commands from package.json / Makefile / mix.exs / pyproject / CI yaml.
  Never invent a command — a delegate that can't run your gate will silently skip it.
- **Point at exemplars.** "Follow the pattern in `src/x/handler.ts`" beats a paragraph of style rules.
- **State the report contract.** What lands in `result.md` is what you get; ask for exactly what you
  need to verify quickly (files, commands, results, doubts).
- **Say what not to touch.** Scope creep is the #1 delegate failure mode; forbidden paths make it checkable.
- **Review briefs** (`--mode read`): include the spec + the diff (or the branch/commit to inspect) and
  demand `PASS`/`FAIL` with `file:line` findings and severity; no rewriting.
- **Retry briefs**: append `## Previous attempt` with the failing gate output and what was wrong;
  keep everything else identical so the delegate targets the fix.
- **Size the effort**: `--effort low` for mechanical/boilerplate, `high|xhigh` for gnarly bugs; a
  cheap model with a great brief beats a great model with a vague one.
