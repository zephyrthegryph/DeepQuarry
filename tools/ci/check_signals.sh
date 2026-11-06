#!/bin/bash
# Kept as the entry point tools/dm-health/src/suite.rs (owned by Codex) calls.
# The DCS signal system is deleted: events are notices (/datum/notice). This confirms no signal API is
# left in code/ (comment lines are ignored). tools/ci/dcs_lints.py, which this used to run, no longer exists.
set -euo pipefail
cd "$(dirname "$0")/../.."
hits="$(grep -rnE --include='*.dm' '\b(RegisterSignal|UnregisterSignal|SEND_SIGNAL|SEND_GLOBAL_SIGNAL|COMSIG_[A-Z_]+)\b' code | grep -vE ':[0-9]+:[[:space:]]*//' || true)"
if [ -n "$hits" ]; then
	echo "signal API still used in code/:" >&2
	echo "$hits" >&2
	exit 1
fi
echo "check_signals: no signal API in code/"
