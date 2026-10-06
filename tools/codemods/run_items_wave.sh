#!/usr/bin/env bash
# The items/structures wave: every codemod over the four folders, in order. Idempotent: a converted site no longer
# matches. Types a codemod must leave are in tools/codemods/exclusions.txt. Afterwards: tools/build/build.sh dm,
# bash tools/ci/check_ratchets.sh, bash tools/dq_focused_test.sh dq_conversion_pin.
#
#   bash tools/codemods/run_items_wave.sh [--check]
set -euo pipefail
cd "$(dirname "$0")/../.."
dirs=(code/game/objects/items code/game/objects/structures code/game/objects/effects code/game/objects code/game/turfs)
check=()
[ "${1:-}" = "--check" ] && check=(--check)
python tools/codemods/tool_act.py "${check[@]}" --dirs "${dirs[@]}" | grep -vE 'test caller|^        '
python tools/codemods/interaction_datums.py "${check[@]}" --dirs "${dirs[@]}" | grep -vE '^        '
python tools/dx/codemods/interact_declare.py "${check[@]}" --dirs "${dirs[@]}" | grep -vE '^        '
python tools/codemods/damage_reaction.py "${check[@]}" --dirs "${dirs[@]}" | grep -vE '^        '
