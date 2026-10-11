---
name: project-docs
description: Keep this repository's documentation current. Use at the end of every work session, after any result worth keeping (new metrics, model, video, decision, user feedback), when a new command is used, or when the user asks to update, sync or reorganise docs.
---

# Project documentation

The repository documentation is the project's memory between chats. It must let a new chat (or a person) understand where the project stands and continue without this conversation.

## Rules

- **Language:** all repository documentation is in English, even when the conversation is in Ukrainian.
- **Where things go:**
  - `README.md`: what the project is, setup, and **every command that has been run** with what it does, its arguments and caveats. No status, no results.
  - `docs/`: stable content that changes rarely: vision, requirements, architecture, phases (plan), testing strategy, risks, business plan, decisions, research.
  - `specs/`: content that changes often: per-phase status, results, backlog, datasets and models, raw metrics.
  - `CLAUDE.md`: short entry point for Claude; update only when working rules change.
- **Do not duplicate:** a number lives in one place (usually `specs/results.md`); other files link to it.
- **Facts only:** every number comes from a run in this project or a cited source. Mark estimates as estimates. Never present an untested idea as done.
- **Dates:** use absolute dates (YYYY-MM-DD) and update the "Last updated" line of every `specs/` file you touch.
- **Code comments** may stay as they are; documents may not be in another language.

## End-of-session checklist

1. `specs/status.md`, for each phase touched:
   - move finished items to **Done** (with the key number);
   - update **To do**;
   - add **Difficulties** met (what went wrong and how it was worked around);
   - add **Lessons learned** (what to do differently next time);
   - update the status table at the top.
2. `specs/results.md`: one row per new run worth keeping (date, version, match, method, metrics); precision spot-checks; goal checklist entries.
3. `specs/backlog.md`: add new issues (from user feedback especially) with problem, likely causes, ideas, "done when"; reorder priorities; remove finished items.
4. `specs/datasets.md`: new videos (file, venue, conditions, resolution, length, licence) and models (file, training data, licence).
5. `README.md`: any new script, flag or shell command used during the session, in the commands table or the utilities section, with what it does.
6. `docs/decisions.md`: append decisions made in the session to the decision log (date, decision, why).
7. `docs/` other files: change only if the plan itself changed (new requirement, new phase criterion, new risk). Mention the change in the decision log.
8. Commit with a message that says what changed in the docs, then push.

## Templates

Status entry for a phase:

```markdown
## Phase N: name

**Status:** not started | in progress | done | done with caveats (say which).

**Done**
- What was delivered, with the key number.

**To do**
- Open items (details in backlog.md).

**Difficulties**
- What blocked or failed, and the workaround.

**Lessons learned**
- What to repeat or avoid next time.
```

Backlog item:

```markdown
### N. Title (requirement ID if any)
- **Problem:** what is wrong, with evidence (file, time, metric, user quote).
- **Likely causes:** ...
- **Ideas:** ...
- **Done when:** a measurable condition.
```

Results row: `| YYYY-MM-DD | version | match | method | ball found | in crop | players | max pan |`

## Starting a new chat on this project

Point the new chat at the repository and say: "Read CLAUDE.md, specs/status.md and specs/backlog.md, then continue with the top backlog item." Everything needed should be in the repository; if something is missing, that is a documentation bug to fix with this skill.
