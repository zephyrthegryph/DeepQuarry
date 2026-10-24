#!/bin/bash
# The Verdigris bindings are generated build output (not committed), so there is nothing to be stale:
# this writes them (kept under the old name for tools/dm-health's suite) and fails only if generation fails.
exec bash "$(dirname "$0")/gen_verdigris_bindings.sh"
