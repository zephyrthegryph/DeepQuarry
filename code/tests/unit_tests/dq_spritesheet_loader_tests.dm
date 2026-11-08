// A deferred sprite sheet whose build fails in the asset loading service still ends its generation: the service's count of sheets in flight comes
// back down and the sheet leaves the queue, so the wait for deferred assets (a bench's, a test's) does not stall on it
// (code/library/ui/asset_cache/iconforge/batched_spritesheet.dm, realize_failed()).

/// A sheet whose create_spritesheets() throws while `fail` is set. Abstract, so the asset system never builds it at boot; the test makes it.
/datum/asset/spritesheet_batched/dq_failing_build
	_abstract = /datum/asset/spritesheet_batched/dq_failing_build
	name = "dq_failing_build"
	var/static/fail = FALSE

/datum/asset/spritesheet_batched/dq_failing_build/create_spritesheets()
	if(fail)
		CRASH("planned failure of a test sheet's build")
	insert_icon("ok", uni_icon('icons/mob/actions.dmi', "default", SOUTH))

/datum/unit_test/dq_spritesheet_failed_build_releases_loader
/datum/unit_test/dq_spritesheet_failed_build_releases_loader/Run()
	var/list/caught = list()
	set_global(nameof(GLOB.dq_caught_capture), caught)
	var/before = SSasset_loading.assets_generating
	var/datum/asset/spritesheet_batched/dq_failing_build/sheet = new
	TEST_ASSERT(sheet in SSasset_loading.generate_queue, "a deferred sheet is queued at register()")
	sheet.fail = TRUE
	sheet.queued_generation() // what the service's generate step does with it
	TEST_ASSERT_EQUAL(SSasset_loading.assets_generating, before, "the failed build released the count of sheets in flight")
	TEST_ASSERT(!sheet.queued_generation_active, "the sheet's generation ended")
	TEST_ASSERT(!(sheet in SSasset_loading.generate_queue), "and it left the queue")
	TEST_ASSERT(!sheet.fully_generated, "the sheet was not built")
	TEST_ASSERT_EQUAL(length(caught), 1, "the fault was reported once")
	// Once its build works, asking for the sheet builds it.
	sheet.fail = FALSE
	sheet.ensure_ready()
	TEST_ASSERT(sheet.fully_generated, "a later build of the sheet succeeds")
	TEST_ASSERT_EQUAL(SSasset_loading.assets_generating, before, "and leaves the count where it was")
	GLOB.asset_datums -= sheet.type
