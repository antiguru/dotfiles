---
name: spike-idea
description: Run a technical idea spike end to end and record it in the "Spiking ideas" Notion database. Use whenever the user wants to explore, prototype, or test the feasibility of an idea ("spike this", "is it feasible to...", "could we do X in Materialize", "look into this gap", "quick and dirty prototype", "how would this compare to..."), wants a prior-art or market check on a technical idea, wants to estimate product impact of an engineering idea, or asks to capture a spike's findings in Notion. Covers framing with a pass/fail envelope, prior-art survey, prototyping on the cheapest faithful substrate, measurement hygiene, reference numbers, product impact, capture, and the hand-off to design.
---

# Spike an idea

A spike answers a question. Its output is a decision plus evidence, never code to keep. This skill
encodes the order that makes a spike cheap and its verdict trustworthy: fix what "pass" means
before measuring, check prior art before building, prototype on a substrate that transfers, and
check product pull before investing in design.

## Pick the depth first

Say which depth you chose so the user can override it.

* **Quick feasibility** ("can we...", one mechanism, under a day): steps 1, 3, 4, 8.
* **Full spike** (new capability, competitive claim, or anything heading toward a design doc):
  all steps.

Steps 2, 5, 6, and 7 are the ones that are easy to skip and expensive to have skipped on a full
spike: building something that exists, losing the failed variants, numbers without context, and
designing what nobody asked for.

## 1. Frame the question and the envelope

Write the question in one sentence and the hypothesis behind it. Then propose an envelope: the
concrete numbers that decide pass or fail (dataset and scale, quality metric, latency, memory as a
multiple of raw data, per-update cost, rebuild cost, whatever applies). Get the user to accept or
correct it before measuring anything.

The envelope turns "it seems fine" into a decision, and it is what lets an early, cheaper substrate
gate a later, expensive one ("if it misses in the prototype, it will miss in the product").

Ask one question at a time, only the ones whose answer changes the probe. Example of a good one:
"Which query shape matters: ad-hoc, standing, or both?"

## 2. Prior art (full spike)

Launch a background research agent with WebSearch. Give it the precise property combination being
claimed as novel, the candidate technique families, and the systems to check. Require a citation
for every claim and `UNVERIFIED` for anything unsourced, and ask for a verdict: is the gap real,
what is the closest prior work, which family looks most promising. See
`references/agent-prompts.md` for a template.

Do not duplicate the agent's work while it runs. Use the time for step 3 setup or for a parallel
read-only codebase survey of what the target system can express today.

## 3. Prototype on the cheapest faithful substrate

Prototype outside the target system when that is cheaper (for Materialize: plain timely and
differential dataflow, same crate versions as the workspace), but restrict the prototype to
operators the target system has, plus extensions you name explicitly as asks. A pass using
operators the target cannot express proves nothing about the target.

* Throwaway code lives in the session scratchpad, never in the repo, and is labeled throwaway.
* Use real public data at the envelope's scale (for vectors: SIFT1M from the TEXMEX corpus).
* Keep each variant runnable (copy to `src/bin/<variant>.rs` before rewriting `main.rs`) so later
  comparisons rerun old designs under the same harness.
* When the user pushes back on a design point (cost model, parallelism, unsupported operators),
  re-derive the design before measuring further.

## 4. Measurement hygiene

These are the traps that produced wrong numbers or hangs in past spikes:

* **Native baseline on the same hardware.** Implement the same algorithm without the framework.
  It separates framework overhead from algorithm cost and checks result equivalence (identical
  recall means identical answers).
* **Determinism.** If the system promises deterministic results, hash the consolidated output log
  `(data, time, diff)` and compare digests across worker counts, record placement, and input
  order or batching.
* **Memory.** Report RSS after `malloc_trim(0)`, minus the RSS of loaded input files. Untrimmed
  glibc RSS keeps transient peaks and overstates steady state.
* **CPU vs wall.** Report both. Per-update cost is CPU time divided by changes.
* **Waiting on runs.** Wait on a PID or an output file. `pgrep -f PATTERN` inside a `bash -c`
  loop matches its own command line and never exits.
* **Memory caps.** Run under `memcap`, so a blowup is an OOM result, not a frozen machine.
* **Contention.** Run timing runs alone. Determinism-only runs may run concurrently.

## 5. Record dead ends (full spike)

When a variant fails, keep the failure and its mechanism ("delta-join variant: query vector cloned
into every intermediate tuple, OOM at 24 GB"). A named failure mode prevents someone from
re-trying it and often states a constraint on the eventual design.

## 6. Reference numbers (full spike)

Launch a background agent to collect published numbers for comparable systems at a comparable
operating point, with hardware, threads, dataset, and source for each. Present results as a table
with the spike's numbers in it, and caveat apples-to-oranges comparisons (dimensions, threads,
batching). State plainly where the spike loses.

## 7. Product impact (full spike)

Before any design work, launch a read-only agent over the sources the user supplies (Slack
threads, Notion pages) plus a targeted search and a market scan. Tell it not to post, comment, or
edit anything. Ask it to separate "wants X in our product" from adjacent asks (for example "wants
us to feed an external system"), map use cases against the spike's measured strengths and
weaknesses, and recommend a minimum scope with risks. Template in `references/agent-prompts.md`.

Give your own take on its recommendation. Push back where the evidence is thin.

## 8. Capture

Write the entry in the user's Notion "Spiking ideas" database. Details, field mapping, and page
layout are in `references/notion-capture.md`. Also save the durable findings to auto-memory
(one memory file per spike, updated as the spike progresses).

Anonymize customers, prospects, and accounts in everything persisted ("two accounts asked...").
Public product and project names are fine.

## 9. Hand-off

A spike ends with a recommendation. Turning it into product code is a new task: classify it with
the brainstorming skill (usually architectural, so questions, approaches, written spec, then a
plan). Do not carry spike code over.
