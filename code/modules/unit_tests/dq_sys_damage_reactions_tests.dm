// Declared damage reactions (code/__defines/sys_damage_reactions.dm), doc/rewrite/systems.md section 12.

/// A machine that declares one of each reaction shape and counts what ran.
/obj/machinery/dq_reaction_probe
	name = "reaction probe"
	use_power = USE_POWER_OFF
	max_integrity = 1000
	var/projectile_seen = 0
	var/blast_seen = 0
	var/block_projectiles = FALSE

CAPABILITIES(/obj/machinery/dq_reaction_probe)
	extend(/datum/act/hit/projectile, instead(then(PROC_REF(on_projectile))))
	on_notice(/datum/notice/hit/explosion, then(PROC_REF(on_blast)))

/obj/machinery/dq_reaction_probe/proc/on_projectile(datum/act/hit/projectile/A)
	projectile_seen++
	if(block_projectiles)
		return OP_OK
	return HOOK_DECLINE

/obj/machinery/dq_reaction_probe/proc/on_blast(datum/act/A)
	var/datum/notice/hit/explosion/N = A
	var/datum/damage_packet/packet = N.packet
	blast_seen = packet.severity

/// Reflects every projectile.
/obj/structure/dq_reflect_probe
	name = "reflect probe"
	density = TRUE

CAPABILITY(/obj/structure/dq_reflect_probe, reflects(list(/obj/item/projectile), 100))

/// Reflects only burn, with a chance answered by a holder proc.
/obj/structure/dq_reflect_probe/burn_only
	var/reflect_chance = 100

CAPABILITY(/obj/structure/dq_reflect_probe/burn_only, reflects(list(BURN), PROC_REF(current_reflect_chance)))

/obj/structure/dq_reflect_probe/burn_only/proc/current_reflect_chance()
	return reflect_chance

/datum/unit_test/sys_damage_reactions
	abstract_type = /datum/unit_test/sys_damage_reactions

/datum/unit_test/sys_damage_reactions/proc/projectile(injury_kind, damage)
	var/obj/item/projectile/P = allocate(/obj/item/projectile, run_loc_floor_bottom_left)
	P.injury_kind = injury_kind
	P.damage = damage
	P.nodamage = !damage
	rel_set(P, nameof(P.starting), run_loc_floor_bottom_left)
	return P

/// A hit hook runs once per hit, a zero-damage round included, and a cancelling hook stops the sink; an explosion notice reads packet.severity.
/datum/unit_test/sys_damage_reactions/entries

/datum/unit_test/sys_damage_reactions/entries/Run()
	var/obj/machinery/dq_reaction_probe/probe = allocate(/obj/machinery/dq_reaction_probe)

	probe.bullet_act(projectile(INJURY_BLUNT, 20))
	TEST_ASSERT_EQUAL(probe.projectile_seen, 1, "a projectile hit runs the projectile hook once")

	probe.bullet_act(projectile(INJURY_BLUNT, 0))
	TEST_ASSERT_EQUAL(probe.projectile_seen, 2, "a zero-damage round still reaches the projectile hook")

	var/before = probe.get_integrity()
	probe.block_projectiles = TRUE
	probe.bullet_act(projectile(INJURY_BLUNT, 20))
	TEST_ASSERT_EQUAL(probe.projectile_seen, 3, "the blocking hook ran")
	TEST_ASSERT_EQUAL(probe.get_integrity(), before, "a taken-over hit stops the sink")

	probe.ex_act(2)
	TEST_ASSERT_EQUAL(probe.blast_seen, 2, "the explosion notice reads packet.severity")

/// reflects(): a matching round bounces (bullet_act returns PROJECTILE_CONTINUE) and lands nothing.
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
	TEST_ASSERT(!burn.reflect_projectile(projectile(INJURY_BURN, 20)), "the chance is answered by the holder proc")
	TEST_ASSERT(cap_of(any, /datum/capability/reflects), "reflects() is a capability")

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
	rel_set(B, nameof(B.starting), run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(slime.bullet_act(B), PROJECTILE_CONTINUE, "a silver slime reflects beams")

/// A mob that blocks every projectile by declaration (a shield, an immunity).
/mob/living/simple_mob/dq_projectile_immune
	name = "projectile-immune probe"

CAPABILITIES(/mob/living/simple_mob/dq_projectile_immune)
	extend(/datum/act/hit/projectile, instead())

/// A blocking DAMAGE_PROJECTILE reaction runs before the round's own effects, so a blocked stun
/// round stuns nobody and injures nobody; the same round on an ordinary mob does stun.
/datum/unit_test/sys_damage_reactions/blocked_stun

/datum/unit_test/sys_damage_reactions/blocked_stun/Run()
	var/mob/living/simple_mob/dq_projectile_immune/immune = allocate(/mob/living/simple_mob/dq_projectile_immune)
	var/obj/item/projectile/P = projectile(INJURY_BLUNT, 20)
	P.stun = 10
	P.weaken = 10
	var/vitality = immune.vitality()
	immune.bullet_act(P, BP_TORSO)
	TEST_ASSERT_EQUAL(immune.status_units(STAT_STUNNED), 0, "a blocked stun round applies no stun")
	TEST_ASSERT_EQUAL(immune.status_units(STAT_WEAKENED), 0, "nor weaken")
	TEST_ASSERT_EQUAL(immune.vitality(), vitality, "nor damage")

	var/mob/living/simple_mob/animal/passive/cockroach/control = allocate(/mob/living/simple_mob/animal/passive/cockroach)
	var/obj/item/projectile/Q = projectile(INJURY_BLUNT, 0)
	Q.stun = 10
	control.bullet_act(Q, BP_TORSO)
	TEST_ASSERT(control.status_units(STAT_STUNNED) > 0, "the same round stuns a mob with no blocking reaction")
