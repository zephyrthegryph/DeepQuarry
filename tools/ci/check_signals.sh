#!/bin/bash
# Kept only as the entry point tools/dm-health/src/suite.rs (owned by Codex) calls;
# do not delete it without repointing that suite first.
# The DCS signal system is deleted (doc/rewrite/object_model_core.md sec 10):
# events are OM events declared as /datum/definition_event types. This check now only
# confirms no signal API is left in code/ (tools/ci/dcs_lints.py does the scan).
set -euo pipefail
cd "$(dirname "$0")/../.."
exec "${PYTHON:-python3}" tools/ci/dcs_lints.py
