#!/usr/bin/env bash
# A native compile that exits 75 "admission deadline expired" re-queues until DQ_NATIVE_ADMISSION_MAX_MIN instead of failing.
set -euo pipefail
cd "$(dirname "$0")/../.."
exec bun test tools/build/lib/admission_retry.test.ts
