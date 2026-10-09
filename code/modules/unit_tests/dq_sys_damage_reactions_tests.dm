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

DAMAGE_REACTION(/obj/machinery/dq_reaction_probe, DAMAGE_EMP, PROC_REF(on_emp))
CAPABILITIES(/obj/machinery/dq_reaction_probe)
	extend(/datum/act/hit/projectile, instead(then(PROC_REF(on_projectile))))
	on_notice(/datum/notice/hit/explosion, then(PROC_REF(on_blast)))
DAMAGE_REACTION(/obj/machinery/dq_reaction_probe, DAMAGE_PAIN, PROC_REF(on_pain))
DAMAGE_REACTION_AFTER(/obj/machinery/dq_reaction_probe, DAMAGE_PROJECTILE, PROC_REF(after_projectile))

/obj/machinery/dq_reaction_probe/proc/on_emp(datum/damage_packet/packet)
	emp_seen++
	emp_severity = packet.severity

/obj/machinery/dq_reaction_probe/proc/on_projectile(datum/act/hit/projectile/A)
	projectile_seen++
	if(block_projectiles)
		return OP_OK
	return HOOK_DECLINE

/obj/machinery/dq_reaction_probe/proc/on_blast(datum/act/A)
	var/datum/notice/hit/explosion/N = A
	var/datum/damage_packet/packet = N.packet
	blast_seen = packet.severity

/obj/machinery/dq_reaction_probe/proc/on_pain(datum/damage_packet/packet)
	pain_seen++

/obj/machinery/dq_reaction_probe/proc/after_projectile(datum/damage_packet/packet)
	after_seen++
	integrity_at_after = get_integrity()

/// Reflects every projectile.
/obj/structure/dq_reflect_probe
	name = "reflect probe"
	density = TRUE

REFLECTS(/obj/structure/dq_reflect_probe, list(/obj/item/projectile), 100)

/// Reflects only burn, with a chance answered by a holder proc.
/obj/structure/dq_reflect_probe/burn_only
	var/reflect_chance = 100

CAPABILITY(/obj/structure/dq_reflect_probe/burn_only, reflects(list(BURN), PROC_REF(current_reflect_chance)))

/obj/structure/dq_reflect_probe/burn_only/proc/current_reflect_chance()
	return reflect_chance

/// The foundation form, written out: damage reactions in reactions(), one blocking.
/obj/structure/dq_damage_rx_probe
	name = "damage reaction probe"
	max_integrity = 100
	var/before_seen = 0
	var/after_seen = 0
	var/block = FALSE

/obj/structure/dq_damage_rx_probe/reactions()
	. = ..()
	. += before_op(damage(DAMAGE_BLUNT), PROC_REF(on_blunt))
	. += after_op(damage(DAMAGE_BLUNT), PROC_REF(after_blunt))

/obj/structure/dq_damage_rx_probe/proc/on_blunt(datum/damage_packet/packet)
	before_seen++
	return block ? DAMAGE_REACTION_BLOCK : null

/obj/structure/dq_damage_rx_probe/proc/after_blunt(datum/damage_packet/packet)
	after_seen++

/// before_op(damage(kind)) / after_op(damage(kind)) in reactions(): read from the composed table by receive_damage();
/// a block stops the sink and the after rows; a repeated declaration runs once.
/datum/unit_test/sys_damage_reactions/foundation_form

/datum/unit_test/sys_damage_reactions/foundation_form/Run()
	var/obj/structure/dq_damage_rx_probe/probe = allocate(/obj/structure/dq_damage_rx_probe)
	TEST_ASSERT_EQUAL(length(damage_rows_of(probe)), 2, "one row per declared damage reaction")
	var/full = probe.get_integrity()
	probe.deal_damage(DAMAGE_BLUNT, 10)
	TEST_ASSERT_EQUAL(probe.before_seen, 1, "the before_op row ran")
	TEST_ASSERT_EQUAL(probe.after_seen, 1, "the after_op row ran after the sink")
	TEST_ASSERT(probe.get_integrity() < full, "the sink applied the hit")
	probe.block = TRUE
	var/now = probe.get_integrity()
	probe.deal_damage(DAMAGE_BLUNT, 10)
	TEST_ASSERT_EQUAL(probe.before_seen, 2, "the before_op row ran again")
	TEST_ASSERT_EQUAL(probe.get_integrity(), now, "a block stops the sink")
	TEST_ASSERT_EQUAL(probe.after_seen, 1, "and the after rows")
	probe.deal_damage(DAMAGE_THERMAL, 10)
	TEST_ASSERT_EQUAL(probe.before_seen, 2, "a kind trigger ignores other kinds")
	var/obj/machinery/dq_reaction_probe/machine = allocate(/obj/machinery/dq_reaction_probe)
	var/emp_rows = 0
	for(var/list/row as anything in damage_rows_of(machine))
		if(row[1] == DAMAGE_EMP)
			emp_rows++
	TEST_ASSERT_EQUAL(emp_rows, 1, "the type's own EMP reaction is one row")

/datum/unit_test/sys_damage_reactions
	abstract_type = /datum/unit_test/sys_damage_reactions

/datum/unit_test/sys_damage_reactions/proc/projectile(injury_kind, damage)
	var/obj/item/projectile/P = allocate(/obj/item/projectile, run_loc_floor_bottom_left)
	P.injury_kind = injury_kind
	P.damage = damage
	P.nodamage = !damage
	rel_set(P, nameof(P.starting), run_loc_floor_bottom_left)
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

/// EMP reactions fire only when the pulse isn't blocked.
/datum/unit_test/sys_damage_reactions/emp_blocked

/datum/unit_test/sys_damage_reactions/emp_blocked/Run()
	var/obj/machinery/dq_reaction_probe/probe = allocate(/obj/machinery/dq_reaction_probe)
	probe.emp_act(EMP_MEDIUM)
	TEST_ASSERT_EQUAL(probe.emp_seen, 1, "an EMP runs the DAMAGE_EMP reaction")
	TEST_ASSERT_EQUAL(probe.emp_severity, EMP_MEDIUM, "with the pulse's severity")
	probe.emp_protection_flags = EMP_PROTECT_SELF
	probe.emp_act(EMP_HEAVY)
	TEST_ASSERT_EQUAL(probe.emp_seen, 1, "a blocked pulse runs no EMP reaction")

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
	TEST_ASSERT(!burn.reflect_projectile(projectile(INJURY_BURN, 20)), "the chance is answered by the holder proc")
	TEST_ASSERT(cap_of(any, /datum/capability/reflects), "REFLECTS is the reflects() capability")

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

/// A zero-damage stun round (a taser dart) is vetoed by the same hook, and the hit action runs once per round.
/datum/unit_test/sys_damage_reactions/blocked_zero_damage_stun

/datum/unit_test/sys_damage_reactions/blocked_zero_damage_stun/Run()
	var/mob/living/simple_mob/dq_projectile_immune/immune = allocate(/mob/living/simple_mob/dq_projectile_immune)
	var/obj/item/projectile/P = projectile(INJURY_BLUNT, 0)
	P.stun = 10
	P.weaken = 10
	immune.bullet_act(P, BP_TORSO)
	TEST_ASSERT_EQUAL(immune.status_units(STAT_STUNNED), 0, "a vetoed zero-damage round applies no stun")
	TEST_ASSERT_EQUAL(immune.status_units(STAT_WEAKENED), 0, "nor weaken")
