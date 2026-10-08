#!/usr/bin/env bash
# Counts the call sites of each legacy form (AGENTS.md section 3b) in code/, excluding unit tests and the files that define the forms (code/engine,
# code/datums/om, code/datums/sys, code/__defines). Prints "form<TAB>sites<TAB>files". doc/rewrite/README.md keeps the last run.
cd "$(dirname "$0")/../.." || exit 1
forms=(om_after om_hook om_ask om_grant OM_EMIT OM_FIELD TOPIC_ACTION DECLARE_PERIODIC_WHILE DECLARE_REPEAT DECLARE_EMAG DAMAGE_REACTION
	DECLARE_INTERACTIONS EXTEND_INTERACTIONS INTERACT_HAND DECLARE_LOOT MAP_RESOLVER APPEARANCE_ topic_ask act_ask rerun_ask
	world_service OWN REL om_changed om_raise_change PERIODIC_ REQ_ CHANGE_ DECLARE_UI DECLARE_VERB)
for f in "${forms[@]}"; do
	case "$f" in
		OWN|REL) re="\b${f}\(" ;;
		*_) re="\b${f}[A-Z0-9_]+" ;;
		*) re="\b${f}\b" ;;
	esac
	out=$(grep -rEn --include='*.dm' "$re" code 2>/dev/null | grep -Ev '^code/(modules/unit_tests|tests|engine|datums/om|datums/sys|__defines)/' | grep -Ev '^[^:]*:[0-9]+:\s*//')
	sites=$(printf '%s' "$out" | grep -c . || true)
	files=$(printf '%s' "$out" | cut -d: -f1 | sort -u | grep -c . || true)
	printf '%s\t%s\t%s\n' "$f" "$sites" "$files"
done
printf 'capabilities()/reactions()/relations() table procs\t%s\t-\n' "$(grep -rEn --include='*.dm' '^/[a-z0-9_/]+/(capabilities|reactions|relations)\(\)' code | grep -Ev '^code/(modules/unit_tests|tests|engine)/' | grep -c .)"
printf 'topic_allowed (hard ban)\t%s\t-\n' "$(grep -rEn --include='*.dm' '\btopic_allowed\b' code | grep -Ev '^code/modules/unit_tests/' | grep -c .)"
