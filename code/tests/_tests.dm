// Cross-cutting test code, compiled only under UNIT_TESTS (doc/rewrite/final_api.html, section 22: the generator writes this
// include list; until L lands it is kept by hand). The driver and the recorder come first, then the test-only types and
// capability declarations of code/tests/engine/. The E0 proofs themselves are /datum/unit_test types under
// code/modules/unit_tests/ so the unit-test runner finds them like any other test.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
#include "driver\driver.dm"
#include "driver\recorder.dm"
#include "engine\fixtures.dm"
#endif
