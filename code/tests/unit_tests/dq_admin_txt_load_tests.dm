/// The legacy admins.txt grants its keys their rank: config/example's "BigBadE = Host" makes ckey bigbade a Host admin with every right.
/datum/unit_test/dq_admin_txt_load

/datum/unit_test/dq_admin_txt_load/Run()
	var/old_directory = global.config.directory
	var/old_legacy = CONFIG_GET(flag/admin_legacy_system)
	var/list/old_datums = GLOB.admin_datums.Copy()
	global.config.directory = "config/example"
	CONFIG_SET(flag/admin_legacy_system, TRUE)
	load_admins(TRUE, TRUE)
	var/datum/admins/holder = GLOB.admin_datums["bigbade"]
	var/list/rank_names = list()
	for(var/datum/admin_rank/R as anything in GLOB.admin_ranks)
		rank_names += R.name
	TEST_ASSERT_NOTNULL(holder, "admins.txt makes bigbade an admin; datums: [json_encode(GLOB.admin_datums)] ranks: [json_encode(rank_names)]")
	if(holder)
		TEST_ASSERT_EQUAL(holder.rank_flags() & R_EVERYTHING, R_EVERYTHING, "the Host rank grants every right ([holder.name])")
		// The holder must outlive boot: the player logs in minutes later.
		test_driver_begin()
		test_time(5 MINUTES)
		TEST_ASSERT(!QDELETED(holder), "the admin holder survives the round's sweeps")
		TEST_ASSERT_EQUAL(GLOB.admin_datums["bigbade"], holder, "bigbade is still an admin five minutes on")
	global.config.directory = old_directory
	CONFIG_SET(flag/admin_legacy_system, old_legacy)
	load_admins(TRUE, TRUE)
	TEST_ASSERT_EQUAL(length(GLOB.admin_datums), length(old_datums), "the test world's admins are restored")

/// A client's verb grants land on its /datum/client_verbs holder and reach the verbs of what it owns. grant() on a /client used to be
/// refused ("the holder is deleted or not a datum"), so no admin verb ever reached an admin. Clients can't be made in a test: the
/// holder is given a mob as its owner, which the store edits the same way.
/datum/unit_test/dq_client_verb_holder_grants

/datum/unit_test/dq_client_verb_holder_grants/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/client_verbs/holder = allocate(/datum/client_verbs, null)
	holder.owner = H
	var/datum/verb_source/source = verb_source("dq_client_verb_holder_grants")
	TEST_ASSERT(!(/client/proc/show_verbs in H.verbs), "the verb starts absent")
	TEST_ASSERT_NOTNULL(grant(holder, granted_verb(/client/proc/show_verbs), source), "the grant attaches to the holder")
	TEST_ASSERT(/client/proc/show_verbs in H.verbs, "the granted verb reaches the owner's verbs")
	revoke(holder, granted_verb(/client/proc/show_verbs), source)
	TEST_ASSERT(!(/client/proc/show_verbs in H.verbs), "the revoke takes it away")
	holder.owner = null
