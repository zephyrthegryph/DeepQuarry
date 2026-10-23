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
#   allow     it has an ALLOW(...) annotation
#   oldform   it uses Destroy(), spawn, sleep, do_after, INVOKE_ASYNC, Initialize, LateInitialize, Topic, a New() override, /verb/,
#             flow_ask / prompt_flow or CHANGE_ (comments are ignored)
#   defines   it sits under __defines/
# A clean file may still carry a `layering` note: a target in library/ or domains/ that names a type declared under content/
# (engine may not reference library or content; library may not reference content). Layering is a note, never dirty.
# lint_scopes.toml is not a dirty reason: the move's third commit follows the paths there.
#
#   --summary   one line per directory (clean/dirty counts) instead of one per file
#   --root DIR  check the tree under DIR instead of the repository (the self-test fixture)
exec python -I "$(dirname "$0")/move_candidates.py" "$@"
