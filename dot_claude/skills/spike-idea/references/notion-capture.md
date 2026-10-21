# Capturing a spike in Notion

## Destination

The skill stores no workspace identifiers, because it is published in a public dotfiles repo.
Resolve them at run time:

* Find the database with `notion-search` for "Spiking ideas" (the user's own database). If the
  user pasted a link, use that instead.
* `notion-fetch` the database. Use its `collection://` URL as the `data_source_id` parent and
  check the property names against the table below.
* Get the owner with `notion-get-users` and `user_id: "self"`.

## Properties

| Property | Value |
|---|---|
| `Name` | Short title naming the capability, e.g. "Deterministic, incremental vector search (IVF) in Materialize" |
| `Type` | `Spike` for a spike, `Idea` before any probe, `Design` for a design doc, `Outcome` for a decision record |
| `Status` | `In review` while a decision is pending, `Done` when decided, `Parked` when shelved, `In progress` while running, `Backlog` for untouched ideas |
| `Owner` | `["<id from notion-get-users self>"]` |
| `Summary` | Two or three sentences: the question, why it is open, the approach |
| `Outcome` | Two or three sentences: key numbers, product signal, recommendation |
| `Related entries` | Only when the user names related entries |

## Page body

Notion markdown uses `-` for bullets and `<table>` XML for tables. Read
`notion://docs/enhanced-markdown-spec` via `notion-fetch` if unsure. Write prose in the user's
documentation style: concise, active voice, headers capitalized only on the first word.

Sections, in order (drop ones a quick spike did not do):

1. Question
2. Literature check (closest prior work, one line each)
3. Design that fits (the mechanism and why it meets the constraints)
4. Spike results (setup line, results table, determinism and equivalence checks)
5. Dead ends
6. Comparison with other systems
7. Gaps in the target system
8. Product assessment (demand, market, links to the user's sources)
9. Recommendation (numbered, staged)
10. Open questions

11. Resume context
12. Sessions

End the body before `Resume context` with a line stating that the spike code is throwaway and not
committed.

## Resume context

The page is the durable record of the spike. A later session must be able to pick it up from the
page alone, because session transcripts expire (see below). Record only what the other sections
do not already say:

- Base: repository and commit the analysis or prototype ran against.
- Artifacts: branches, worktrees, draft PRs, and where throwaway code lived. Code in a scratchpad
  is gone once the session ends, so say so, and quote any snippet that is needed to rerun a
  measurement.
- Environment: how a measurement was set up, if the results section does not already state it.
- Leads checked and dropped that are not in `Dead ends`, one line each with the reason.
- Decisions taken after the page was first written, if they changed the design.
- Next step: the single concrete action to take first.

Update this section whenever a later session moves the spike forward.

## Sessions

Add a `Sessions` section after `Resume context`, so the entry can be traced to the session that
wrote it while the transcript still exists. The session id is in `$CLAUDE_CODE_SESSION_ID`. Read
it, the hostname, and the working directory with Bash at capture time. A transcript lives only on
that host, under `~/.claude/projects/<cwd with / replaced by ->/<id>.jsonl`, and Claude Code
deletes it after `cleanupPeriodDays` (30 by default). Never upload transcripts to Notion: they
hold raw tool output, including account names and anything a command printed.

One bullet per session that created or substantially updated the entry. Append a bullet for
each later session, and never replace an earlier one:

```
- 2026-10-05, `<session id>` on `<host>`, `<cwd>`: created. Local transcript, expires after cleanupPeriodDays. Resume with `claude --resume <session id>`.
```
