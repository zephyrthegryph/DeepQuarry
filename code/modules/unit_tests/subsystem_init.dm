/// The systems the kernel boots in its DAG (the former subsystems among them) must initialize.
/datum/unit_test/system_init

/datum/unit_test/system_init/Run()
	var/list/former_subsystems = list(
		SSassets, SSatoms, SSbehaviours, SSdbcore, SSearly_assets, SSgarbage, SSoverlays, SSprofiler, SSsqlite, SStgui, SSblackbox,
	)
	for(var/datum/system/booted as anything in former_subsystems)
		TEST_ASSERT(booted.initialized, "[booted] ([booted.type]) is a system the kernel boots, but it never initialized")
