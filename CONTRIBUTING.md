# Contributing to Latch

Latch is deliberately small: five shell scripts and a thin CLI dispatcher, zero
dependencies beyond `ssh` and `curl`. Keep it that way. A pull request that adds a
language runtime, a package manager, or a config-file format needs a very good reason
in its description.

## Before you open a PR

1. **Run `./latch doctor <your-own-anchor>` against something real.** Every script in
   this repo was written by encountering a real 403, a real stale-lock, a real
   `HeadlessChrome` fingerprint leak, and fixing it — not by guessing at the shape of
   the problem. If your change can't be exercised against a real anchor device, explain
   in the PR how you validated it (a mock SSH target is fine if you say so).
2. **`shellcheck` clean.** CI runs it on every push; run it locally first:
   ```bash
   shellcheck bin/*.sh latch
   ```
3. **Keep the five-script shape.** `start` launches, `tunnel` connects, `status`
   verifies, `stop` tears down, `doctor` preflights. If your feature doesn't fit one of
   those five verbs, it probably belongs in a new, separate script (and a new `latch`
   subcommand) rather than bolted onto an existing one.
4. **Update the README's "What Latch does NOT solve" section** if you're closing a gap
   it lists — don't leave stale limitations documented once they're fixed.

## Reporting a target site that still blocks Latch

Open an issue with:
- The site and the exact blocking behavior (HTTP status, WAF vendor if known).
- Output of `latch status` at the time of the block.
- Whether the block persists with a **non-headless** anchor browser (some WAFs key off
  more than the `HeadlessChrome` UA string — this tells us whether the fix belongs in
  Latch's fingerprint layer or is out of scope, per the README's stated limits).

## Code style

- `set -euo pipefail` at the top of every script, no exceptions.
- Every script accepts its anchor as `$1` and prints a `[latch] ...` prefixed status
  line for each major step — that prefix is what makes multi-script output greppable
  when several scripts are piped through a supervisor/log aggregator.
- Prefer explicit `ssh ... bash -s -- <args>` heredocs over long single-line `ssh`
  command strings — the heredoc form is what survived actual debugging; single-line
  quoting across an SSH boundary is a proven source of silent failures (see the
  README's Origin section).
