---
name: map
description: Draw the review map of a pull request or a stack of them. Diple invokes this with a JSON input that already lists every domain and module the diff changed; the skill adds what only reading the code can tell, and answers with one JSON object the app renders as a canvas. Use only when invoked by Diple with that input.
---

# Draw the map

The reviewer is about to open a PR they did not write. The canvas you feed tells them, before the first line of diff, how deep this change goes and what they must hold in their head to judge it.

Diple already did the cheap part. The input lists the domains and modules the diff touched, with churn and the file that changed most in each. That layer is exact and costs no tokens. Do not recount it, do not re-derive it, do not list files back.

Your job is the part that needs judgement, and it has four pieces.

## 1. Intent

One sentence, what the change is trying to do, the way a colleague says it across the desk. Not a description of the diff. "Stops charging Salvy's own companies for real" is intent; "adds a DemoPaymentProvider and changes ChargeInvoice" is diff.

Then up to three `deltas`: short tags a reviewer scans in a second, each a fact about the change's reach. "changes behaviour on invoice generation", "no schema change", "public API untouched". Only say what you checked.

## 2. Domains

For each domain id in the input, one line saying what that domain is responsible for **in this codebase**, and what this change does to it. Read its entry point or its README when there is one. Skip a domain you could not say anything true about rather than inventing.

## 3. Edges between changed modules

Draw the dependencies among the changed modules that a reviewer needs to follow the change: who calls whom, who emits the event another listens to, who implements the port another declares. Label each in two or three words (`calls`, `implements port`, `emits InvoicePaid`). Only between ids present in the input. Skip edges that are just "same folder".

## 4. What feels it, and what you need to know

**Affected**: modules the diff does **not** touch that depend on what changed. The input's `candidates` already lists files outside the diff that mention a changed file, found by a local `git grep` before you started. Start there: most answers are in that list, and confirming a candidate costs one ranged `Read`. Grep for more only when a changed symbol is clearly used under another name. For each one, give the real path, a line when it points at the call site, the changed module id it depends on (`from`), and in a few words **why** it feels the change. "inherits the new throw without handling it" counts. "uses that module" does not. A candidate that only imports a type and is not affected by the change is not affected: leave it out. At most six.

**Context**: what someone must know to judge this change that is not in the diff. An implicit business rule, a vendor contract, an invariant the code assumes without writing down, a state machine, a deploy ordering. Say why a review is weak without it and where to read it (`location`, a real path, or a doc). Attach it to the module it explains (`about`). At most four. An empty list is a fine answer.

## Budget

Speed matters: a person is watching a timer. Aim for three or four rounds of tools and about ten calls in total, then answer.

- Batch. Every round, issue all the independent calls you already know you need in the same turn, so they run in parallel: the per-module diffs together, the candidate reads together. One call per turn is the slowest way to do this.
- Never run the same search twice. One `Grep` with a regex alternation over the repository beats five greps for the same symbol in different folders.
- `Grep` for importers and callers before any `Read`.
- `Read` only entry points, ports, and the most-changed file of a module, and prefer a range over a whole file.
- `git diff <base>...HEAD -- <path>` for one module at a time, never the full diff of a large change.
- Never walk the repository tree to "get oriented". The input already oriented you.

## Rules

- Every `path` and `location` must exist in the worktree. If you are not sure, leave it out.
- Every `from`, `about` and edge endpoint must be an id from the input.
- Write prose in the language the input asks for. Keep identifiers as they are in the code.
- Answer with the JSON object only. No code fence, no text before or after.

```
{"intent":"...",
 "deltas":["..."],
 "domains":[{"id":"d:src/billing","summary":"..."}],
 "edges":[{"from":"m:src/billing/use-cases","to":"m:src/billing/adapters","label":"calls"}],
 "affected":[{"name":"iugu webhook","path":"src/iugu/use-cases/handle-iugu-webhook.ts","line":50,"from":"m:src/billing/domain","why":"..."}],
 "context":[{"title":"...","why":"...","location":"docs/billing/states.md","about":"m:src/billing/domain"}]}
```
