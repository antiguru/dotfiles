# Agent prompt templates

Fill in the bracketed parts. Run agents in the background and keep working on other steps.

## Prior-art survey

```
Literature and systems survey. Use WebSearch and WebFetch. Do not edit any files. Report in
terse prose with a citation (title, authors/org, year, URL) for every claim. Mark anything you
could not verify as UNVERIFIED.

Context: [what the target system is and the properties it requires, stated precisely].
Hypothesis: published work lacks [property A] + [property B] + [property C] together.
Candidate families we think fit: [list].

Answer:
1. Is the gap real? Search for [search terms]. For each system [list], state precisely what it
   guarantees and whether it has each property.
2. Incremental/streaming variants of the technique: what each maintains vs rebuilds.
3. Quality/performance numbers for the candidate families at [operating point].
4. Anything expressing the technique with [the target system's primitives].

End with a verdict: is the gap real, closest prior work, most promising family.
Keep under ~1200 words.
```

## Codebase capability survey (read-only, runs in parallel with the prior-art agent)

```
Read-only investigation in [repo]. Report with file:line citations, terse, under ~700 words.
Goal: how well [target system] can express [the prototype] today.
1. Does [feature/type/function] exist anywhere?
2. Which existing building blocks could express it, and are they allowed in [maintained context]?
3. How does [the relevant operator] behave under [updates/deletes]? Cost?
4. What is the smallest extension point for [missing primitive]? Name the files.
5. Any prior work on this in the repo or design docs?
```

## Reference numbers

```
Use WebSearch/WebFetch. No file edits. Citation for every number, UNVERIFIED otherwise.
Under ~800 words.
The prototype: [setup]. Measured: [numbers].
Find comparable published numbers (state hardware/threads/dataset) for: [systems and metrics].
Report grouped by system, then where the prototype stands.
```

## Product impact

```
Product-impact assessment. READ-ONLY: do not post, comment, react, edit or create anything in
Slack, Notion, Linear or elsewhere. Do not edit local files. Load deferred Slack/Notion tools
with ToolSearch first. If a source is inaccessible, say so instead of guessing.

Context: [what engineering has: measured strengths, measured weaknesses, staged plan].
Sources to read in full: [Slack thread URLs, Notion URLs]. Then search Slack/Notion for
[related terms] and cite each hit with a permalink.

Answer:
1. Internal demand: who, what, workload shape, urgency, link. Distinguish "wants X inside the
   product" from adjacent asks [name them].
2. Summarize the supplied docs: thesis, use cases, architecture, status, assumptions.
3. Market: size, commoditization, differentiators that still matter, direct competitors in the
   niche. Cite sources.
4. Use-case fit table: does our differentiator matter, does measured performance suffice,
   alternative, fit high/med/low.
5. Impact: who adopts, what it unlocks, what it does not win, risks, minimum viable scope.

Output under ~1800 words: executive summary with recommendation, demand table with links, docs
summary, market with citations, fit table, impact and MVP, open questions.
```
