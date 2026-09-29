// Declared damage reactions (code/__defines/sys_damage_reactions.dm), doc/rewrite/systems.md section 12.

/// A machine that declares one of each reaction shape and counts what ran.
/obj/machinery/dq_reaction_probe
	name = "reaction probe"
	use_power = USE_POWER_OFF
	max_integrity = 1000
	var/emp_seen = 0
	var/emp_severity = 0
	var/projectile_seen = 0
	var/blast_seen = 0
	var/after_seen = 0
	var/integrity_at_after = 0
	var/pain_seen = 0
	var/block_projectiles = FALSE
	var/disable_changes = 0
	EXPIRY_DECLARE(emp_until)

DAMAGE_REACTION(/obj/machinery/dq_reaction_probe, DAMAGE_EMP, PROC_REF(on_emp))
DAMAGE_REACTION(/obj/machinery/dq_reaction_probe, DAMAGE_PROJECTILE, PROC_REF(on_projectile))
DAMAGE_REACTION(/obj/machinery/dq_reaction_probe, DAMAGE_EXPLOSION, PROC_REF(on_blast))
DAMAGE_REACTION(/obj/machinery/dq_reaction_probe, DAMAGE_PAIN, PROC_REF(on_pain))
DAMAGE_REACTION_AFTER(/obj/machinery/dq_reaction_probe, DAMAGE_PROJECTILE, PROC_REF(after_projectile))
EMP_DISABLE(/obj/machinery/dq_reaction_probe, 30 SECONDS, "emp_until")

/obj/machinery/dq_reaction_probe/proc/on_emp(datum/damage_packet/packet)
	emp_seen++
	emp_severity = packet.severity

/obj/machinery/dq_reaction_probe/proc/on_projectile(datum/damage_packet/packet)
	projectile_seen++
	if(block_projectiles)
		return DAMAGE_REACTION_BLOCK

/obj/machinery/dq_reaction_probe/proc/on_blast(datum/damage_packet/packet)
	blast_seen = packet.severity

/obj/machinery/dq_reaction_probe/proc/on_pain(datum/damage_packet/packet)
	pain_seen++

/obj/machinery/dq_reaction_probe/proc/after_projectile(datum/damage_packet/packet)
	after_seen++
	integrity_at_after = get_integrity()

/obj/machinery/dq_reaction_probe/emp_disable_changed(disabled)
	..()
	disable_changes++

/// Reflects every projectile.
/obj/structure/dq_reflect_probe
	name = "reflect probe"
	density = TRUE

REFLECTS(/obj/structure/dq_reflect_probe, list(/obj/item/projectile), 100)

/// Reflects only burn, with a chance read from a var.
/obj/structure/dq_reflect_probe/burn_only
	var/reflect_chance = 100

REFLECTS(/obj/structure/dq_reflect_probe/burn_only, list(BURN), "reflect_chance")

/datum/unit_test/sys_damage_reactions
	abstract_type = /datum/unit_test/sys_damage_reactions

/datum/unit_test/sys_damage_reactions/proc/projectile(injury_kind, damage)
	var/obj/item/projectile/P = allocate(/obj/item/projectile, run_loc_floor_bottom_left)
	P.injury_kind = injury_kind
	P.damage = damage
	P.nodamage = !damage
	P.starting = run_loc_floor_bottom_left
	return P

/// Entry triggers fire once per hit, before the sink (or after it, for the AFTER phase); a
/// zero-damage hit still fires its entry's reactions; BLOCK stops the sink.
/datum/unit_test/sys_damage_reactions/entries

/datum/unit_test/sys_damage_reactions/entries/Run()
	var/obj/machinery/dq_reaction_probe/probe = allocate(/obj/machinery/dq_reaction_probe)
	var/full = probe.get_integrity()

	probe.bullet_act(projectile(INJURY_BLUNT, 20))
	TEST_ASSERT_EQUAL(probe.projectile_seen, 1, "a projectile hit runs the DAMAGE_PROJECTILE reaction once")
	TEST_ASSERT_EQUAL(probe.after_seen, 1, "the AFTER reaction runs")
	TEST_ASSERT(probe.integrity_at_after < full, "the AFTER reaction runs after the sink applied the hit")
	TEST_ASSERT_EQUAL(probe.emp_seen, 0, "a projectile doesn't fire EMP reactions")

	probe.bullet_act(projectile(INJURY_BLUNT, 0))
	TEST_ASSERT_EQUAL(probe.projectile_seen, 2, "a zero-damage round still fires the projectile reaction")

	var/before = probe.get_integrity()
	probe.block_projectiles = TRUE
	probe.bullet_act(projectile(INJURY_BLUNT, 20))
	TEST_ASSERT_EQUAL(probe.projectile_seen, 3, "the blocking reaction ran")
	TEST_ASSERT_EQUAL(probe.get_integrity(), before, "DAMAGE_REACTION_BLOCK stops the sink")
	TEST_ASSERT_EQUAL(probe.after_seen, 2, "a blocked hit runs no AFTER reaction")

	probe.ex_act(2)
	TEST_ASSERT_EQUAL(probe.blast_seen, 2, "the explosion reaction reads packet.severity")

	probe.deal_damage(DAMAGE_PAIN, 5)
	TEST_ASSERT_EQUAL(probe.pain_seen, 1, "a kind trigger fires when the packet carries that kind")
	probe.deal_damage(DAMAGE_BLUNT, 5)
	TEST_ASSERT_EQUAL(probe.pain_seen, 1, "a kind trigger doesn't fire for other kinds")

/// EMP reactions: fire only when the pulse isn't blocked; EMP_DISABLE sets the field and EMPED,
/// and the lapse (section 17) restores them, once.
/datum/unit_test/sys_damage_reactions/emp_disable

/datum/unit_test/sys_damage_reactions/emp_disable/Run()
	var/obj/machinery/dq_reaction_probe/probe = allocate(/obj/machinery/dq_reaction_probe)
	TEST_ASSERT(!probe.has_stat(EMPED), "starts working")
	probe.emp_act(EMP_MEDIUM)
	TEST_ASSERT_EQUAL(probe.emp_seen, 1, "an EMP runs the DAMAGE_EMP reaction")
	TEST_ASSERT_EQUAL(probe.emp_severity, EMP_MEDIUM, "with the pulse's severity")
	TEST_ASSERT(probe.has_stat(EMPED), "EMP_DISABLE sets EMPED on machinery")
	TEST_ASSERT(EXPIRY_ACTIVE(probe, emp_until, CLOCK_WORLD), "EMP_DISABLE sets the declared field")
	TEST_ASSERT_EQUAL(EXPIRY_LEFT(probe, emp_until, CLOCK_WORLD), 30 SECONDS / EMP_MEDIUM, "for duration / severity")
	TEST_ASSERT_EQUAL(probe.disable_changes, 1, "emp_disable_changed(TRUE) ran")

	var/until = probe.emp_until
	probe.emp_act(EMP_HEAVY)
	TEST_ASSERT_EQUAL(probe.emp_until, until, "an EMP while down doesn't extend the outage")
	TEST_ASSERT_EQUAL(probe.disable_changes, 1, "nor re-runs the down hook")

	probe.emp_until = world.time - 1
	expiry_lapse_fire(probe, "emp_until")
	TEST_ASSERT(!probe.has_stat(EMPED), "the lapse clears EMPED")
	TEST_ASSERT_EQUAL(probe.emp_until, 0, "and the field")
	TEST_ASSERT_EQUAL(probe.disable_changes, 2, "emp_disable_changed(FALSE) ran")
	probe.emp_disable_lapsed()
	TEST_ASSERT_EQUAL(probe.disable_changes, 2, "the lapse hook is idempotent")

	probe.emp_protection_flags = EMP_PROTECT_SELF
	probe.emp_act(EMP_HEAVY)
	TEST_ASSERT_EQUAL(probe.emp_seen, 2, "a blocked pulse runs no EMP reaction")
	TEST_ASSERT(!probe.has_stat(EMPED), "and disables nothing")

/// REFLECTS: a matching round bounces (bullet_act returns PROJECTILE_CONTINUE) and lands nothing.
/datum/unit_test/sys_damage_reactions/reflects

/datum/unit_test/sys_damage_reactions/reflects/Run()
	var/obj/structure/dq_reflect_probe/any = allocate(/obj/structure/dq_reflect_probe)
	var/obj/item/projectile/P = projectile(INJURY_BLUNT, 20)
	var/full = any.get_integrity()
	TEST_ASSERT_EQUAL(any.bullet_act(P), PROJECTILE_CONTINUE, "a reflected round keeps flying")
	TEST_ASSERT(P.reflected, "and is marked reflected")
	TEST_ASSERT_EQUAL(any.get_integrity(), full, "a reflected round lands nothing")

	var/obj/structure/dq_reflect_probe/burn_only/burn = allocate(/obj/structure/dq_reflect_probe/burn_only)
	TEST_ASSERT(!burn.reflect_projectile(projectile(INJURY_BLUNT, 20)), "a kind list of BURN ignores brute rounds")
	TEST_ASSERT(burn.reflect_projectile(projectile(INJURY_BURN, 20)), "and reflects burn rounds")
	burn.reflect_chance = 0
	TEST_ASSERT(!burn.reflect_projectile(projectile(INJURY_BURN, 20)), "the chance is read from the named var")

/// Migrated real types: a mob family's explosion reaction blocks its ladder, and the
/// reflecting slimes bounce beams.
/datum/unit_test/sys_damage_reactions/migrated_types

/datum/unit_test/sys_damage_reactions/migrated_types/Run()
	var/mob/living/simple_mob/animal/passive/cockroach/roach = allocate(/mob/living/simple_mob/animal/passive/cockroach)
	var/vitality = roach.vitality()
	roach.ex_act(1)
	TEST_ASSERT(!QDELETED(roach), "a cockroach shrugs off a blast")
	TEST_ASSERT_EQUAL(roach.vitality(), vitality, "and takes nothing from it")

	var/obj/effect/weaversilk/silk = allocate(/obj/effect/weaversilk)
	silk.ex_act(3)
	TEST_ASSERT(QDELETED(silk), "weaver silk is destroyed by any blast")

	var/mob/living/simple_mob/slime/xenobio/silver/slime = allocate(/mob/living/simple_mob/slime/xenobio/silver)
	var/obj/item/projectile/beam/B = allocate(/obj/item/projectile/beam, run_loc_floor_bottom_left)
	B.starting = run_loc_floor_bottom_left
	TEST_ASSERT_EQUAL(slime.bullet_act(B), PROJECTILE_CONTINUE, "a silver slime reflects beams")
