// C8a: occupant machines and mechs on slots (doc/rewrite/containment.md §10).
//
// Each converted holder gets the same conservation/parity shape: entering
// puts the occupant in a sealed, reaches_mobs slot; leaving takes them out
// again; and destroying the holder spills them (the ledger's drop policy),
// rather than hard-deleting or stranding them.

/// Puts `who` into `holder`'s occupant slot `slot_id` directly (bypassing each
/// machine's own do_after-gated entry verb, which is that machine's business,
/// not the containment wiring under test) and checks the slot's own shape.
/datum/unit_test/proc/c8a_check_occupant_slot(atom/holder, mob/living/who, slot_id)
	TEST_ASSERT(who.move_into(holder, slot_id), "[who] should be able to move into [holder]'s [slot_id] slot")
	TEST_ASSERT_EQUAL(who.loc, holder, "[who] should be inside [holder]")
	TEST_ASSERT(who in holder.slot_contents(slot_id), "[who] should be listed in [holder]'s [slot_id] slot")
	var/datum/slot_def/def = dq_path_slot_of(holder, who)
	TEST_ASSERT(def, "[holder] should report a slot definition for [who]")
	TEST_ASSERT_EQUAL(def.exposure, SLOT_EXPOSURE_SEALED, "[holder]'s occupant slot should be sealed")
	TEST_ASSERT(def.reaches_mobs, "[holder]'s occupant slot should reach the mob inside it")
	var/turf/out = get_turf(holder)
	TEST_ASSERT(holder.slot_remove(who, out), "[who] should be able to leave [holder]")
	TEST_ASSERT_EQUAL(who.loc, out, "[who] should land on [out] after leaving [holder]")

/// Destroying an occupied holder spills the occupant instead of deleting them.
/datum/unit_test/proc/c8a_check_occupant_spills_on_destroy(atom/movable/holder, mob/living/who, slot_id)
	TEST_ASSERT(who.move_into(holder, slot_id), "[who] should be able to move into [holder]'s [slot_id] slot")
	var/turf/T = get_turf(holder)
	qdel(holder)
	TEST_ASSERT(!QDELETED(who), "destroying the holder should not delete its occupant")
	TEST_ASSERT_EQUAL(who.loc, T, "the occupant should spill onto [T] when the holder is destroyed")

/datum/unit_test/dq_c8a_cryopod_occupant_slot

/datum/unit_test/dq_c8a_cryopod_occupant_slot/Run()
	var/turf/T = test_floor()
	var/obj/machinery/cryopod/pod = allocate(/obj/machinery/cryopod, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	c8a_check_occupant_slot(pod, H, OCCUPANT_SLOT_CRYOPOD)

/datum/unit_test/dq_c8a_cryopod_destroy_spills_occupant

/datum/unit_test/dq_c8a_cryopod_destroy_spills_occupant/Run()
	var/turf/T = test_floor()
	var/obj/machinery/cryopod/pod = allocate(/obj/machinery/cryopod, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	c8a_check_occupant_spills_on_destroy(pod, H, OCCUPANT_SLOT_CRYOPOD)

/datum/unit_test/dq_c8a_resleever_occupant_slot

/datum/unit_test/dq_c8a_resleever_occupant_slot/Run()
	var/turf/T = test_floor()
	var/obj/machinery/transhuman/resleever/pod = allocate(/obj/machinery/transhuman/resleever, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	c8a_check_occupant_slot(pod, H, OCCUPANT_SLOT_RESLEEVER)

/datum/unit_test/dq_c8a_implant_chair_occupant_slot

/datum/unit_test/dq_c8a_implant_chair_occupant_slot/Run()
	var/turf/T = test_floor()
	var/obj/machinery/implantchair/chair = allocate(/obj/machinery/implantchair, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	c8a_check_occupant_slot(chair, H, OCCUPANT_SLOT_IMPLANT_CHAIR)

/datum/unit_test/dq_c8a_gibber_occupant_slot

/datum/unit_test/dq_c8a_gibber_occupant_slot/Run()
	var/turf/T = test_floor()
	var/obj/machinery/gibber/G = allocate(/obj/machinery/gibber, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	c8a_check_occupant_slot(G, H, OCCUPANT_SLOT_GIBBER)

/datum/unit_test/dq_c8a_recharge_station_occupant_slot

/datum/unit_test/dq_c8a_recharge_station_occupant_slot/Run()
	var/turf/T = test_floor()
	var/obj/machinery/recharge_station/S = allocate(/obj/machinery/recharge_station, T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	// A test robot's camera would otherwise schedule a cameranet update a few
	// seconds out (update_triggers.dm); nothing here exercises camera vision,
	// and that timer can still be pending when the robot is torn down at the
	// end of this test, well after it, in an unrelated one.
	QDEL_NULL(R.camera)
	c8a_check_occupant_slot(S, R, OCCUPANT_SLOT_RECHARGE_STATION)

/datum/unit_test/dq_c8a_dna_scanner_occupant_slot

/datum/unit_test/dq_c8a_dna_scanner_occupant_slot/Run()
	var/turf/T = test_floor()
	var/obj/machinery/dna_scannernew/scanner = allocate(/obj/machinery/dna_scannernew, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	c8a_check_occupant_slot(scanner, H, OCCUPANT_SLOT_DNA_SCANNER)

/// The DNA scanner used to pass an explosion's severity into its contents
/// unconditionally (explosion_contents_severity() returning severity as-is).
/// That's now its slot's DAMAGE_BLAST share; an unarmoured scanner still
/// passes the whole severity through.
/datum/unit_test/dq_c8a_dna_scanner_blast_share

/datum/unit_test/dq_c8a_dna_scanner_blast_share/Run()
	var/turf/T = test_floor()
	var/obj/machinery/dna_scannernew/scanner = allocate(/obj/machinery/dna_scannernew, T)
	TEST_ASSERT_EQUAL(scanner.explosion_contents_severity(3), 3, "an unarmoured DNA scanner should pass an explosion's severity through to its occupant")
	TEST_ASSERT_EQUAL(scanner.explosion_contents_severity(0), 0, "no explosion means no share")

/// A holder with no declared blast share (the default) shields its occupant.
/datum/unit_test/dq_c8a_cryopod_blast_share

/datum/unit_test/dq_c8a_cryopod_blast_share/Run()
	var/turf/T = test_floor()
	var/obj/machinery/cryopod/pod = allocate(/obj/machinery/cryopod, T)
	TEST_ASSERT_EQUAL(dq_slot_blast_severity(pod, 3), 0, "a cryopod's default slot should shield its occupant from a blast")

/datum/unit_test/dq_c8a_suit_storage_occupant_slot

/datum/unit_test/dq_c8a_suit_storage_occupant_slot/Run()
	var/turf/T = test_floor()
	var/obj/machinery/suit_storage_unit/empty/SSU = allocate(/obj/machinery/suit_storage_unit/empty, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	c8a_check_occupant_slot(SSU, H, OCCUPANT_SLOT_SUIT_STORAGE)

/// Mechs: the pilot's slot is sealed, equipment sits on an external hardpoint
/// slot and cargo sits in an internal slot -- three roles that used to share
/// raw contents (containment.md §10).
/datum/unit_test/dq_c8a_mecha_pilot_slot

/datum/unit_test/dq_c8a_mecha_pilot_slot/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	c8a_check_occupant_slot(mech, H, MECHA_SLOT_PILOT)

/datum/unit_test/dq_c8a_mecha_equipment_hardpoint_slot

/datum/unit_test/dq_c8a_mecha_equipment_hardpoint_slot/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/clamp = allocate(/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp, T)
	TEST_ASSERT(clamp.can_attach(mech), "the clamp should be attachable to a bare ripley")
	clamp.attach(mech)
	TEST_ASSERT_EQUAL(clamp.loc, mech, "attached equipment should be inside the mech")
	TEST_ASSERT(clamp in mech.slot_contents(MECHA_SLOT_EQUIPMENT), "attached equipment should be listed in the mech's hardpoint slot")
	var/datum/slot_def/def = dq_path_slot_of(mech, clamp)
	TEST_ASSERT(def, "the mech should report a slot definition for its equipment")
	TEST_ASSERT_EQUAL(def.exposure, SLOT_EXPOSURE_EXTERNAL, "a mech's equipment hardpoint should be external")
	clamp.detach()
	TEST_ASSERT_EQUAL(clamp.loc, T, "detached equipment should land on the mech's turf")
	TEST_ASSERT(!(clamp in mech.equipment), "detach() should drop the equipment from the mech's equipment list")

/datum/unit_test/dq_c8a_mecha_cargo_slot

/datum/unit_test/dq_c8a_mecha_cargo_slot/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/obj/item/stack/material/steel/cargo_item = allocate(/obj/item/stack/material/steel, T)
	TEST_ASSERT(cargo_item.move_into(mech, MECHA_SLOT_CARGO), "a cargo item should be able to move into the mech's cargo slot")
	var/datum/slot_def/def = dq_path_slot_of(mech, cargo_item)
	TEST_ASSERT(def, "the mech should report a slot definition for its cargo")
	TEST_ASSERT_EQUAL(def.exposure, SLOT_EXPOSURE_INTERNAL, "a mech's cargo compartment should be internal")
