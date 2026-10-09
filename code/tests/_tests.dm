// Cross-cutting test code, compiled only under UNIT_TESTS (doc/rewrite/final_api.html, section 22: the generator writes this
// include list; until L lands it is kept by hand). The driver and the recorder come first, then the test-only types and
// capability declarations of code/tests/engine/. The E0 proofs themselves are /datum/unit_test types under
// code/modules/unit_tests/ so the unit-test runner finds them like any other test.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
#include "driver\driver.dm"
#include "driver\recorder.dm"
#include "driver\kernel_clock.dm"
#include "engine\fixtures.dm"
#include "engine\e1_fixtures.dm"
#include "engine\e3_fixtures.dm"
#include "engine\e4_fixtures.dm"
#include "engine\veto_fixtures.dm"
#include "engine\e2_fixtures.dm"
#include "engine\e2_bench_fixtures.dm"
#include "library\fixtures.dm"
#include "engine\p1_fixtures.dm"
#include "engine\p2_fixtures.dm"
#include "engine\s1_fixtures.dm"
#include "engine\p2_storage_fixtures.dm"
#include "engine\gap_fixtures.dm"
#include "engine\proximity_fixtures.dm"
#include "engine\eg2_wait_fixtures.dm"
#include "engine\timed_forms_fixtures.dm"
#include "engine\prompt_fixtures.dm"
#include "engine\eg2_fixtures.dm"
#include "domains\heat_fixtures.dm"
#include "engine\req_protocol_fixtures.dm"
#endif
