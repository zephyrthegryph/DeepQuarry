#!/usr/bin/env bash
# Regenerates data/latent_safe_generated.txt (roadmap C10, containment.md §4.7):
# runs the dq_storability_sandbox unit test with GENERATE_LATENT_SAFE defined,
# which writes every candidate /obj/item type the sandbox verified storable
# but that isn't already declared `latent_safe = TRUE` by hand. Review the
# result as a diff before folding entries into
# code/datums/state/latent_safe_types.dm -- this only tells you what *could*
# be marked latent_safe, not that it should be (a type can still be a
# semantic opt-out via latent_unsafe_reason()).
set -euo pipefail
cd "$(dirname "$0")/../.."

FOCUS_FILE="code/modules/unit_tests/dq_focus.dm"
backup="$(mktemp)"
cp "$FOCUS_FILE" "$backup"
restore() { cp "$backup" "$FOCUS_FILE"; rm -f "$backup"; }
trap restore EXIT
echo "TEST_FOCUS(/datum/unit_test/dq_storability_generate)" >> "$FOCUS_FILE"

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) cmd //c "tools\build\build.bat" dm-test -DGENERATE_LATENT_SAFE ;;
	*) tools/build/build.sh dm-test -DGENERATE_LATENT_SAFE ;;
esac

echo "Wrote data/latent_safe_generated.txt"
