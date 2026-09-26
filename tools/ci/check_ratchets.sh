#!/usr/bin/env bash
# Ratcheted rewrite lints (doc/rewrite/roadmap.md, Guardrails). Each fails when a
# count rises above its ceiling or allowlist. Runs every lint, then reports.
set -uo pipefail
cd "$(dirname "$0")/../.."
PY="${PYTHON:-python3}"
failed=()
for lint in \
	scheduler_lints.py \
	declared_refs_lint.py \
	lifecycle_counts_lint.py \
	lifecycle_lint.py \
	containment_lint.py \
	latent_lint.py \
	registry_lint.py \
	instance_list_lint.py \
	state_schema_lint.py \
	check_deadline_polling.py \
	actor_forwarding_lint.py \
	breakpoint_lint.py; do
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
