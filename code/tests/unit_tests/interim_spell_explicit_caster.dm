/// The complete real targeted casting path uses the supplied caster and debits real charges.
/datum/spell/targeted/interim_explicit_caster
	spell_flags = INCLUDEUSER
	charge_type = Sp_CHARGES
	charge_max = 2
	cast_delay = 0
	range = 0
	amt_stunned = 2 SECONDS
	var/selection_actor_ref
	var/invocation_actor_ref

/datum/spell/targeted/interim_explicit_caster/choose_targets(mob/user)
	selection_actor_ref = user ? REF(user) : null
	return ..()

/datum/spell/targeted/interim_explicit_caster/invocation(mob/user, list/targets)
	invocation_actor_ref = user ? REF(user) : null
	return ..()

/datum/unit_test/interim_spell_explicit_cast/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/caster = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/datum/spell/targeted/interim_explicit_caster/spell = allocate(/datum/spell/targeted/interim_explicit_caster)
	TEST_ASSERT(caster.add_spell(spell), "the real caster receives the actual spell and its HUD master")
	TEST_ASSERT(spell in caster.spell_list, "the real spell appears in the caster's spell list")
	TEST_ASSERT_EQUAL(spell.charge_counter, 2, "the real constructor grants two casts")
	TEST_ASSERT(!caster.has_status(STAT_STUNNED), "the caster begins without the spell's status")
	spell.perform(caster)
	TEST_ASSERT_EQUAL(spell.holder(), caster, "the complete cast binds its real spell holder")
	TEST_ASSERT_EQUAL(spell.selection_actor_ref, REF(caster), "real target selection receives the explicit caster")
	TEST_ASSERT_EQUAL(spell.invocation_actor_ref, REF(caster), "real invocation receives the same explicit caster")
	TEST_ASSERT_EQUAL(spell.charge_counter, 1, "the complete real cast debits exactly one charge")
	TEST_ASSERT(caster.has_status(STAT_STUNNED), "the real targeted effect stuns its explicit self-target")
	TEST_ASSERT(!bystander.has_status(STAT_STUNNED), "the real targeted effect leaves the nearby bystander unchanged")
	spell.perform(caster)
	TEST_ASSERT_EQUAL(spell.charge_counter, 0, "the second real cast exhausts the final charge")
	spell.perform(caster)
	TEST_ASSERT_EQUAL(spell.charge_counter, 0, "the real validation prevents an exhausted cast from overdrawing")
	TEST_ASSERT(!bystander.has_status(STAT_STUNNED), "subsequent casts still leave the bystander unchanged")

/// Real dumbfire selection follows the supplied caster's location and direction.
/datum/unit_test/interim_spell_explicit_dumbfire/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/caster = allocate(/mob/living/carbon/human, T)
	var/datum/spell/targeted/projectile/dumbfire/spell = allocate(/datum/spell/targeted/projectile/dumbfire)
	spell.range = 1
	caster.set_dir(EAST)
	var/list/targets = spell.choose_targets(caster)
	TEST_ASSERT_EQUAL(length(targets), 1, "real dumbfire selection chooses one destination")
	TEST_ASSERT_EQUAL(targets[1], get_step(T, EAST), "real selection follows the supplied caster facing east")
	caster.set_dir(NORTH)
	targets = spell.choose_targets(caster)
	TEST_ASSERT_EQUAL(targets[1], get_step(T, NORTH), "changing the actual caster's direction changes the actual destination")

/// Area selection preserves its holder-centered annulus while accepting an explicit caller.
/datum/unit_test/interim_spell_explicit_area/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/caster = allocate(/mob/living/carbon/human, T)
	var/datum/spell/aoe_turf/spell = allocate(/datum/spell/aoe_turf)
	rel_set(spell, nameof(spell.holder), caster)
	spell.range = 1
	spell.inner_radius = 0
	spell.selection_type = "range"
	var/list/targets = spell.choose_targets(caster)
	TEST_ASSERT(length(targets), "the real annulus contains neighboring floor targets")
	TEST_ASSERT(!(T in targets), "the actual inner radius excludes the holder's center turf")
	TEST_ASSERT(get_step(T, EAST) in targets, "the actual annulus includes the adjacent east floor")
	TEST_ASSERT(!(run_loc_floor_top_right in targets), "the actual annulus excludes the distant fixture corner")
