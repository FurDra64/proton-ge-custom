# OBSOLETE-65 Audit (t_5ff0e2ac)

Gate: `bash scripts/run-check.sh`
(`scripts/pp-check.sh --check`, official WINE sections 2-0..2-7 on a shadow tree).
(The audit originally invoked `~/.hermes/cache/scratch/run-check.sh`, a scratch
wrapper that only did `cd <repo> && bash .dbg-ds5/pp-check.sh --check`; both
scripts are now in-repo under `scripts/`, see `scripts/README.md`.)
Base: proton `sync/wine-submodule` + wine pin `34c16565b9d`.
HEAD at audit: `3e58ed1dc` (parent-task gate: 0 FAILED / 65 OBSOLETE / 692 passed).

Result after this task: **TRUE FAILED 0, OBSOLETE 65 -> 34, passed 692 -> 695.**
(Note: the gate summary line `check FAILED: N failed` counts OBSOLETE rows into N;
true failures are `^FAILED` rows, which are zero.)

## Method

For each of the 65 OBSOLETE rows, reverse-apply was attempted against the exact
gate pre-state of that patch
(`git -C <clean-tree-at-pre-state> apply -R --check -p1 <patch>`), reproduced with
an audit hook in a replay of the official gate (`/mnt/hdd/obsolete-audit/`, outside repo).
- `exit 0` = fully in tree -> drop (`git rm`; empty staging dirs covered by
  `EMPTY_OK_DIRS` in `patches/protonprep-valve-staging.sh` + `.dbg-ds5/pp-check.sh`).
- `exit != 0` = partial/absent -> must NOT drop.

## Key finding: partial-injection load-bearing (do NOT "fix" the remaining 34 naively)

The gate's OBSOLETE path (`git apply` fails -> `patch -Np1` prints
"Reversed (or previously applied)") still **modifies the tree** when `patch`
fuzz/partially applies neighbouring hunks before hitting a Reversed hunk.
Downstream patches are written against that partially-modified tree.

Proven case: `0015-fractional-scaling` (OBSOLETE) vs `0016-Fix-missing-release`.
`0016` needs the 4-arg `NtUserExposeWindowSurface(hwnd, 0, NULL, 0)` context that
only exists via the partial-injection of the skipped `0015`. Dropping `0015`
(and 27 siblings) + retargeting `0126/0173/0193/c0010` produced ~60 TRUE FAILED
(`0016`, `0097`, `0122`, `0198/0199`, `0236`, `0242`, all child-rendering,
em-fixups). Restoring every non-strict file to HEAD returned the gate to
TRUE FAILED 0. Lesson: only **strict** reverse-apply-clean patches (zero tree
modification in the original gate) are safe drops; everything else is
load-bearing until the whole downstream chain is re-ported together.

A first attempt at retargeting the partials (`0193` move of `output_info_array`,
`0126` color-management apply, `c0010`, `0173`, `0099`, `ge-video-0004`,
`ds5-0039/0086/0087`) was **reverted** except for three self-contained,
downstream-clean cases (see RETARGETED below): applied content shifts the
foundation that later patches were written against (e.g. applied `0193` broke
`0242-Remove-output_info_structure`).

## Verdicts (65 rows)

### DROPPED (28) — strict reverse-apply clean, or documented superseded

| patch | verdict |
|---|---|
| wine-wayland/0005-Use-process_name | IN-TREE, dropped |
| wine-wayland/0007-Always-flush-window-surface-in-expose | IN-TREE, dropped |
| wine-wayland/0010-primary-monitor-rect | IN-TREE, dropped |
| wine-wayland/0017-Use-surfaces-for-client-area | IN-TREE, dropped |
| wine-wayland/0018-numpad-vkey | IN-TREE, dropped |
| wine-wayland/0026-RECT-in-wayland_surface_config | IN-TREE, dropped |
| wine-wayland/0033-build-error-older-wl_pointer | IN-TREE, dropped |
| wine-wayland/0077-ntdll-Avoid-infinite-wait | IN-TREE, dropped |
| wine-wayland/0103-GIF-LZW-init | IN-TREE, dropped |
| wine-wayland/0108-64bpp-RGBA-to-32bpp | IN-TREE, dropped |
| wine-wayland/0109-copypixels_to_64bpp-fallback | IN-TREE, dropped |
| wine-wayland/0134-winegstreamer-Don-t-force-x11 | IN-TREE, dropped |
| wine-wayland/0179-IME-cursor-rect-y | IN-TREE, dropped |
| wine-wayland/0187-wined3d-Clear-backup_dc/wnd | IN-TREE, dropped |
| wine-wayland/0208-Ignore-empty-byte-stream-origin | IN-TREE, dropped |
| wine-wayland/0237-Remove-implicit-fullscreen | IN-TREE, dropped |
| wine-wayland/0270-Don-t-return-early-no-monitor-id | IN-TREE, dropped |
| wine-wayland/0288-null-terminated-clipboard-string | IN-TREE, dropped |
| pending/crypt32-wc3-accept-legacy-chain-engine-config | IN-TREE, dropped (explicit apply line commented) |
| pending/crypt32-wc3-modern-chain-engine-config | IN-TREE, dropped (explicit apply line commented) |
| pending/secur32-schannel-fix-incomplete-message | IN-TREE, dropped (explicit apply line commented) |
| pending/ole32-clipboard-stale-handle-2-fix | IN-TREE, dropped (explicit apply line commented) |
| wine-staging/comctl32_animate_avi-cleanup-dead-variable | IN-TREE, dropped (dir now empty, EMPTY_OK_DIRS) |
| wine-staging/windowscodecs-TIFF_Support-Werror-fixup | IN-TREE, dropped (dir now empty, EMPTY_OK_DIRS) |
| proton-ds5-haptic/0030-dont-register-dualsense-mono-pnp | IN-TREE, dropped (glob dir, no harness edit needed) |
| proton-ds5-haptic/0032-dualsense-mono-pnp-skip-at-callsite | IN-TREE, dropped (glob dir) |
| pending/ntdll-prefer-native-version-resource-heuristics | SUPERSEDED by upstream (loadorder `get_version_entry`/vendors[] CompanyName heuristic on newer `pe_mapping_info` API; old `version_res,version_len` premise gone). Dropped, explicit line commented with rationale. |
| game-patches/ace-lsass-samss-service-stub | SUPERSEDED by upstream (wine ships programs/lsass, SamSs ServiceMain, wine.inf SamSsService; proton copy is a stale duplicate with a `--- a/` mail-header quirk). Dropped, explicit line commented. |

### RETARGETED-TO-PASS (3) — kept in tree, formerly OBSOLETE now silently passing

| patch | change |
|---|---|
| proton-ds5-haptic/0086-forget-sony-controller-endpoints | Rebased to current pulse.c (3-split deletion A/B/C around scattered helpers; upstream-shifted contexts). Gate ds5 section clean. |
| pending/icuuc-icuin-forwarder-dlls | Two create-file hunks replaced by modify hunks (`EXTRADLLFLAGS -Wl,-noentry` -> `-Wb,--data-only -Wb,--prefer-native`), preserving proton prefer-native intent vs upstream -noentry. |
| ge-video-rework/0004-quartz-adapt-legacy-video-paths | Ported to current tree: dmowrapper hunks rebased to older `process_output` form (kept `HRESULT process_hr` + 2-arg `get_output_samples`, adopted audio_only/got_output/DISCONTINUITY/S_FALSE semantics); wmadmod extern+factory renamed to 3-arg `winedmo_create_wma_decoder(outer, riid, out)` matching provider `0001`; wmvcore/wmadmod Makefiles `winegstreamer` IMPORTS -> `winedmo` DELAYIMPORTS; already-superseded iyuv_32/vidreszr/memallocator/async-stream_open hunks dropped with per-hunk rationale. |

### RETAINED OBSOLETE (34) — partial/absent, load-bearing, do NOT drop without chain re-port

wine-wayland (31): 0004, 0006, 0009, 0012, 0013, 0014, 0015, 0019, 0021, 0022,
0023, 0024, 0025, 0027, 0028, 0030, 0032, 0034, 0073, 0091, 0096, 0099, 0104,
0106, 0107, 0126, 0173, 0174, 0193, 0207, 0248.
wineland-child-rendering (1): 0010-Respect-xdg-toplevel-configure-bounds.
proton-ds5-haptic (2): 0039-fresh-ids, 0087-drop-unused-disconnect-helper.

Rationale per case: reverse-apply fails (content genuinely missing or drifted);
the original-gate tree at each patch's turn contains partial-injections from
these very files that downstream patches (`0016`, `0031`, `0097`, `0110`,
`0122`, `0198/0199`, `0236`, `0242`, `0291/0293`, child-rendering chain,
em-fixups) depend on. 0022/0013/0012/0030/0091/0015/0021/0025/0104 showed
whitespace-fragile near-zero misses but were restored conservatively after the
cascade experiment proved judgment-drops unsafe (the `0016` 4-arg case: an
added-line grep "miss" was actually satisfied by an evolved upstream variant,
yet the drop still broke the gate — measurement said DROP, gate said KEEP;
gate wins).

## Follow-ups (not this task; assigned to owners)

- ds5 chain `0039/0086/0087`: `0086` now fully applies; `0039`/`0087` remain
  OBSOLETE. A ds5-owner cleanup task should re-port the chain (0061 already
  re-defines `pulse_endpoint_id`/`pulse_device_matches`, mitigating the loss).
- The 34 retained: reducing them further requires re-porting each patch AND its
  downstream chain together (0193+0242, 0126+0198/0199/0291/0293, 0015+0016, ...),
  one chain per task.

## Harness notes (no behavior change to the OBSOLETE branch itself)

- `patches/protonprep-valve-staging.sh` + `.dbg-ds5/pp-check.sh`: 5 explicit
  apply lines commented (ace, crypt32 x2, secur32, ole32, ntdll) with reason +
  absorption SHA where known; `EMPTY_OK_DIRS` extended with the 2 emptied
  staging dirs. `bash -n` clean on both. The OBSOLETE-detection branch itself
  (`git apply` -> `patch -Np1` -> Reversed grep) is untouched per the task ban.
