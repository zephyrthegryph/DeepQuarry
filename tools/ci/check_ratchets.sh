#!/usr/bin/env bash
# Ratcheted rewrite lints (doc/rewrite/roadmap.md, Guardrails). Each fails on a site
# not held in its fingerprint baseline (tools/ci/*_baseline.txt, printed as file:line); a justified keep is an inline
# `// ALLOW(<lint>): <reason>` (tools/ci/allow_annotations.py). Runs every lint, then reports.
# doc/rewrite/object_model_core.md sec 16 ("One way to do X") maps each banned
# alternative to the lint here that counts it.
set -uo pipefail
cd "$(dirname "$0")/../.."
PY="${PYTHON:-python3}"
failed=()
# Fixture selftests first: a lint whose own fixtures fail can't be trusted to ratchet.
for lint in ui_actions_lint.py sys_lint.py cap_bits_lint.py doc_snippets.py; do
	if ! "$PY" "tools/ci/$lint" --selftest; then
		failed+=("$lint --selftest")
	fi
done
for lint in \
	allow_annotations.py \
	scheduler_lints.py \
	ownership_lint.py \
	lifecycle_counts_lint.py \
	lifecycle_lint.py \
	containment_lint.py \
	latent_lint.py \
	spatial_lint.py \
	pollers_lint.py \
	registry_lint.py \
	instance_list_lint.py \
	state_schema_lint.py \
	check_deadline_polling.py \
	actor_forwarding_lint.py \
	breakpoint_lint.py \
	api_lints.py \
	cooldown_lint.py \
	i7_handler_lint.py \
	dcs_lints.py \
	leftovers_lints.py \
	silent_catch_lint.py \
	subsystem_fire_lint.py \
	interactions_lint.py \
	om_internal_lint.py \
	init_lint.py \
	decl_lint.py \
	organ_slots_lint.py \
	cache_lint.py \
	stance_examine_lint.py \
	ui_actions_lint.py \
	sys_lint.py \
	tracked_lint.py \
	derived_reads_lint.py \n	cap_bits_lint.py \n	system_boundary_lint.py \n	doc_snippets.py; do
	echo "::group::$lint"
	if ! "$PY" "tools/ci/$lint"; then
		failed+=("$lint")
	fi
	echo "::endgroup::"
done
echo "::group::tracked_lint.py --selftest"
if ! "$PY" tools/ci/tracked_lint.py --selftest; then
	failed+=("tracked_lint.py --selftest")
fi
echo "::endgroup::"
echo "::group::derived_reads_lint.py --selftest"
if ! "$PY" tools/ci/derived_reads_lint.py --selftest; then
	failed+=("derived_reads_lint.py --selftest")
fi
echo "::endgroup::"
if [ ${#failed[@]} -gt 0 ]; then
	echo "Ratchet lints failed: ${failed[*]}"
	exit 1
fi
echo "All ratchet lints passed."
