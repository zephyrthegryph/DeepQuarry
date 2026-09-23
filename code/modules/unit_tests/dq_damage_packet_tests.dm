// Damage packets (doc/rewrite/damage.md §2, §3): every entry point builds a
// packet and hands it to receive_damage(). Each adapter test checks which
// packet an entry point produces, using probes that record the packet
// instead of applying it.

/// What a probe saw of the last packet it received.
/datum/dq_packet_record
	var/list/amounts
	var/penetration
	var/zone
	var/flags
	var/armor_flag
	var/atom/source
	var/atom/attacker
	var/atom/weapon

/datum/dq_packet_record/New(datum/damage_packet/packet)
	amounts = packet.amounts.Copy()
	penetration = packet.penetration
	zone = packet.zone
	flags = packet.flags
	armor_flag = packet.armor_flag
	source = packet.source
	attacker = packet.attacker
	weapon = packet.weapon

/datum/dq_packet_record/Destroy(force)
	source = null
	attacker = null
	weapon = null
	return ..()

/// Only `kind` carries damage, and exactly `amount` of it.
/datum/dq_packet_record/proc/only(kind, amount)
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		if(i == kind ? abs(amounts[i] - amount) > 0.01 : amounts[i] != 0)
			return FALSE
	return TRUE

/datum/dq_packet_record/proc/describe()
	var/list/parts = list()
	for(var/i in 1 to DAMAGE_KIND_COUNT)
		if(amounts[i])
			parts += "[i]=[amounts[i]]"
	return "{[jointext(parts, ", ")]} flags=[flags] pen=[penetration] zone=[zone]"

/// An object that records packets instead of losing integrity.
/obj/machinery/dq_damage_probe
	name = "damage probe"
	use_power = USE_POWER_OFF
	max_integrity = 1000
	var/datum/dq_packet_record/last
	var/received = 0

/obj/machinery/dq_damage_probe/receive_damage(datum/damage_packet/packet)
	received++
	QDEL_NULL(last)
	last = new(packet)
	return 0

/obj/machinery/dq_damage_probe/Destroy()
	QDEL_NULL(last)
	return ..()

/// A mob that records packets instead of being injured.
/mob/living/simple_mob/dq_damage_probe
	name = "damage probe"
	attack_injury_kind = INJURY_CUT
	attack_armor_pen = 7
	resistance = 0
	var/datum/dq_packet_record/last
	var/received = 0

/mob/living/simple_mob/dq_damage_probe/receive_damage(datum/damage_packet/packet)
	received++
	QDEL_NULL(last)
	last = new(packet)
	return 0

/mob/living/simple_mob/dq_damage_probe/Destroy()
	QDEL_NULL(last)
	return ..()

/datum/unit_test/dq_damage_packet
	abstract_type = /datum/unit_test/dq_damage_packet
	var/obj/machinery/dq_damage_probe/probe
	var/mob/living/simple_mob/dq_damage_probe/mob_probe

/datum/unit_test/dq_damage_packet/proc/make_probes()
	probe = allocate(/obj/machinery/dq_damage_probe)
	mob_probe = allocate(/mob/living/simple_mob/dq_damage_probe)

/datum/unit_test/dq_damage_packet/proc/make_projectile(kind, damage, pen = 0)
	var/obj/item/projectile/P = allocate(/obj/item/projectile)
	P.injury_kind = kind
	P.injury_kinds = null
	P.damage = damage
	P.armor_penetration = pen
	P.nodamage = FALSE
	P.emp_on_hit = FALSE
	return P

/datum/unit_test/dq_damage_packet/proc/make_item(kind, force, throwforce = 0)
	var/obj/item/I = allocate(/obj/item)
	I.injury_kind = kind
	I.injury_kinds = null
	I.force = force
	I.throwforce = throwforce
	I.armor_penetration = 5
	return I


/// The pool hands out clean packets and takes them back.
/datum/unit_test/dq_damage_packet/pool

/datum/unit_test/dq_damage_packet/pool/Run()
	var/datum/damage_packet/packet = damage_packet(null, null, null, BP_TORSO, DAMAGE_PACKET_PROJECTILE, 30)
	packet.add(DAMAGE_PIERCE, 12)
	packet.add_split(INJURY_BURN, alist(INJURY_BURN = 0.25, INJURY_CUT = 0.75), 8)
	TEST_ASSERT(dq_near(packet.amounts[DAMAGE_THERMAL], 2), "a split should share its amount out")
	TEST_ASSERT(dq_near(packet.amounts[DAMAGE_SHARP], 6), "a split should share its amount out")
	TEST_ASSERT(!packet.add_injury(INJURY_CELLULAR, 5), "cellular injury has no packet kind")
	packet.release()
	var/datum/damage_packet/again = damage_packet()
	TEST_ASSERT(again == packet, "a released packet should be reused")
	TEST_ASSERT_EQUAL(again.total(), 0, "a reused packet should come back empty")
	TEST_ASSERT_EQUAL(again.penetration, 0, "a reused packet should come back without penetration")
	TEST_ASSERT_NULL(again.zone, "a reused packet should come back without a zone")
	TEST_ASSERT_EQUAL(again.flags, NONE, "a reused packet should come back without flags")
	again.release()


/// Packet kinds reach injure() through the mapping agreed with the body rewrite.
/datum/unit_test/dq_damage_packet/injure_mapping
	var/list/seen

/datum/unit_test/dq_damage_packet/injure_mapping/proc/on_injure(mob/living/source, kind, list/amount_ref, zone, atom/injury_source, flags)
	SIGNAL_HANDLER
	seen += list(list(kind, flags))

/datum/unit_test/dq_damage_packet/injure_mapping/Run()
	var/static/list/expected = list(
		INJURY_BLUNT, INJURY_CUT, INJURY_PIERCE, INJURY_BURN, INJURY_FROSTBITE, INJURY_ELECTRIC,
		INJURY_CORROSIVE, INJURY_TOXIN, INJURY_RADIATION, INJURY_ELECTRIC, INJURY_BLUNT, INJURY_PAIN,
	)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	RegisterSignal(H, COMSIG_LIVING_INJURE, PROC_REF(on_injure))
	for(var/kind in 1 to DAMAGE_KIND_COUNT)
		seen = list()
		var/datum/damage_packet/packet = damage_packet(null, null, null, BP_TORSO, DAMAGE_PACKET_SILENT | DAMAGE_PACKET_PROJECTILE)
		packet.add(kind, 1)
		H.receive_damage(packet)
		packet.release()
		TEST_ASSERT_EQUAL(length(seen), 1, "packet kind [kind] should become one injury")
		var/list/hit = seen[1]
		TEST_ASSERT_EQUAL(hit[1], expected[kind], "packet kind [kind] should map to injury kind [expected[kind]]")
		TEST_ASSERT(hit[2] & INJURE_ARMORED, "hits from outside are armoured")
		TEST_ASSERT(hit[2] & INJURE_PROJECTILE, "the projectile flag should carry over")
		TEST_ASSERT(hit[2] & INJURE_SILENT, "the silent flag should carry over")
	seen = list()
	var/datum/damage_packet/packet = damage_packet(flags = DAMAGE_PACKET_UNARMORED)
	packet.add(DAMAGE_SHOCK, 1)
	H.receive_damage(packet)
	packet.release()
	TEST_ASSERT(!(seen[1][2] & INJURE_ARMORED), "an unarmoured packet should skip armour")
	UnregisterSignal(H, COMSIG_LIVING_INJURE)


/// Objects: physical kinds are brute, thermal and corrosive are burn, the
/// rest leave integrity alone; fire keeps its FIRE flag so objects burn down.
/datum/unit_test/dq_damage_packet/object_sink

/datum/unit_test/dq_damage_packet/object_sink/Run()
	var/obj/structure/grille/G = allocate(/obj/structure/grille)
	var/start = G.get_integrity()
	var/datum/damage_packet/packet = damage_packet(flags = DAMAGE_PACKET_SILENT)
	packet.add(DAMAGE_TOXIC, 5)
	packet.add(DAMAGE_PAIN, 5)
	packet.add(DAMAGE_SHOCK, 5)
	packet.add(DAMAGE_IONIC, 5)
	G.receive_damage(packet)
	packet.release()
	TEST_ASSERT_EQUAL(G.get_integrity(), start, "toxic, pain, shock and ionic should not touch integrity")
	G.deal_damage(DAMAGE_BLUNT, 3, flags = DAMAGE_PACKET_SILENT)
	TEST_ASSERT(G.get_integrity() < start, "blunt should cost integrity")
	TEST_ASSERT(BURN != FIRE, "BURN and FIRE must be distinct strings (B17)")


/// bullet_act on an object: the projectile's kinds, penetration and zone.
/datum/unit_test/dq_damage_packet/bullet_act

/datum/unit_test/dq_damage_packet/bullet_act/Run()
	make_probes()
	var/obj/item/projectile/P = make_projectile(INJURY_PIERCE, 20, 15)
	probe.bullet_act(P, BP_TORSO)
	TEST_ASSERT_EQUAL(probe.received, 1, "a projectile hit should deliver one packet")
	TEST_ASSERT(probe.last.only(DAMAGE_PIERCE, 20), "a bullet should pierce for its damage: [probe.last.describe()]")
	TEST_ASSERT_EQUAL(probe.last.penetration, 15, "the packet should carry the round's penetration")
	TEST_ASSERT(probe.last.flags & DAMAGE_PACKET_PROJECTILE, "the packet should be marked as a projectile")
	TEST_ASSERT_EQUAL(probe.last.source, P, "the round is the packet's source")

	var/obj/item/projectile/split = make_projectile(INJURY_BURN, 30)
	split.injury_kinds = alist(INJURY_BURN = 1/3, INJURY_CUT = 2/3)
	probe.bullet_act(split)
	TEST_ASSERT(dq_near(probe.last.amounts[DAMAGE_THERMAL], 10, 0.01) && dq_near(probe.last.amounts[DAMAGE_SHARP], 20, 0.01), "a searing round should split: [probe.last.describe()]")

	var/obj/item/projectile/ion = make_projectile(INJURY_ELECTRIC, 30)
	ion.emp_on_hit = TRUE
	probe.bullet_act(ion)
	TEST_ASSERT_EQUAL(probe.received, 2, "ion rounds pulse instead of delivering a packet")

	// Mobs: the same packet, through inflict_injury().
	var/obj/item/projectile/mob_round = make_projectile(INJURY_PIERCE, 20, 15)
	mob_probe.bullet_act(mob_round, BP_TORSO)
	TEST_ASSERT(mob_probe.last?.only(DAMAGE_PIERCE, 20), "a mob should get the round's packet: [mob_probe.last?.describe()]")
	TEST_ASSERT_EQUAL(mob_probe.last.zone, BP_TORSO, "the packet should carry the struck zone")
	TEST_ASSERT_EQUAL(mob_probe.last.penetration, 15, "the packet should carry penetration for injure()'s armour stage")


/// A projectile_damage() override changes how much of a round a type catches.
/datum/unit_test/dq_damage_packet/projectile_shape

/datum/unit_test/dq_damage_packet/projectile_shape/Run()
	var/obj/machinery/portable_atmospherics/canister/C = allocate(/obj/machinery/portable_atmospherics/canister)
	var/obj/item/projectile/P = allocate(/obj/item/projectile)
	P.injury_kind = INJURY_BLUNT
	P.damage = 40
	var/start = C.get_integrity()
	C.bullet_act(P)
	TEST_ASSERT(C.get_integrity() >= start - 20 - DAMAGE_PRECISION, "a canister catches at most half a round ([start] -> [C.get_integrity()])")
	TEST_ASSERT(C.get_integrity() < start, "a canister still takes damage from a round")


/// Weapon hits on objects and mobs: the weapon's kinds at its force.
/datum/unit_test/dq_damage_packet/weapon_hit

/datum/unit_test/dq_damage_packet/weapon_hit/Run()
	make_probes()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/obj/item/W = make_item(INJURY_CUT, 18)
	probe.receive_weapon_hit(W, user)
	TEST_ASSERT(probe.last.only(DAMAGE_SHARP, 18), "a blade should cut for its force: [probe.last.describe()]")
	TEST_ASSERT_EQUAL(probe.last.weapon, W, "the weapon is recorded")
	TEST_ASSERT_EQUAL(probe.last.attacker, user, "the wielder is recorded")
	TEST_ASSERT_EQUAL(probe.last.penetration, 5, "the weapon's penetration is carried")
	probe.receive_weapon_hit(W, user, 9, INJURY_BURN)
	TEST_ASSERT(probe.last.only(DAMAGE_THERMAL, 9), "a type can say how a tool hurts it: [probe.last.describe()]")

	// Mob melee (standard_weapon_hit_effects): zoned, armoured, not silent.
	mob_probe.standard_weapon_hit_effects(W, user, 18, 0, BP_TORSO)
	TEST_ASSERT(mob_probe.last?.only(DAMAGE_SHARP, 18), "melee on a mob should deliver the weapon's packet: [mob_probe.last?.describe()]")
	TEST_ASSERT_EQUAL(mob_probe.last.zone, BP_TORSO, "melee should land on the struck zone")
	TEST_ASSERT(!(mob_probe.last.flags & (DAMAGE_PACKET_SILENT | DAMAGE_PACKET_UNARMORED)), "melee on a mob is armoured and felt")


/// Weapon melee lands on non-human carbons again (B3).
/datum/unit_test/dq_damage_packet/carbon_melee

/datum/unit_test/dq_damage_packet/carbon_melee/Run()
	var/mob/living/carbon/alien/diona/nymph = allocate(/mob/living/carbon/alien/diona)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife)
	TEST_ASSERT_EQUAL(nymph.resolve_item_attack(knife, user, BP_TORSO), BP_TORSO, "a weapon swing at a nymph should resolve to the aimed zone")


/// Thrown impacts (hitby / throw_impact): the one force formula, the item's kinds.
/datum/unit_test/dq_damage_packet/thrown

/datum/unit_test/dq_damage_packet/thrown/Run()
	make_probes()
	var/obj/item/I = make_item(INJURY_BLUNT, 0, 12)
	probe.hitby(I, null)
	TEST_ASSERT(probe.last.only(DAMAGE_BLUNT, 12), "a thrown item should hit for its throwforce: [probe.last.describe()]")
	TEST_ASSERT(probe.last.flags & DAMAGE_PACKET_THROWN, "the packet should be marked as thrown")
	TEST_ASSERT_EQUAL(probe.last.source, I, "the thrown item is the source")
	I.throw_impact(probe, null)
	TEST_ASSERT_EQUAL(probe.received, 2, "throw_impact should reach the same adapter")
	var/obj/item/knife = make_item(INJURY_PIERCE, 0, 10)
	mob_probe.hitby(knife, null)
	TEST_ASSERT(mob_probe.last?.only(DAMAGE_PIERCE, 10), "a thrown knife should pierce a mob: [mob_probe.last?.describe()]")


/// ex_act: blast from the severity.
/datum/unit_test/dq_damage_packet/ex_act

/datum/unit_test/dq_damage_packet/ex_act/Run()
	make_probes()
	probe.ex_act(2)
	TEST_ASSERT(probe.last.only(DAMAGE_BLAST, probe.max_integrity * 0.5), "a severity-2 explosion should blast half of max integrity: [probe.last.describe()]")
	probe.ex_act(3)
	TEST_ASSERT(probe.last.only(DAMAGE_BLAST, probe.max_integrity * 0.25), "a severity-3 explosion should blast a quarter: [probe.last.describe()]")


/// emp_act: ionic from the shared ladder, only for types that EMPs can break.
/datum/unit_test/dq_damage_packet/emp_act

/datum/unit_test/dq_damage_packet/emp_act/Run()
	make_probes()
	probe.emp_act(EMP_MEDIUM)
	TEST_ASSERT_EQUAL(probe.received, 0, "EMPs don't break objects without an emp_integrity_factor")
	probe.emp_integrity_factor = 1
	probe.emp_act(EMP_MEDIUM)
	TEST_ASSERT(probe.last?.only(DAMAGE_IONIC, emp_ionic_damage(EMP_MEDIUM)), "an EMP should deliver the ladder's ionic amount: [probe.last?.describe()]")
	TEST_ASSERT(probe.last.flags & DAMAGE_PACKET_UNARMORED, "EMP surges ignore armour")


/// attack_generic: the attacker's declared kind and penetration.
/datum/unit_test/dq_damage_packet/attack_generic

/datum/unit_test/dq_damage_packet/attack_generic/Run()
	make_probes()
	probe.attack_generic(mob_probe, 12, "bites")
	TEST_ASSERT(probe.last?.only(DAMAGE_SHARP, 12), "an animal attack should use the animal's kind: [probe.last?.describe()]")
	TEST_ASSERT_EQUAL(probe.last.penetration, 7, "an animal attack should carry the animal's penetration")
	TEST_ASSERT_EQUAL(probe.last.attacker, mob_probe, "the animal is the attacker")
	var/mob/living/simple_mob/dq_damage_probe/victim = allocate(/mob/living/simple_mob/dq_damage_probe)
	victim.attack_generic(mob_probe, 12, "bites")
	TEST_ASSERT(victim.last?.only(DAMAGE_SHARP, 12), "an animal attack on a mob should use the same packet: [victim.last?.describe()]")
	TEST_ASSERT(victim.last.flags & DAMAGE_PACKET_UNARMORED, "animal attacks on plain mobs are unarmoured, as before")


/// blob_act: the blob type's profile (a plain blunt blow without an overmind).
/datum/unit_test/dq_damage_packet/blob_act

/datum/unit_test/dq_damage_packet/blob_act/Run()
	make_probes()
	probe.blob_act(null)
	var/blunt = probe.last?.amounts[DAMAGE_BLUNT]
	TEST_ASSERT(blunt >= 30 && blunt <= 40, "a blob without an overmind should strike blunt for 30-40: [probe.last?.describe()]")


/// fire_act: thermal, flagged FIRE so the object burns down.
/datum/unit_test/dq_damage_packet/fire_act

/datum/unit_test/dq_damage_packet/fire_act/Run()
	make_probes()
	probe.fire_act(T0C + 1000, 100)
	var/thermal = probe.last?.amounts[DAMAGE_THERMAL]
	TEST_ASSERT(thermal > 0 && thermal <= 20, "a fire should deliver 0-20 thermal: [probe.last?.describe()]")
	TEST_ASSERT_EQUAL(probe.last.armor_flag, FIRE, "fire damage keeps the FIRE flag")


/// electrocute_act: shock after insulation, unarmoured.
/datum/unit_test/dq_damage_packet/electrocute_act

/datum/unit_test/dq_damage_packet/electrocute_act/Run()
	make_probes()
	mob_probe.electrocute_act(30, probe, 0.5)
	TEST_ASSERT(mob_probe.last?.only(DAMAGE_SHOCK, 15), "a shock should deliver its insulated amount: [mob_probe.last?.describe()]")
	TEST_ASSERT(mob_probe.last.flags & DAMAGE_PACKET_UNARMORED, "armour doesn't apply to a shock twice")
