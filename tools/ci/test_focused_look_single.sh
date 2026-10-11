#!/usr/bin/env bash
set -euo pipefail
runner="${1:-$(git rev-parse --show-toplevel)/tools/dq_focused_test.sh}"
runner="$(cd "$(dirname "$runner")" && pwd)/$(basename "$runner")"
decision="$(sed -n '/^look_world=0$/,/^LOOK_PARAMS=/p' "$runner")"
check_mode() {
 local split_mode="$1" DQ_FOCUS_SPLIT="$2" bless="$3" repeat="$4" expected="$5"
 local look_group=(dq_look_state_pin dq_look_tree_pin) do_split=0 look_world=0 look_single=0 LOOK_PARAMS
 eval "$decision"
 test "$look_world:$look_single:$do_split" = "$expected"
}
check_mode auto 0 0 1 1:1:0
check_mode off '' 0 1 1:1:0
check_mode auto '' 0 1 1:0:1
check_mode off 0 1 1 0:0:0
check_mode off 0 0 2 0:0:0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tools/build"
cat > "$work/tools/build/build.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "params=$DQ_WORLD_PARAMS" "args=$*"
STUB
chmod +x "$work/tools/build/build.sh"
run_fn="$(awk '/^run_once\(\) \{/ { copying=1 } copying { print } copying && /^}$/ { exit }' "$runner")"
cd "$work"
eval "$run_fn"
look_single=1
LOOK_PARAMS='look-plan=data/look-plan.tsv&look-types=data/look-types.txt'
DQ_WORLD_PARAMS='user-param=kept'
focus='dq_real_test,dq_look_state_pin,dq_look_tree_pin'
args=()
result="$(run_once)"
[[ "$result" == *'params=user-param=kept&look-plan=data/look-plan.tsv&look-types=data/look-types.txt'* ]]
[[ "$result" == *'--focus=dq_real_test,dq_look_state_pin,dq_look_tree_pin'* ]]
test "$DQ_WORLD_PARAMS" = 'user-param=kept'
printf '%s\n' 'focused serialized incremental look shell regression: PASS'
