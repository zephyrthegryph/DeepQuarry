// Tests for the mind/body runtime perk layer.
// See code/modules/mind_body/_perk_runtime.dm (granted_perks + has_perk), _perk.dm
// (base grant/revoke recording), _formulas.dm (capstone spend gate), and perks_body.dm.

// grant_perk / has_perk / revoke_perk maintain the runtime set.
/datum/unit_test/dq_perk_runtime_set

/datum/unit_test/dq_perk_runtime_set/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(!H.has_perk(/datum/perk/body/str_powerful), "a fresh mob should have no perks")
	H.grant_perk(/datum/perk/body/str_powerful)
	TEST_ASSERT(H.has_perk(/datum/perk/body/str_powerful), "grant_perk should register the perk")
	TEST_ASSERT(!H.has_perk(/datum/perk/body/str_brawler), "only the granted perk should read as present")
	H.revoke_perk(/datum/perk/body/str_powerful)
	TEST_ASSERT(!H.has_perk(/datum/perk/body/str_powerful), "revoke_perk should clear the perk")

// /datum/perk/grant() stamps its own type into the mob's runtime set — the apply hook
// relies on this so conditional perks become queryable at spawn.
/datum/unit_test/dq_perk_grant_records

/datum/unit_test/dq_perk_grant_records/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/perk/P = GLOB.all_perks[/datum/perk/body/str_brawler]
	TEST_ASSERT_NOTNULL(P, "Brawler should be in the perk registry")
	P.grant(H)
	TEST_ASSERT(H.has_perk(/datum/perk/body/str_brawler), "grant() should record the perk on the mob")
	P.revoke(H)
	TEST_ASSERT(!H.has_perk(/datum/perk/body/str_brawler), "revoke() should clear the perk from the mob")

// Every Body tree's capstone gates on the category-spend threshold rather than a chain.
/datum/unit_test/dq_perk_capstones_gated

/datum/unit_test/dq_perk_capstones_gated/Run()
	var/list/capstones = list(
		/datum/perk/body/str_juggernaut,
		/datum/perk/body/vig_undying,
		/datum/perk/body/spd_blur,
		/datum/perk/body/end_immovable,
	)
	for(var/path in capstones)
		var/datum/perk/P = GLOB.all_perks[path]
		TEST_ASSERT_NOTNULL(P, "capstone [path] should be registered")
		TEST_ASSERT_EQUAL(P.category_spend_required, DQ_PERK_CAPSTONE_SPEND, "capstone [path] should gate on the spend threshold")
		TEST_ASSERT(!LAZYLEN(P.requires), "capstone [path] should not also require a specific chain")

// Body perks register under the right tree and pool side, and stat perks carry their
// var_changes so the apply hook still bakes them into the species.
/datum/unit_test/dq_perk_body_registry

/datum/unit_test/dq_perk_body_registry/Run()
	var/datum/perk/P = GLOB.all_perks[/datum/perk/body/str_powerful]
	TEST_ASSERT_NOTNULL(P, "Powerful Build should be registered")
	TEST_ASSERT_EQUAL(P.perk_kind, PERK_KIND_BODY, "Powerful Build should draw the Body pool")
	TEST_ASSERT_EQUAL(P.tree, PERK_TREE_BODY_STRENGTH, "Powerful Build should live in the Strength tree")

	var/datum/perk/tough = GLOB.all_perks[/datum/perk/body/str_toughness]
	TEST_ASSERT_NOTNULL(tough.var_changes, "Toughness should carry var_changes")
	TEST_ASSERT_EQUAL(tough.var_changes["brute_mod"], 0.9, "Toughness should set brute_mod")
