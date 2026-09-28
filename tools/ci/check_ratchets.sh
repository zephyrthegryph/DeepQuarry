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
for lint in \
	allow_annotations.py \
	scheduler_lints.py \
	declared_refs_lint.py \
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
	ownership_cycle_lint.py \
	handle_kinds_lint.py \
	subsystem_fire_lint.py \
	interactions_lint.py \
	om_internal_lint.py \
	init_lint.py \n	organ_slots_lint.py; do
	echo "::group::$lint"
	if ! "$PY" "tools/ci/$lint"; then
		failed+=("$lint")
	fi
	echo "::endgroup::"
done
if [ ${#failed[@]} -gt 0 ]; then
	echo "Ratchet lints failed: ${failed[*]}"
	exit 1
fi
echo "All ratchet lints passed."
