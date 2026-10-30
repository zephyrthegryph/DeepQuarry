#!/bin/bash
# Move candidate checker: which old-tree .dm files can move into the section 22 tree as a pure `git mv`.
#
#   bash tools/ci/move_candidates.sh [--root DIR] [--summary] [--clean|--dirty] [PATH...]
#
# PATHs are files or directories (default: every old-tree file under code/). For each .dm file it prints
#   clean|dirty<TAB>file<TAB>proposed target<TAB>reasons
# A file is dirty when:
#   baseline  a data file in tools/ci/ (baseline, snapshot, golden; not lint_scopes.toml, not scripts) or tools/dm-health/baseline.json
#             names it (a path, or a directory that contains it)
#   toolref   tool source (tools/analyze/src, tools/build, tools/ci scripts) names its path or a directory containing it
#   allow     it has an ALLOW(...) naming a migration lint (init, base_vars, stored_refs, ref_text, native_ref_write, decl); other keeps do not block
#   oldform   it uses Destroy(), spawn, sleep, do_after, INVOKE_ASYNC, Initialize, LateInitialize, Topic, a New() override on an atom type (a plain datum's New() is its
#             constructor, final_api section 6), a verb off /client (the verb set holds client, OOC and admin commands only),
#             flow_ask or CHANGE_ (comments are ignored)
#   systemowner  it defines procs on /datum/system/X and the file declaring SYSTEM_DEF(X) stays in the old tree (system_boundary B3
#             wants the procs in the owner's folder; a move together is fine)
#   defines   it sits under __defines/
# A clean file may still carry a `layering` note: a target in library/ or domains/ that names a type declared under content/
# (engine may not reference library or content; library may not reference content). Layering is a note, never dirty.
# A clean file may also carry a `relinc:<includer>:<line>` note: a relative `#include "../x.dm"` in a .dm file that names it, or
# that sits in it, breaks when either moves; the note names the include line to update in the move's follow-up commit. Never dirty.
# lint_scopes.toml is not a dirty reason: the move's third commit follows the paths there.
#
#   --summary   one line per directory (clean/dirty counts) instead of one per file
#   --root DIR  check the tree under DIR instead of the repository (the self-test fixture)
exec python -I "$(dirname "$0")/move_candidates.py" "$@"
