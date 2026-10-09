// D3 (doc/rewrite/damage.md §5): every object's hit points are its integrity.
// Walls and the old separate health pools each keep their damage, break,
// destroy and repair outcomes, now through take_damage() / repair_damage().

/datum/unit_test/dq_integrity_pool
	abstract_type = /datum/unit_test/dq_integrity_pool
	/// Atoms that were on the scratch turf before the test, so debris can be cleared.
	var/list/before_contents

/// A turf away from allocate()'s default one, so debris and blob tile-eating
/// don't touch other tests' atoms.
/datum/unit_test/dq_integrity_pool/proc/scratch_turf()
	RETURN_TYPE(/turf)
	var/turf/T = run_loc_floor_top_right || test_floor()
	before_contents = T.contents.Copy()
	return T

/// Deletes whatever a destroyed object left on the scratch turf.
/datum/unit_test/dq_integrity_pool/proc/clear_debris(turf/T)
	for(var/atom/movable/AM in turf_contents_of_type(T, /atom/movable))
		if(!(AM in before_contents) && !ismob(AM) && !istype(AM, /obj/effect/landmark))
			qdel(AM)



/// Walls: the material cap is max integrity, damage and repair move integrity,
/// projectiles are capped at 100, wall-rot multiplies hits, and zero dismantles.
/datum/unit_test/dq_integrity_pool/wall

/datum/unit_test/dq_integrity_pool/wall/Run()
	var/turf/T = scratch_turf()
	var/old_type = T.type
	var/turf/simulated/wall/W = T.ChangeTurf(/turf/simulated/wall)
	TEST_ASSERT(istype(W), "ChangeTurf should make a wall")
	W.set_material(get_material_by_name(MAT_PLASTEEL))
	W.set_reinf_material(get_material_by_name(MAT_PLASTEEL))
	W.update_material()
	var/cap = W.material.integrity + W.reinf_material.integrity
	TEST_ASSERT(W.uses_integrity, "walls use integrity")
	TEST_ASSERT_EQUAL(W.max_integrity, cap, "a wall's max integrity is its material cap")
	TEST_ASSERT_EQUAL(W.get_integrity(), cap, "a new wall is intact")

	W.take_damage(50)
	TEST_ASSERT_EQUAL(W.get_integrity(), cap - 50, "damage should come off integrity")
	TEST_ASSERT(dq_near(W.wall_damage_fraction(), 50 / cap), "the damage fraction drives the overlay and examine text")

	W.repair_damage(W.max_integrity)
	TEST_ASSERT_EQUAL(W.get_integrity(), cap, "welder repair restores the wall")

	var/obj/item/projectile/P = allocate(/obj/item/projectile)
	P.injury_kind = INJURY_BLUNT
	P.injury_kinds = null
	P.damage = 300
	P.nodamage = FALSE
	P.emp_on_hit = FALSE
	W.projectile_damage(P, null)
	TEST_ASSERT_EQUAL(W.get_integrity(), cap - 100, "a wall catches at most 100 of a round")
	W.repair_damage(W.max_integrity)

	var/obj/effect/overlay/wallrot/rot = new(W)
	W.take_damage(5)
	TEST_ASSERT_EQUAL(W.get_integrity(), cap - 50, "wall-rot makes every hit count ten times")
	qdel(rot)
	W.repair_damage(W.max_integrity)

	// Changing the material keeps the damage already done.
	W.take_damage(30)
	W.set_reinf_material(null)
	W.update_material()
	TEST_ASSERT_EQUAL(W.max_integrity, W.material.integrity, "an unreinforced wall's cap is its plating")
	TEST_ASSERT_EQUAL(W.get_integrity(), W.material.integrity - 30, "a material change keeps the wall's damage")

	W.take_damage(W.get_integrity() + 10)
	TEST_ASSERT(!istype(T, /turf/simulated/wall), "a wall at zero integrity is dismantled ([T.type])")
	// D-turf: floors keep integrity now; the overkill must not carry onto the floor left behind.
	TEST_ASSERT(!T.uses_integrity || T.get_integrity() == T.max_integrity, "the floor left behind is undamaged ([T.uses_integrity ? T.get_integrity() : "n/a"])")

	clear_debris(T)
	T.ChangeTurf(old_type)


/// The damage packet reaches a wall through its turf adapters, and a packet
/// that destroys it stops at the floor left behind.
/datum/unit_test/dq_integrity_pool/wall_packet

/datum/unit_test/dq_integrity_pool/wall_packet/Run()
	var/turf/T = scratch_turf()
	var/old_type = T.type
	var/turf/simulated/wall/W = T.ChangeTurf(/turf/simulated/wall)
	var/cap = W.max_integrity
	W.deal_damage(DAMAGE_BLUNT, 20, MELEE)
	TEST_ASSERT_EQUAL(W.get_integrity(), cap - 20, "a blunt packet lands on the wall")
	W.deal_damage(DAMAGE_TOXIC, 20)
	TEST_ASSERT_EQUAL(W.get_integrity(), cap - 20, "toxins don't harm walls")

	var/datum/damage_packet/packet = damage_packet(flags = DAMAGE_PACKET_SILENT)
	packet.add(DAMAGE_BLUNT, cap * 2)
	packet.add(DAMAGE_THERMAL, cap * 2)
	T.receive_damage(packet)
	packet.release()
	TEST_ASSERT(!istype(T, /turf/simulated/wall), "a big enough packet dismantles the wall")

	clear_debris(T)
	T.ChangeTurf(old_type)


/// blob2: blob integrity is atom integrity; the damaged icon is its broken state.
/datum/unit_test/dq_integrity_pool/blob

/datum/unit_test/dq_integrity_pool/blob/Run()
	var/turf/T = scratch_turf()
	var/obj/structure/blob/normal/B = allocate(/obj/structure/blob/normal, T)
	TEST_ASSERT_EQUAL(B.max_integrity, 25, "a normal blob has 25 integrity")
	TEST_ASSERT_EQUAL(B.get_integrity(), 21, "a normal blob doesn't start at full health")
	refresh_flush() // the blob draws its look at the refresh at the end of the frame
	TEST_ASSERT_EQUAL(B.icon_state, "blob", "a healthy blob looks healthy")

	B.adjust_integrity(-6)
	TEST_ASSERT_EQUAL(B.get_integrity(), 15, "blob damage comes off integrity")
	refresh_flush() // the blob draws its look at the refresh at the end of the frame
	TEST_ASSERT_EQUAL(B.icon_state, "blob_damaged", "a blob at 15 or less looks damaged")

	B.adjust_integrity(5)
	TEST_ASSERT_EQUAL(B.get_integrity(), 20, "pulses heal blob integrity")
	refresh_flush() // the blob draws its look at the refresh at the end of the frame
	TEST_ASSERT_EQUAL(B.icon_state, "blob", "a healed blob looks healthy again")

	B.deal_damage(DAMAGE_BLUNT, 4)
	TEST_ASSERT_EQUAL(B.get_integrity(), 16, "an inert blob takes packets at face value")

	B.adjust_integrity(-100)
	TEST_ASSERT(QDELETED(B), "a blob at zero integrity dies")
	clear_debris(T)


/// The old /obj/effect/blob: resistances divide hits; below half it looks damaged.
/datum/unit_test/dq_integrity_pool/old_blob

/datum/unit_test/dq_integrity_pool/old_blob/Run()
	var/turf/T = scratch_turf()
	var/obj/effect/blob/B = allocate(/obj/effect/blob, T)
	TEST_ASSERT_EQUAL(B.max_integrity, 30, "an old blob has 30 integrity")
	B.blob_damage(40, BRUTE)
	TEST_ASSERT_EQUAL(B.get_integrity(), 20, "brute resistance divides a hit by four")
	B.blob_damage(6, BURN)
	TEST_ASSERT_EQUAL(B.get_integrity(), 14, "burns land in full")
	TEST_ASSERT_EQUAL(B.appearance_state(), "blob_damaged", "below half integrity the blob looks damaged (its look declares the state; icon_state stays the mapped sprite)")
	B.regen()
	TEST_ASSERT_EQUAL(B.get_integrity(), 15, "a pulse regenerates one point")
	B.take_damage(100)
	TEST_ASSERT(QDELETED(B), "a blob at zero integrity bursts")
	clear_debris(T)


/// Energy fields: strength is integrity at 20 per Renwick; below one Renwick
/// the field drops, but it is never destroyed.
/datum/unit_test/dq_integrity_pool/energy_field

/datum/unit_test/dq_integrity_pool/energy_field/Run()
	var/turf/T = scratch_turf()
	var/obj/effect/energy_field/F = allocate(/obj/effect/energy_field, T)
	TEST_ASSERT_EQUAL(F.get_strength(), 0, "fields start down")
	TEST_ASSERT(!F.density, "a down field is not solid")

	F.set_max_strength(10)
	F.adjust_strength(5, 0)
	TEST_ASSERT_EQUAL(F.get_strength(), 5, "charging raises strength")
	TEST_ASSERT(F.density, "a charged field is solid")

	F.take_damage(40)
	TEST_ASSERT(dq_near(F.get_strength(), 3), "take_damage costs damage / 20 Renwicks ([F.get_strength()])")

	F.adjust_strength(-2.5, 0)
	TEST_ASSERT_EQUAL(F.get_strength(), 0, "below one Renwick the field breaks to zero")
	TEST_ASSERT(!F.density, "a broken field drops")
	TEST_ASSERT_EQUAL(F.ticks_recovering, 10, "a broken field recovers slowly")

	F.adjust_strength(-5, 0)
	TEST_ASSERT(!QDELETED(F), "a drained field is not destroyed")

	F.adjust_strength(2, 0)
	TEST_ASSERT(F.density, "a recharged field comes back up")


/// Simple doors: integrity is the material's, rounded to tens; explosions
/// land on it as blast packets; zero dismantles the door.
/datum/unit_test/dq_integrity_pool/simple_door

/datum/unit_test/dq_integrity_pool/simple_door/Run()
	var/turf/T = scratch_turf()
	var/obj/structure/simple_door/D = allocate(/obj/structure/simple_door, T, MAT_STEEL)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	TEST_ASSERT_EQUAL(D.max_integrity, max(1, round(steel.integrity / 10)) * 10, "a door's integrity is its material's")

	D.take_damage(25)
	TEST_ASSERT_EQUAL(D.get_integrity(), D.max_integrity - 25, "hits come off integrity")

	D.ex_act(3)
	TEST_ASSERT_EQUAL(D.get_integrity(), D.max_integrity * 0.75 - 25, "a light blast takes a quarter of the door's integrity")

	D.repair_damage(D.max_integrity)
	TEST_ASSERT_EQUAL(D.get_integrity(), D.max_integrity, "doors repair")

	D.take_damage(D.max_integrity)
	TEST_ASSERT(QDELETED(D), "a door at zero integrity is dismantled")
	TEST_ASSERT(locate_on(T, /obj/item/stack/material), "a dismantled door leaves its material")
	clear_debris(T)


/// Shooting targets: hp is integrity; zero breaks the target apart.
/datum/unit_test/dq_integrity_pool/target

/datum/unit_test/dq_integrity_pool/target/Run()
	var/turf/T = scratch_turf()
	var/obj/item/target/target = allocate(/obj/item/target, T)
	TEST_ASSERT_EQUAL(target.max_integrity, 1800, "a target has 1800 integrity")
	target.take_damage(1000, BRUTE, null, FALSE)
	TEST_ASSERT_EQUAL(target.get_integrity(), 800, "shots wear the target down")
	target.repair_damage(200)
	TEST_ASSERT_EQUAL(target.get_integrity(), 1000, "targets repair")
	target.take_damage(1000, BRUTE, null, FALSE)
	TEST_ASSERT(QDELETED(target), "a target at zero integrity collapses")
	clear_debris(T)


/// Tanks: the pressure seal is integrity (ten per old point). Stress wears it,
/// rest restores it, and a failed seal is a state, not a wreck.
/datum/unit_test/dq_integrity_pool/tank

/datum/unit_test/dq_integrity_pool/tank/Run()
	var/obj/item/tank/oxygen/tank = allocate(/obj/item/tank/oxygen)
	TEST_ASSERT_EQUAL(tank.max_integrity, 200, "a tank's seal has 200 integrity")
	tank.tank_stress(70)
	TEST_ASSERT_EQUAL(tank.get_integrity(), 130, "over-pressure stresses the seal")
	tank.repair_damage(10)
	TEST_ASSERT_EQUAL(tank.get_integrity(), 140, "the seal recovers at rest")
	tank.tank_stress(500)
	TEST_ASSERT_EQUAL(tank.get_integrity(), 0, "the seal can fail")
	TEST_ASSERT(!QDELETED(tank), "a failed seal doesn't delete the tank")
	tank.repair_damage(tank.max_integrity)
	TEST_ASSERT_EQUAL(tank.get_integrity(), 200, "a repaired tank is sealed again")


/// Shield projectors: the shield's strength is the projector's integrity; at
/// zero the shield overloads and the projector survives to recharge.
/datum/unit_test/dq_integrity_pool/shield_projector

/datum/unit_test/dq_integrity_pool/shield_projector/Run()
	var/turf/T = scratch_turf()
	var/obj/item/shield_projector/rectangle/projector = allocate(/obj/item/shield_projector/rectangle, T)
	var/full = projector.max_integrity
	projector.set_on(TRUE)
	TEST_ASSERT(projector.active, "the projector comes on")
	projector.adjust_health(-50)
	TEST_ASSERT_EQUAL(projector.get_integrity(), full - 50, "blocked hits drain the shield")
	projector.adjust_health(20)
	TEST_ASSERT_EQUAL(projector.get_integrity(), full - 30, "the shield recharges")
	projector.adjust_health(-full)
	TEST_ASSERT_EQUAL(projector.get_integrity(), 0, "the shield can be drained")
	TEST_ASSERT(!projector.active, "a drained shield overloads")
	TEST_ASSERT(!length(projector.active_shields), "an overloaded shield vanishes")
	TEST_ASSERT(!QDELETED(projector), "the projector survives an overload")
	TEST_ASSERT(!projector.create_shields(), "a drained projector can't raise a shield")
	projector.adjust_health(full)
	TEST_ASSERT_EQUAL(projector.get_integrity(), full, "a projector recharges fully")
	projector.destroy_shields()
	clear_debris(T)


/// Modular computers: chassis damage is integrity; below integrity_failure the
/// computer won't run; at zero it breaks apart.
/datum/unit_test/dq_integrity_pool/modular_computer

/datum/unit_test/dq_integrity_pool/modular_computer/Run()
	var/turf/T = scratch_turf()
	var/obj/item/modular_computer/laptop/laptop = allocate(/obj/item/modular_computer/laptop, T)
	var/full = laptop.max_integrity
	TEST_ASSERT_EQUAL(full, 200, "a laptop has 200 integrity")
	laptop.damage_computer(50, 0, TRUE, FALSE)
	TEST_ASSERT_EQUAL(laptop.get_integrity(), 150, "casing damage comes off integrity")
	TEST_ASSERT(!laptop.computer_broken(), "a scratched laptop still works")

	// Blasts hit the casing; EMPs only the components.
	laptop.ex_act(3)
	var/after_blast = laptop.get_integrity()
	TEST_ASSERT(after_blast < 150, "a blast damages the casing ([after_blast])")
	laptop.emp_act(EMP_LIGHT)
	TEST_ASSERT_EQUAL(laptop.get_integrity(), after_blast, "an EMP spares the casing")

	laptop.repair_damage(full)
	laptop.damage_computer(110, 0, TRUE, FALSE)
	TEST_ASSERT(laptop.computer_broken(), "below half integrity a laptop is broken")
	laptop.repair_damage(full)
	TEST_ASSERT(!laptop.computer_broken(), "a repaired laptop works again")

	laptop.damage_computer(full, 0, TRUE, FALSE)
	TEST_ASSERT(QDELETED(laptop), "a laptop at zero integrity breaks apart")
	TEST_ASSERT(locate_on(T, /obj/item/stack/material/steel), "a broken laptop leaves scrap")
	clear_debris(T)


/// Computer hardware: below integrity_failure a part fails; at zero it is wrecked but kept.
/datum/unit_test/dq_integrity_pool/computer_hardware

/datum/unit_test/dq_integrity_pool/computer_hardware/Run()
	var/obj/item/computer_hardware/processor_unit/part = allocate(/obj/item/computer_hardware/processor_unit)
	part.take_damage(30, BRUTE, null, FALSE)
	TEST_ASSERT_EQUAL(part.get_integrity_damage(), 30, "hardware damage comes off integrity")
	TEST_ASSERT(!part.hardware_failed(), "a scratched part still works")
	part.take_damage(30, BRUTE, null, FALSE)
	TEST_ASSERT(part.hardware_failed(), "below half integrity a part fails")
	TEST_ASSERT(!part.check_functionality(), "a failed part doesn't function")
	part.take_damage(100, BRUTE, null, FALSE)
	TEST_ASSERT(!QDELETED(part), "a wrecked part stays a part")
	part.repair_damage(part.max_integrity)
	TEST_ASSERT(!part.hardware_failed(), "nanopaste-style repair restores the part")


/// Material weapons: integrity is the material's (in wear units); use wears it;
/// fragile things shatter and dull-able things dull at zero; whetstones repair.
/datum/unit_test/dq_integrity_pool/material_weapon

/datum/unit_test/dq_integrity_pool/material_weapon/Run()
	var/turf/T = scratch_turf()
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife, T)
	TEST_ASSERT_EQUAL(knife.max_integrity, max(1, round(knife.material.integrity / 10)) * MATERIAL_WEAR_UNIT, "a weapon's integrity is its material's")
	knife.material_wear(MATERIAL_WEAR_UNIT)
	TEST_ASSERT_EQUAL(knife.get_integrity_damage(), MATERIAL_WEAR_UNIT, "a blow wears one unit")
	knife.repair_damage(MATERIAL_WEAR_UNIT)
	TEST_ASSERT_EQUAL(knife.get_integrity_damage(), 0, "a whetstone repairs the wear")

	knife.fragile = FALSE
	knife.can_dull = TRUE
	knife.sharp = TRUE
	knife.material_wear(knife.get_integrity())
	TEST_ASSERT(knife.dulled, "a worn-out blade goes dull")
	TEST_ASSERT(!knife.sharp, "a dull blade loses its edge")
	TEST_ASSERT(!QDELETED(knife), "a dulled blade survives")

	var/obj/item/material/knife/glass = allocate(/obj/item/material/knife, T)
	glass.fragile = TRUE
	glass.material_wear(glass.get_integrity())
	TEST_ASSERT(QDELETED(glass), "a fragile weapon shatters at zero")
	clear_debris(T)


/// Material armour: the armour's integrity is its material's; worn to zero it shatters.
/datum/unit_test/dq_integrity_pool/material_armor

/datum/unit_test/dq_integrity_pool/material_armor/Run()
	var/turf/T = scratch_turf()
	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest, T)
	vest.set_material(MAT_STEEL)
	TEST_ASSERT_EQUAL(vest.max_integrity, max(1, round(vest.material.integrity / 10)) * MATERIAL_WEAR_UNIT, "material armour's integrity is its material's")
	vest.take_damage(MATERIAL_WEAR_UNIT, BRUTE, null, FALSE)
	TEST_ASSERT_EQUAL(vest.get_integrity_damage(), MATERIAL_WEAR_UNIT, "hits wear the armour")
	vest.repair_damage(MATERIAL_WEAR_UNIT)
	TEST_ASSERT_EQUAL(vest.get_integrity_damage(), 0, "armour repairs")
	vest.take_damage(vest.max_integrity, BRUTE, null, FALSE)
	TEST_ASSERT(QDELETED(vest), "material armour worn to zero shatters")
	clear_debris(T)


/// Ashtrays and barbed wire keep their scales in wear units.
/datum/unit_test/dq_integrity_pool/material_misc

/datum/unit_test/dq_integrity_pool/material_misc/Run()
	var/turf/T = scratch_turf()
	var/obj/item/material/barbedwire/wire = allocate(/obj/item/material/barbedwire, T)
	TEST_ASSERT_EQUAL(wire.max_integrity, max(1, round(wire.material.integrity / 3)) * MATERIAL_WEAR_UNIT, "barbed wire has a third of its material's integrity")
	wire.material_wear(wire.get_integrity())
	TEST_ASSERT(QDELETED(wire), "worn-out barbed wire breaks")

	var/obj/item/material/ashtray/glass/ashtray = allocate(/obj/item/material/ashtray/glass, T)
	ashtray.material_wear(MATERIAL_WEAR_UNIT)
	TEST_ASSERT_EQUAL(ashtray.get_integrity_damage(), MATERIAL_WEAR_UNIT, "a knock wears the ashtray")
	ashtray.repair_damage(MATERIAL_WEAR_UNIT)
	TEST_ASSERT_EQUAL(ashtray.get_integrity_damage(), 0, "ashtrays repair")
	ashtray.material_wear(ashtray.get_integrity())
	TEST_ASSERT(QDELETED(ashtray), "a broken ashtray shatters")
	clear_debris(T)


/// Smoleworld buildings: three stomps flatten one into ruins.
/datum/unit_test/dq_integrity_pool/smolebuilding

/datum/unit_test/dq_integrity_pool/smolebuilding/Run()
	var/turf/T = scratch_turf()
	var/obj/structure/smolebuilding/building = allocate(/obj/structure/smolebuilding, T)
	building.take_damage(25, BRUTE, MELEE, FALSE)
	building.take_damage(25, BRUTE, MELEE, FALSE)
	TEST_ASSERT_EQUAL(building.get_integrity(), 25, "each stomp takes a third")
	building.repair_damage(25)
	TEST_ASSERT_EQUAL(building.get_integrity(), 50, "buildings repair")
	building.take_damage(50, BRUTE, MELEE, FALSE)
	TEST_ASSERT(QDELETED(building), "a flattened building is gone")
	TEST_ASSERT(locate_on(T, /obj/structure/smoleruins), "it leaves ruins")
	clear_debris(T)


/// Mech components: condition is integrity; a wrecked component stays installed.
/datum/unit_test/dq_integrity_pool/mech_component

/datum/unit_test/dq_integrity_pool/mech_component/Run()
	var/obj/item/mecha_parts/component/hull/hull = allocate(/obj/item/mecha_parts/component/hull)
	var/full = hull.max_integrity
	TEST_ASSERT_EQUAL(hull.get_efficiency(), 1, "an intact hull is fully efficient")
	hull.damage_part(full * 0.75)
	TEST_ASSERT_EQUAL(hull.get_integrity(), full * 0.25, "component damage comes off integrity")
	TEST_ASSERT(hull.get_efficiency() < 1, "a damaged hull loses efficiency")
	hull.damage_part(full)
	TEST_ASSERT_EQUAL(hull.get_integrity(), 0, "a component can be wrecked")
	TEST_ASSERT(!QDELETED(hull), "a wrecked component stays")
	hull.adjust_integrity(full)
	TEST_ASSERT_EQUAL(hull.get_integrity(), full, "nanopaste repairs components")


/// Mechs: a damage packet lands through the mech's own absorption and component model.
/datum/unit_test/dq_integrity_pool/mech_packet

/datum/unit_test/dq_integrity_pool/mech_packet/Run()
	var/turf/T = scratch_turf()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	// Mechs deflect hits at random (the armour plates' deflect_chance); pin it to zero so
	// the packet always lands.
	var/obj/item/mecha_parts/component/armor/armour = mech.internal_components[MECH_ARMOR]
	if(armour)
		armour.deflect_chance = 0
	var/before = mech.get_integrity()
	var/applied = mech.deal_damage(DAMAGE_BLUNT, 40, MELEE, flags = DAMAGE_PACKET_SILENT)
	TEST_ASSERT(mech.get_integrity() < before, "a blunt packet damages the mech ([before] -> [mech.get_integrity()])")
	TEST_ASSERT(dq_near(applied, before - mech.get_integrity(), 0.01), "the sink reports what it applied")
	var/obj/item/projectile/P = allocate(/obj/item/projectile)
	P.damage = 30
	TEST_ASSERT_EQUAL(mech.projectile_damage(P, null), 0, "rounds go through the mech body plan, not the generic adapter")
	clear_debris(T)

/// A casual click with a held item must not flatten a smole building; harm intent still hurts it.
/datum/unit_test/dq_integrity_pool/smolebuilding_item_gate

/datum/unit_test/dq_integrity_pool/smolebuilding_item_gate/Run()
	var/turf/T = scratch_turf()
	var/obj/structure/smolebuilding/building = allocate(/obj/structure/smolebuilding, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/card/id/card = allocate(/obj/item/card/id)
	H.put_in_hands(card)
	H.set_use_stance(I_HELP)
	var/datum/op_result/calm = test_click(H, building, card)
	TEST_ASSERT(!QDELETED(building), "a help-intent click with a card leaves the building standing")
	TEST_ASSERT(calm && calm.outcome == ACT_REFUSED && calm.reason == MSG(harm_click_only), "a help-intent click with a card is refused with the harm-intent reason (got [calm?.outcome] [calm?.reason])")
	H.set_use_stance(I_HURT)
	var/datum/op_result/hit = test_click(H, building, card)
	TEST_ASSERT(hit && findtext("[hit.key]", "smolebuilding_item") && hit.outcome == ACT_COMMITTED, "a harm-intent click with a card is the smash op, which outranks the actor's own melee (got [hit?.key] [hit?.outcome] [hit?.reason])")
	clear_debris(T)

/// The supermatter wall: an empty hand touches it (and is dusted), a held item is consumed only on harm intent, and any other click with an item is refused
/// (the player is not dusted: the item op answers before the bare-hand touch).
/datum/unit_test/dq_integrity_pool/supermatter_wall_item_gate

/datum/unit_test/dq_integrity_pool/supermatter_wall_item_gate/Run()
	var/turf/T = scratch_turf()
	var/start = T.type
	var/mob/living/carbon/human/bare = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/helper = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/striker = allocate(/mob/living/carbon/human, T)
	var/turf/unsimulated/wall/supermatter/wall = T.ChangeTurf(/turf/unsimulated/wall/supermatter)
	var/obj/item/card/id/calm_card = allocate(/obj/item/card/id)
	var/obj/item/card/id/hard_card = allocate(/obj/item/card/id)
	bare.set_use_stance(I_HELP)
	var/datum/op_result/empty = test_click(bare, wall, null)
	var/bare_dusted = QDELETED(bare) || bare.loc != T
	helper.put_in_hands(calm_card)
	helper.set_use_stance(I_HELP)
	var/datum/op_result/calm = test_click(helper, wall, calm_card)
	var/helper_safe = !QDELETED(helper) && helper.loc == T
	var/calm_kept = !QDELETED(calm_card)
	striker.put_in_hands(hard_card)
	striker.set_use_stance(I_HURT)
	var/datum/op_result/hard = test_click(striker, wall, hard_card)
	var/hard_consumed = QDELETED(hard_card)
	var/striker_safe = !QDELETED(striker) && striker.loc == T
	var/empty_key = empty ? "[empty.key]" : ""
	var/calm_outcome = calm ? calm.outcome : null
	var/calm_reason = calm ? calm.reason : null
	var/hard_key = hard ? "[hard.key]" : ""
	wall.ChangeTurf(start)
	TEST_ASSERT(findtext(empty_key, "supermatter_wall_hand"), "an empty hand touches the wall (got [empty_key])")
	TEST_ASSERT(bare_dusted, "the bare-hand touch still dusts the toucher")
	TEST_ASSERT(calm_outcome == ACT_REFUSED && calm_reason == MSG(harm_click_only), "a help-intent click with an item is refused with the harm-intent reason (got [calm_outcome] [calm_reason])")
	TEST_ASSERT(helper_safe, "a help-intent click with an item does NOT dust the player")
	TEST_ASSERT(calm_kept, "a help-intent click with an item leaves the item intact")
	TEST_ASSERT(findtext(hard_key, "supermatter_wall_item"), "a harm-intent click with an item is the item op (got [hard_key])")
	TEST_ASSERT(hard_consumed, "a harm-intent click with an item consumes it")
	TEST_ASSERT(striker_safe, "a harm-intent item touch does not dust the player")
