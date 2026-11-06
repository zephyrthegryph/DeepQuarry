#!/bin/bash
# Move candidate checker: which old-tree .dm files can move into the section 22 tree as a pure `git mv`.
#
#   bash tools/ci/move_candidates.sh [--root DIR] [--summary] [--clean|--dirty] [PATH...]
#
# PATHs are files or directories (default: every old-tree file under code/). For each .dm file it prints
#   clean|dirty<TAB>file<TAB>proposed target<TAB>reasons
# A file is dirty when:
#   baseline  a data file in tools/ci/ (baseline, snapshot, golden; not lint_scopes.toml, not scripts) names it (a path, or a directory
#             that contains it)
#   allow     it has an ALLOW(...) naming a migration lint (init, base_vars, stored_refs, ref_text, native_ref_write, decl); other keeps do not block
#   oldform   it uses Destroy(), spawn, sleep, do_after, INVOKE_ASYNC, Initialize, LateInitialize, Topic, a New() override on an atom type (a plain datum's New() is its
#             constructor, final_api section 6), a verb off /client (the verb set holds client, OOC and admin commands only),
#             flow_ask or CHANGE_ (comments are ignored)
#   systemowner  it defines procs on /datum/system/X and the file declaring SYSTEM_DEF(X) stays in the old tree (system_boundary B3
#             wants the procs in the owner's folder; a move together is fine)
#   defines   it sits under __defines/
# A clean file may still carry a `layering` note: a target in library/ or domains/ that names a type declared under content/
# (engine may not reference library or content; library may not reference content). Layering is a note, never dirty.
# A clean file may also carry `dmhealth:<ref>` (a tools/dm-health/baseline.json row names it) and `toolref:<ref>` (tool source under
# tools/analyze/src, tools/build or a tools/ci script names its path or a directory containing it) notes. Neither holds a file back:
# the move's follow-up commit rewrites the path mechanically in the baseline row or the tool source (a dm-health row is a quality
# finding, not an old form; a tool that keys on a directory needs the new directory added or the file kept where the tool expects it).
# A clean file may also carry a `relinc:<includer>:<line>` note: a relative `#include "../x.dm"` in a .dm file that names it, or
# that sits in it, breaks when either moves; the note names the include line to update in the move's follow-up commit. Never dirty.
# lint_scopes.toml is not a dirty reason: the move's third commit follows the paths there.
#
#   --summary   one line per directory (clean/dirty counts) instead of one per file
#   --root DIR  check the tree under DIR instead of the repository (the self-test fixture)
# python is a Windows binary under Git Bash: hand it a native path even where MSYS path conversion is off (the merge gates).
here="$(cd "$(dirname "$0")" && pwd)"
if command -v cygpath >/dev/null 2>&1; then here="$(cygpath -m "$here")"; fi
exec python -I "$here/move_candidates.py" "$@"
