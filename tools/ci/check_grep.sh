#!/bin/bash
set -euo pipefail

#nb: must be bash to support shopt globstar
shopt -s globstar extglob

source dependencies.sh

#ANSI Escape Codes for colors to increase contrast of errors
RED="\033[0;31m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

FAILED=0

# check for ripgrep
if command -v rg >/dev/null 2>&1; then
	grep=rg
	pcre2_support=1
	if [ ! rg -P '' >/dev/null 2>&1 ] ; then
		pcre2_support=0
	fi
	code_files=(code/**/**.dm)
	map_files=(maps/**/**.dmm)
	# shuttle_map_files="_maps/shuttles/**.dmm"
	code_x_515=(code/**/!(__byond_version_compat).dm)
else
	# Fallback for machines without ripgrep: GNU grep in Perl-regex mode reads
	# the same patterns. The multiline (PCRE2) checks below still need ripgrep
	# and are skipped here; CI always runs them.
	export LC_ALL=C.UTF-8
	pcre2_support=0
	grep="grep -P"
	code_files=(code/**/**.dm)
	map_files=(maps/**/**.dmm)
	code_x_515=(code/**/!(__byond_version_compat).dm)
fi;

# The file lists are expanded once: re-globbing code/**/**.dm for every rule
# took about 6 s each on Windows, over 4 minutes in total.
echo -e "${BLUE}Using grep provider at $(which ${grep%% *})${NC}"

part=0
section() {
	echo -e "${BLUE}Checking for $1${NC}..."
	part=0
}

part() {
	part=$((part+1))
	padded=$(printf "%02d" $part)
	echo -e "${GREEN} $padded- $1${NC}"
}

section "map issues"

part "TGM"
if grep -El '^\".+\" = \(.+\)' "${map_files[@]}";	then
	echo
	echo -e "${RED}ERROR: Non-TGM formatted map detected. Please convert it using Map Merger!${NC}"
	FAILED=1
fi;

part "iconstate tags"
if grep -P '^\ttag = \"icon' "${map_files[@]}";	then
	echo
	echo -e "${RED}ERROR: tag vars from icon state generation detected in maps, please remove them.${NC}"
	FAILED=1
fi;

part "suspicious symbols in maps"
if grep -P '[<>]' "${map_files[@]}";	then
	echo
	echo -e "${RED}ERROR: potential html code in maps detected.${NC}"
	FAILED=1
fi;

part "step_[xy]"
#Checking for step_x/step_y defined in any maps anywhere.
(! $grep 'step_[xy]' "${map_files[@]}")
retVal=$?
if [ $retVal -ne 0 ]; then
	echo -e "${RED}The variables 'step_x' and 'step_y' are present on a map, and they 'break' movement ingame.${NC}"
	FAILED=1
fi;

part "wrongly offset APCs"
if grep -Pzo '/obj/structure/machinery/power/apc[/\w]*?\{\n[^}]*?pixel_[xy] = -?[013-9]\d*?[^\d]*?\s*?\},?\n' "${map_files[@]}" ||
	grep -Pzo '/obj/structure/machinery/power/apc[/\w]*?\{\n[^}]*?pixel_[xy] = -?\d+?[0-46-9][^\d]*?\s*?\},?\n' "${map_files[@]}" ||
	grep -Pzo '/obj/structure/machinery/power/apc[/\w]*?\{\n[^}]*?pixel_[xy] = -?\d{3,1000}[^\d]*?\s*?\},?\n' "${map_files[@]}" ;	then
	echo -e "${RED}ERROR: found an APC with a manually set pixel_x or pixel_y that is not +-25.${NC}"
	FAILED=1
fi;

part "vareditted areas"
if grep -P '^/area/.+[\{]' "${map_files[@]}";	then
	echo -e "${RED}ERROR: Vareditted /area path use detected in maps, please replace with proper paths.${NC}"
	FAILED=1
fi;

part "base /turf usage"
if grep -P '\W\/turf\s*[,\){]' "${map_files[@]}"; then
	echo
	echo -e "${RED}ERROR: base /turf path use detected in maps, please replace with proper paths.${NC}"
	FAILED=1
fi;

part "test map included"
#Checking for any 'checked' maps that include 'test'
(! $grep 'maps\\.*test.*' *.dme)
retVal=$?
if [ $retVal -ne 0 ]; then
	echo -e "${RED}A map containing the word 'test' is included. This is not allowed to be committed.${NC}"
	FAILED=1
fi;

section "code issues"

part "call_ext outside generated bindings"
# Verdigris is reached only through the generated vg_* procs in
# code/__defines/verdigris/_bindings.dm (tools/build/lib/verdigris_bindings.ts).
# The allowlisted files bind other libraries (rust_g, tracy, the debugger,
# vchatlog, TGS) or define the LIBCALL compat alias.
if $grep -n 'call_ext|load_ext|VERDIGRIS_CALL' "${code_files[@]}" \
	| $grep -v '^code/(__defines/verdigris/_bindings\.dm|__defines/rust_g\.dm|__defines/vchatlog\.dm|__byond_version_compat\.dm|modules/debugging/(tracy|debugger)\.dm|modules/tgs/|modules/benchmarks/scenarios.dm)' \
	| $grep -v ':\s*//|:\s*\*|// .*call_ext'; then
	echo
	echo -e "${RED}ERROR: call_ext/load_ext outside the generated verdigris bindings. Declare the Rust function with #[auxmacros::bind], run tools/build/build.sh verdigris-bindings, and call the generated vg_* proc.${NC}"
	FAILED=1
fi;

part "life scheduler: no Life() overrides"
# /mob/living/Life() is the life scheduler (code/modules/mob/living/life/scheduler.dm). Living
# mobs change their upkeep by adding or overriding /datum/life_system variants, never by
# overriding Life() (doc/mob_life_architecture.md §4).
if $grep -n '^/mob/living[a-zA-Z0-9_/]*/(proc/)?Life\(' "${code_files[@]}" | grep -v '^code/modules/mob/living/life/scheduler\.dm:'; then
	echo
	echo -e "${RED}ERROR: Life() override on a living mob. Add a /datum/life_system (or a variant of one) instead.${NC}"
	FAILED=1
fi;

part "life scheduler: no handle_* life hooks"
# The old Life() hooks became life systems. Their handle_* procs must not come back on mobs,
# species or traits; put the work in a system's tick() (or a variant of the system).
LIFE_HOOKS='addictions|ambience|blood|breath|breathing|changeling|chemical_smoke|chemicals_in_body|confused|darksight|defib_timer|diseases|disabilities|drugged|environment|environment_special|guts|heartbeat|hud_icons_health|hud_list|instability|light|medical_side_effects|modifiers|mutations|nif|npc|organs|pain|paralysed|phobias|post_breath|pulse|radiation|random_events|regular_hud_updates|regular_status_updates|sensory_recovery|shock|silent|sleeping|slurring|special|species_components|statuses|stomach|stunned|stuttering|supernatural|temperature_damage|tf_holder|vision|vr_derez|weakened'
if $grep -n "^/(mob|datum/species|datum/trait)[a-zA-Z0-9_/]*/(proc/)?handle_($LIFE_HOOKS)\(" "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: handle_* Life hook defined outside the life scheduler. Life() steps are /datum/life_system types (code/modules/mob/living/life/).${NC}"
	FAILED=1
fi;

part "gas mixture mirror writes"
# /datum/gas_mixture temperature/volume are READ-ONLY mirrors of the Rust atmos arena
# (the authoritative store). A bare `air.temperature = x` / `air_contents.volume = y`
# (incl. += -= *= /=) updates only the DM mirror, so the arena keeps the old value and
# the change silently vanishes from all gas math. Callers must use set_temperature() /
# set_volume() instead. This guards the common gas-mixture accessor idioms; a refresh of
# the mirror FROM the arena (RHS return_temperature()/return_volume()) is allowed.
if $grep -n '(\bair|air_contents|\bair[0-9]|cabin_air|\benvironment)\.(temperature|volume)[[:space:]]*[-+*/]?=[^=]' "${code_files[@]}" | grep -vE 'return_temperature|return_volume'; then
	echo
	echo -e "${RED}ERROR: direct write to a gas mixture temperature/volume mirror detected. Use set_temperature() / set_volume() — a raw assignment updates only the DM mirror and is ignored by the Rust atmos arena.${NC}"
	FAILED=1
fi;

part "input: modifier ladders"
# Click modifiers (shift, ctrl, alt, middle, right, extra buttons) are read in one
# place: the input router (code/modules/keybindings/router.dm), which turns them
# into abstract actions for every mob (doc/rewrite/interactions.md §4). Branch on
# the action instead. The files listed below predate the router (HUD buttons,
# camera consoles, the admin spawn panel, the secondary item-interaction flag);
# they are grandfathered and must not grow.
input_ladder_allowlist='code/modules/keybindings/router\.dm|code/_onclick/item_attack\.dm|code/_onclick/hud/action/action_screen_objects\.dm|code/game/machinery/computer/(body)?camera\.dm|code/modules/admin/spawn_panel/spawn_panel\.dm|code/modules/mob/living/carbon/human/species/station/protean/protean_powers\.dm'
if $grep -n '\bmodifiers\[\s*"(shift|ctrl|alt|middle|right|left|xbutton1|xbutton2)"|LAZYACCESS\(\s*modifiers\s*,\s*(SHIFT_CLICK|CTRL_CLICK|ALT_CLICK|MIDDLE_CLICK|RIGHT_CLICK|LEFT_CLICK|BUTTON4|BUTTON5)|\bmodifiers\[\s*(SHIFT_CLICK|CTRL_CLICK|ALT_CLICK|MIDDLE_CLICK|RIGHT_CLICK|LEFT_CLICK|BUTTON4|BUTTON5)\s*\]' "${code_files[@]}" | grep -vE "^($input_ladder_allowlist):"; then
	echo
	echo -e "${RED}ERROR: a click modifier check outside the input router. Add a row to a click table in code/modules/keybindings/router.dm and branch on the INPUT_ACTION_* it produces.${NC}"
	FAILED=1
fi;

part "combat mode: a_intent"
# Intents were replaced by combat mode (roadmap I6, doc/rewrite/interactions.md §12).
# Read what a Use does with IS_HELPING/IS_HARMING/IS_DISARMING/IS_GRABBING or
# use_stance(), and set it with set_combat_mode()/set_use_stance(). `a_intent`
# survives only as a read-only mirror (code/modules/mob/combat_mode.dm) for
# files other work owns and has not converted yet: the body rewrite's medical,
# surgery, organ and species files, and the tool *_act procs I4 is migrating.
# These must not grow; delete an entry once its file is converted.
a_intent_allowlist='code/modules/mob/combat_mode\.dm|code/modules/medical/instruments/resuscitation\.dm|code/modules/surgery/surgery\.dm|code/modules/organs/organ\.dm|code/game/objects/items/weapons/surgery_tools\.dm|code/game/objects/items/devices/scanners/health\.dm|code/modules/reagents/reagent_containers/(hypospray|syringes|blood_pack)\.dm|code/modules/mob/living/carbon/human/species/(species|station/teshari|station/station_special_abilities|station/traits/weaver_objs)\.dm|code/game/machinery/doors/(airlock|windowdoor)\.dm|code/game/mecha/mecha\.dm|code/game/objects/items/devices/spy_bug\.dm|code/game/objects/structures/window\.dm|code/modules/maintenance_panels/maintenance_panel\.dm|code/modules/mob/living/silicon/robot/robot\.dm'
if $grep -n '\ba_intent\b' "${code_files[@]}" | grep -vE "^($a_intent_allowlist):"; then
	echo
	echo -e "${RED}ERROR: a_intent is gone. Use combat mode: IS_HARMING(M), IS_HELPING(M), IS_DISARMING(M), IS_GRABBING(M) or M.use_stance() to read it, and set_combat_mode()/set_use_stance() to set it (code/__defines/combat_mode.dm).${NC}"
	FAILED=1
fi;

part "robot cell writes outside the power ledger"
# A robot's cell charge is written only by draw_power()/add_power() in robot.dm, so the
# ledger (used_power_this_tick, part power states) sees every joule. Robot code under
# code/modules/mob/living/silicon/robot must not touch the cell directly.
if grep -RInE --include='*.dm' '\bcell\.(charge[[:space:]]*[-+*/]?=[^=]|use\(|give\(|checked_use\()' code/modules/mob/living/silicon/robot | grep -vE '/robot/robot\.dm:'; then
	echo
	echo -e "${RED}ERROR: direct robot cell write detected. Use draw_power() / add_power() with ROBOT_CELL_JOULES().${NC}"
	FAILED=1
fi;

part "body factors: no chemical effects"
# Reagent effects are body factors (`factors` on the reagent, read with
# L.factor(BF_*)); the per-tick chem_effects channels are gone.
if $grep -n '\b(add_chemical_effect|remove_chemical_effect|chem_effects)\b' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: chem_effects / add_chemical_effect detected. Declare body factors on the reagent (factors = alist(BF_X = value)) and read them with factor(BF_X).${NC}"
	FAILED=1
fi;

part "body factors: no mechanical effects"
# Affliction effects are body factors (`factors`, or a stage's "factors").
if $grep -n '\b(mechanical_effects|vital_effects|od_boost|get_vital_effects)\b' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: mechanical_effects / vital_effects / od_boost detected. Declare body factors on the affliction (factors = alist(BF_X = value)).${NC}"
	FAILED=1
fi;

part "body factors: no modifier numeric fields"
# Every numeric modifier effect is a body factor in the modifier's `factors`.
if $grep -n '\b(endurance_flat|endurance_percent|disable_duration_percent|incoming_[a-z]+_percent|outgoing_melee_damage_percent|bleeding_rate_percent|metabolism_percent|icon_scale_[xy]_percent|attack_speed_percent|accuracy_dispersion|pain_immunity|pulse_modifier|pulse_set_level|emp_modifier|explosion_modifier|[a-z]+_injury_resistance|[a-z]+_physical_resistance|[a-z]+_thermal_resistance)\b' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: a removed /datum/modifier numeric field is referenced. Declare it in the modifier's factors table and read factor(BF_X).${NC}"
	FAILED=1
fi;
if $grep -n '\b(M|mod|modifier)\.(slowdown|haste|evasion|accuracy|siemens_coefficient|heat_protection|cold_protection|vision_flags|armor_percent)\b' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: a modifier's slowdown/evasion/accuracy/... is read directly. Those are body factors: read factor(BF_X) on the holder.${NC}"
	FAILED=1
fi;

part "weapon vocabulary: injury kinds, not damage types"
# Weapons, projectiles, blobs, unarmed and animal attacks declare what they
# inflict as INJURY_* kinds (`injury_kind`, or an `injury_kinds` alist for a
# mixed hit). Object damage is derived with injury_kind_obj_damage_type().
if $grep -n '(\.damtype\b|\bvar/damtype\b|^\s*damtype\s*=|\binjury_kind_for\b|\bget_injury_kind\b|\binjure_by_damtype\b|\bpunch_damtype\b|\bcheck_armour\b|\battack_(sharp|edge)\b)' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: a legacy damage type (damtype / injury_kind_for / check_armour / attack_sharp...) detected. Declare injury_kind = INJURY_X (or injury_kinds) and derive object damage with injury_kind_obj_damage_type().${NC}"
	FAILED=1
fi;
if $grep -n '^\s*(var/)?damage_type\s*=\s*(BRUTE|BURN)\b' "${code_files[@]}" | $grep -v '^code/modules/medical/conditions/wounds\.dm:'; then
	echo
	echo -e "${RED}ERROR: damage_type = BRUTE/BURN on a mob-harming type. Declare injury_kind = INJURY_X; obj_integrity damage is derived from it.${NC}"
	FAILED=1
fi;
if $grep -n '(#define\s+(TOX|OXY|CLONE|HALLOSS)\b|\b(HALLOSS|ELECTROCUTE|BIOACID|SEARING|ELECTROMAG)\b)' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: a removed damage-type define (TOX/OXY/CLONE/HALLOSS/ELECTROCUTE/BIOACID/SEARING/ELECTROMAG) detected. Use INJURY_* kinds.${NC}"
	FAILED=1
fi;

part "one mitigation pipeline"
# Armour, shields, resistance factors and species multipliers apply inside
# injure() (pass INJURE_ARMORED for hits from outside). The old parallel
# armour procs are gone; ask armour with injury_armor(kind, zone).
if $grep -n '\b(run_armor_check|getarmor|getarmor_organ|mitigate_injury|factor_armor|get_injury_mod|injury_mod_groups)\b' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: a parallel mitigation path detected. Harm goes through injure(); armour is injury_armor(kind, zone); species resistances are factor_baseline BF_INCOMING_*.${NC}"
	FAILED=1
fi;

part "medical condition severity writes"
# Condition severity is observable contract state. All writes, including
# pre-attachment initialization, go through set_severity()/adjust_severity()
# so a later refactor cannot silently bypass eligibility invalidation.
if grep -RInE --include='*.dm' '\.severity[[:space:]]*[-+*/]?=[^=]' code/modules/medical code/modules/contracts; then
	echo
	echo -e "${RED}ERROR: direct medical-condition severity write detected. Use set_severity() or adjust_severity() so condition-dependent systems receive invalidation signals.${NC}"
	FAILED=1
fi;

part "organ damage outside the body"
# Organ and limb integrity belong to the body (doc/body_architecture.md): harm
# goes through injure(kind, amount, organ) and healing through
# mend(tag, amount, organ). Outside code/modules/body and code/modules/organs,
# no take_damage()/heal_damage() on organs, no organ `.damage` writes, no
# LESION_HEAL_* modes and no calls to the body-internal integrity procs.
if grep -RInE --include='*.dm' '\b(organ|internal_organ|external_organ|our_organ|affecting|affected|bodypart|brain|my_brain|heart|ht|liver|lungs|kidneys|eyes|stomach|st|limb|[a-z_]*_organ)\??\.(take_damage|heal_damage|damage[[:space:]]*([-+*/]?=[^=]|\+\+|--))|(take_damage|heal_damage)\(.*(LESION_HEAL|/datum/affliction/lesion)|internal_organs_by_name\[[^]]*\]\??\.(take_damage|heal_damage)\(|\.(apply_lesion_damage|apply_wound_damage|restore_lesions|heal_wound_damage)\(|LESION_HEAL_' code | grep -vE '^code/modules/(body|organs)/'; then
	echo
	echo -e "${RED}ERROR: organ or limb damage/healing outside the body detected. Use injure(kind, amount, organ) to harm and mend(tag, amount, organ) to heal.${NC}"
	FAILED=1
fi;

part "contract-only physical types"
# Contracts may observe or extend ordinary world objects, but must not define
# dedicated items, machines, mobs, turfs, or areas. Physical play goes through
# existing paper, fax, scanner, chemistry, Cargo, PDA, and console systems.
if grep -RHnE --include='*.dm' '^/(obj|mob|turf|area)/' code/modules/contracts |
	grep -vE ':(/obj/item/paper/(proc/attach_contract_evidence|on_signature|on_field_written)|/mob/living/carbon/human(/proc/(refresh_contract_medical_eligibility|record_clinical_exposure|clinical_exposure_printout|medical_trial_marker_snapshot))?)($|\()'; then
	echo
	echo -e "${RED}ERROR: contract-only physical type detected. Store contract identity in generic evidence/components/reagent provenance and use an existing world object.${NC}"
	FAILED=1
fi;

part "space indentation"
if grep -P '(^ {2})|(^ [^ * ])|(^    +)' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: space indentation detected.${NC}"
	FAILED=1
fi;

part "mixed tab/space indentation"
if grep -P '^\t+ [^ *]' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: mixed <tab><space> indentation detected.${NC}"
	FAILED=1
fi;

part "improperly pathed static lists"
if $grep -i 'var/list/static/.*' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: Found incorrect static list definition 'var/list/static/', it should be 'var/static/list/' instead.${NC}"
	FAILED=1
fi;

part "changelog"
#Checking for a change to html/changelogs/example.yml
md5sum -c - <<< "0c56937110d88f750a32d9075ddaab8b *html/changelogs/example.yml"
retVal=$?
if [ $retVal -ne 0 ]; then
	echo -e "${RED}Do not modify the example.yml changelog file.${NC}"
	FAILED=1
fi;

part "color macros"
#Checking for color macros
(num=`{ $grep -n '\\\\(red|blue|green|black|b|i[^mnct])' "${code_files[@]}" || true; } | wc -l`; echo "$num escapes (expecting ${MACRO_COUNT} or less)"; [ $num -le ${MACRO_COUNT} ])
retVal=$?
if [ $retVal -ne 0 ]; then
	echo -e "${RED}Do not use any byond color macros (such as \blue), they are deprecated.${NC}"
	FAILED=1
fi;

part "typescript react files"
if ls -1 tgui/**/*.jsx 2>/dev/null; then
	echo
	echo -e "${RED}ERROR: JSX file(s) detected, these must be converted to typescript (TSX).${NC}"
	FAILED=1
fi;

part "balloon_alert sanity"
if $grep 'balloon_alert\(".*"' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: Found a balloon alert with improper arguments.${NC}"
	FAILED=1
fi;

part "balloon_alert span check"
if $grep 'balloon_alert\(.*[Ss][Pp][Aa][Nn]' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: Balloon alerts should never contain spans.${NC}"
	FAILED=1
fi;

part "balloon_alert idiomatic usage"
if $grep 'balloon_alert\(.*?,\s*"[\sA-Z]' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: Balloon alerts should not start with capital letters or whitespace. This includes text like 'AI'. If this is a false positive, wrap the text in UNLINT().${NC}"
	FAILED=1
fi;

part ".proc ref syntax"
if $grep '\.proc/' "${code_x_515[@]}" ; then
	echo
	echo -e "${RED}ERROR: Outdated proc reference use detected in code, please use proc reference helpers.${NC}"
	FAILED=1
fi;

part "ambiguous bitwise or"
if grep -P '^(?:[^\/\n]|\/[^\/\n])*(&[ \t]*\w+[ \t]*\|[ \t]*\w+)' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: Likely operator order mistake with bitwise OR. Use parentheses to specify intention.${NC}"
	FAILED=1
fi;

part "html tag matching"
#Checking for missed tags
python tools/TagMatcher/tag-matcher.py code
retVal=$?
if [ $retVal -ne 0 ]; then
	echo -e "${RED}Some HTML tags are missing their opening/closing partners. Please correct this.${NC}"
	FAILED=1
fi;

part "proc ref syntax"
if $grep '\.proc/' "${code_x_515[@]}" ; then
    echo
    echo -e "${RED}ERROR: Outdated proc reference use detected in code, please use proc reference helpers.${NC}"
    FAILED=1
fi;

part "var in proc args"
if grep -P '^/[\w/]\S+\(.*(var/|, ?var/.*).*\)' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: changed files contains proc argument starting with 'var'.${NC}"
	FAILED=1
fi;

part "unmanaged global vars"
if grep -P '^/*var/' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: Unmanaged global var use detected in code, please use the helpers.${NC}"
	FAILED=1
fi;

part "ambiguous bitwise or"
if grep -P '^(?:[^\/\n]|\/[^\/\n])*(&[ \t]*\w+[ \t]*\|[ \t]*\w+)' "${code_files[@]}"; then
	echo
	echo -e "${RED}ERROR: Likely operator order mistake with bitwise OR. Use parentheses to specify intention.${NC}"
	FAILED=1
fi;

if [ "$pcre2_support" -eq 1 ]; then
	section "regexes requiring PCRE2"

    part "deoptimization of range/view with as anything"
	if $grep -PU 'var\/(?!atom).* as anything in o?(range|view)\(' "${code_files[@]}"; then
		echo
		echo -e "${RED}ERROR: range(), orange(), view(), and oview() perform significantly worse with as anything.${NC}"
		FAILED=1
	fi;

	part "empty variable values"
	if $grep -PU '{\n\t},' "${map_files[@]}"; then
		echo
		echo -e "${RED}ERROR: Empty variable value list detected in map file. Please remove the curly brackets entirely.${NC}"
		FAILED=1
	fi;

	part "to_chat sanity"
	if $grep -P 'to_chat\((?!.*,).*\)' "${code_files[@]}"; then
		echo
		echo -e "${RED}ERROR: to_chat() missing arguments.${NC}"
		FAILED=1
	fi;

	part "timer flag sanity"
	if $grep -P 'addtimer\((?=.*TIMER_OVERRIDE)(?!.*TIMER_UNIQUE).*\)' "${code_files[@]}"; then
		echo
		echo -e "${RED}ERROR: TIMER_OVERRIDE used without TIMER_UNIQUE.${NC}"
		FAILED=1
	fi;

	part "trailing newlines"
	if $grep -PU '[^\n]$(?!\n)' "${code_files[@]}"; then
		echo
		echo -e "${RED}ERROR: File(s) with no trailing newline detected, please add one.${NC}"
		FAILED=1
	fi;

	part "improper atom initialize args"
	if $grep -P '^/(obj|mob|turf|area|atom)/.+/Initialize\((?!mapload).*\)' "${code_files[@]}"; then
		echo
		echo -e "${RED}ERROR: Initialize override without 'mapload' argument.${NC}"
		FAILED=1
	fi;

	part "improper atom New usage"
	(num=`$grep -n '^/?(obj|mob|turf|area|atom)/?.*/New\(' "${code_files[@]}" | wc -l`; echo "$num New (expecting 2 or less)"; [ $num -le 2 ])
	retVal=$?
	if [ $retVal -ne 0 ]; then
		echo -e "${RED}Do not use any New() calls, they've been replaced by Initialize(mapload).${NC}"
		FAILED=1
	fi;

	part "legacy machinery structural damage overrides"
	if $grep -Pn '^/obj/machinery[^\n]*/(take_damage|fall_apart)\(' "${code_files[@]}"; then
		echo
		echo -e "${RED}ERROR: machinery must use obj_integrity and atom_break/atom_fix/atom_destruction; private take_damage/fall_apart handlers are forbidden.${NC}"
		FAILED=1
	fi;

	part "legacy machinery common-tool dispatch"
	# Common tools are dispatched by item_interaction() into focused *_act hooks.
	# attackby() remains valid for ordinary items, but must not rediscover tool
	# qualities or invoke the old deconstruction dispatcher helpers.
	if $grep -PUn '(?m)^/obj/machinery[^\n]*/attackby\([^\n]*\)\n(?:(?!^/)[\s\S])*?(?:has_tool_quality\(TOOL_|istype\([^\n]*?/obj/item/multitool|default_(?:deconstruction_screwdriver|deconstruction_crowbar|unfasten_wrench)\(|computer_deconstruction_screwdriver\(|alarm_deconstruction_(?:screwdriver|wirecutters)\()' code --glob '*.dm'; then
		echo
		echo -e "${RED}ERROR: machinery attackby() must not dispatch common tools or legacy deconstruction helpers; use focused *_act hooks/declarative maintenance.${NC}"
		FAILED=1
	fi;
	if $grep -Pn '\b(default_deconstruction_screwdriver|default_deconstruction_crowbar|default_unfasten_wrench|computer_deconstruction_screwdriver|alarm_deconstruction_screwdriver|alarm_deconstruction_wirecutters)\s*\(' "${code_files[@]}"; then
		echo
		echo -e "${RED}ERROR: removed machinery maintenance helpers must not return; use declarative maintenance flags and focused tool hooks.${NC}"
		FAILED=1
	fi;
	# The volatile abductor RTG's asplod lifecycle is the sole allowlisted scenario
	# device: its ex_act continues an already-running detonation rather than applying
	# structural damage. Ordinary machinery must never delete itself from damage handlers.
	if $grep -PUn '^/obj/machinery[^\n]*/(?:ex_act|bullet_act)\([^\n]*\)\n(?:(?:\t.*|\s*)\n?){0,24}?\t*qdel\(src\)' code --glob '*.dm' --glob '!code/modules/power/port_gen.dm'; then
		echo
		echo -e "${RED}ERROR: machinery structural damage handlers must route through obj_integrity, not qdel(src).${NC}"
		FAILED=1
	fi;
	if $grep -PUn '^/obj/machinery[^\n]*/ex_act\([^\n]*\)\n(?:(?:\t.*|\s*)\n?){0,24}?\t*take_damage\(' code --glob '*.dm' --glob '!code/game/machinery/machinery.dm'; then
		echo
		echo -e "${RED}ERROR: subtype ex_act must preserve orthogonal effects and chain to generic machinery explosion damage.${NC}"
		FAILED=1
	fi;

	part "tag"
	#Checking for 'tag' set to something on maps
	(! $grep -Pn '( |\t|;|{)tag( ?)=' "${map_files[@]}")
	retVal=$?
	if [ $retVal -ne 0 ]; then
		echo -e "${RED}A map has 'tag' set on an atom. It may cause problems and should be removed.${NC}"
		FAILED=1
	fi;

	(! $grep -Pn '( |\t|;|{)tag( ?)=' "${map_files[@]}")
	retVal=$?
	if [ $retVal -ne 0 ]; then
		echo -e "${RED}A map has 'tag' set on an atom. It may cause problems and should be removed.${NC}"
		FAILED=1
	fi

	part "broken html"
	# echo -e "${RED}DISABLED"
	#Checking for broken HTML tags (didn't close the quote for class)
	(! $grep -Pn "<\s*span\s+class\s*=\s*('[^'>]+|[^'>]+')\s*>" "${code_files[@]}")
	retVal=$?
	if [ $retVal -ne 0 ]; then
		echo -e "${RED}A broken span tag class is present (check quotes).${NC}"
		FAILED=1
	fi;

	part "old style hrefs"
	(! $grep -Pn "href[\s='\"\\ ]*\?" "${code_files[@]}")
	retVal=$?
	if [ $retVal -ne 0 ]; then
		echo -e "${RED}old-style hrefs detected, see ripgrep output.${NC}"
		FAILED=1
	fi;
else
	echo -e "${RED}pcre2 not supported, skipping checks requiring pcre2"
	echo -e "if you want to run these checks install ripgrep with pcre2 support.${NC}"
fi;

if [ $FAILED = 0 ]; then
	echo
	echo -e "${GREEN}No errors found using $grep!${NC}"
else
	echo
	echo -e "${RED}Errors found, please fix them and try again.${NC}"
fi;

# Quit with our status code
exit $FAILED
