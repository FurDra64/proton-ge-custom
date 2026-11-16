# Knowledge rule (OP-4)

All resolutions are recorded as knowledge. No fix closes without a record.

## Where

- `docs/` in this repo: one summary file per session cluster (this file).
- Obsidian Knowledge (`Knowledge/Troubleshooting/proton-*.md`): one note per topic,
  linked from `Knowledge/_index.md`.

## Record template

Each topic: symptom (+zahlen) / root cause (evidence: commit, task, log) / fix /
lesson (rule for next time).

## Topics recorded 2026-11-17 (task t_1db9d428)

### 1. pulse_period framework missing (t_84eccdf9)

Official `proton --check`: 310 failed / 384 passed. The ds5 0035/0058 and
video-0005/0020 FAILEDs share one root cause: `struct pulse_period` is defined
nowhere — not in base, wine-owned, or any series (verified on a real-apply
shadow, not by grep alone). The sa-1 assumption "video-0005 provides the
framework" was wrong; 0005 is itself a consumer. Lost from the base side at the
11/16 19:00 wine rebase, so patch repair cannot fix it. Needs a base-restore vs
series-redesign decision. Lesson: "consumer exists but no definition" means
missing framework; never trust a provider assumption without grep proof.

### 2. --check harness silent skips (cd1ea0af1, 4b56d34ac)

`git apply` in a non-repo shadow dir silently skips `diff --git` patches
(766 silent skips measured), cascading into bogus FAILEDs. Fix: `git init` +
commit base in the shadow before dry-run. Same commits fixed the numstat count
(`wc -l` instead of digit-concatenation) and the EXIT trap (`cd / && rm -rf`
because cwd sits inside $SHADOW). Lesson: when --check shows mass FAILEDs,
suspect the harness first.

### 3. OBSOLETE class (4b56d34ac)

Check verdicts are PASS / FAILED / OBSOLETE. An already-applied patch
(`Reversed (or previously applied)`) is OBSOLETE: it needs a removal decision,
not a repair. Lesson: never repair before ruling out upstream absorption.

### 4. Two-checkout problem (t_813dad9b, t_805ba426)

Two checkouts exist: canonical `/mnt/hdd/repo/proton-ge-custom` vs reference
`~/repo/proton-ge-custom` (new-GE side). Failure lists from one tree do not
apply to the other: R-gst's 13 (`patches/wine-gst/*`) and R-wayland's 0292
don't exist in the canonical tree — ghosts from the other tree, closed without
repair. Lesson: always state which tree a failure count is measured on; home
work is reference-only, never merged into canonical.

### 5. e2 rebase findings (t_a959590c)

All 14 e2-follow MISSING residuals were audited: every one already absorbed or
superseded upstream (upstream commits identified for 12 pending; 4 staging
Werror fixups lost their target). No new patchset needed; audit trail recorded
in series.conf; `--check` green held (90 patchsets / 175 files). Lesson: after
a rebase, audit residuals for upstream absorption before repairing; a fixup
whose target vanished is normal, don't force-revive it.
