// Garbage-collection regression tests.
//
// Each test targets a ref-leak class that once made objects fail GC and forced
// hard del() sweeps (a full-world reference walk apiece) — 105 of them stacked
// ~30 minutes of wall time onto whatever unit test happened to be running when
// SSgarbage's check queue came due. These don't wait for the async GC pass;
// they assert the *synchronous* preconditions of collection: Destroy() really
// ran (gc_destroyed set) and the known holders really released their refs.

// Dedicated types let the test inspect SSgarbage's queues without confusing
// its objects with mapped station machinery of the same base type.
/obj/machinery/atmospherics/pipe/simple/hidden/supply/dq_gc_test

/datum/pipeline/dq_gc_test

/datum/pipe_network/dq_gc_test

// Destroy a real pipe -> pipeline -> network ownership chain and then yield
// beyond the filter queue.  A retained cycle is moved into GC_QUEUE_CHECK;
// clean ownership vanishes from every queue on the first collection pass.
/datum/unit_test/dq_atmos_topology_collects_without_hard_delete

/datum/unit_test/dq_atmos_topology_collects_without_hard_delete/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	TEST_ASSERT_NOTNULL(test_turf, "no turf for atmos topology GC test")
	var/obj/machinery/atmospherics/pipe/simple/hidden/supply/dq_gc_test/pipe = new(test_turf)
	dq_atmos_test_publish_rust_pipenets(list(pipe))
	var/datum/pipeline/line = pipe.parent
	var/datum/pipe_network/network = pipe.return_network()
	TEST_ASSERT_NOTNULL(line, "Rust topology did not materialize a pipeline wrapper")
	TEST_ASSERT_NOTNULL(network, "Rust topology did not materialize a pipenet wrapper")

	qdel(pipe)
	TEST_ASSERT(QDELETED(pipe), "atmos pipe Destroy() did not run")
	TEST_ASSERT(QDELETED(line), "pipeline Destroy() did not run")
	TEST_ASSERT(QDELETED(network), "pipenet Destroy() did not run")
	TEST_ASSERT_NULL(pipe.parent, "destroyed pipe retained its pipeline")
	TEST_ASSERT_NULL(line.network, "destroyed pipeline retained its pipenet")
	TEST_ASSERT_NULL(line.members, "destroyed pipeline retained its pipe members")
	TEST_ASSERT_NULL(network.line_members, "destroyed pipenet retained its pipelines")
	TEST_ASSERT_NULL(network.normal_members, "destroyed pipenet retained its machinery")
	TEST_ASSERT(!(network in SSair.networks), "destroyed pipenet remained in SSair.networks")
	TEST_ASSERT(!(network in SSair.currentrun), "destroyed pipenet remained in SSair.currentrun")

// Explosion teardown is not a one-pipe case: every member may be qdel'd in the
// same tick and each neighbour can already be inside Destroy(). Assert that the
// whole graph loses both directional node references and its shared owners.
/datum/unit_test/dq_atmos_mass_topology_teardown_breaks_all_cycles

/datum/unit_test/dq_atmos_mass_topology_teardown_breaks_all_cycles/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/obj/machinery/atmospherics/pipe/simple/hidden/supply/dq_gc_test/A = new(test_turf)
	var/obj/machinery/atmospherics/pipe/simple/hidden/supply/dq_gc_test/B = new(test_turf)
	var/obj/machinery/atmospherics/pipe/simple/hidden/supply/dq_gc_test/C = new(test_turf)
	A.node2 = B
	B.node1 = A
	B.node2 = C
	C.node1 = B
	dq_atmos_test_publish_rust_pipenets(list(A, B, C))
	var/datum/pipeline/line = A.parent
	var/datum/pipe_network/network = A.return_network()
	TEST_ASSERT_NOTNULL(line, "Rust topology did not materialize a shared pipeline wrapper")
	TEST_ASSERT_NOTNULL(network, "Rust topology did not materialize a shared pipenet wrapper")
	qdel(B)
	qdel(A)
	qdel(C)
	TEST_ASSERT(QDELETED(line), "mass pipe deletion retained its shared pipeline")
	TEST_ASSERT(QDELETED(network), "mass pipe deletion retained its shared pipenet")
	TEST_ASSERT_NULL(A.node1, "destroyed first pipe retained node1")
	TEST_ASSERT_NULL(A.node2, "destroyed first pipe retained node2")
	TEST_ASSERT_NULL(B.node1, "destroyed middle pipe retained node1")
	TEST_ASSERT_NULL(B.node2, "destroyed middle pipe retained node2")
	TEST_ASSERT_NULL(C.node1, "destroyed final pipe retained node1")
	TEST_ASSERT_NULL(C.node2, "destroyed final pipe retained node2")

// Deleting a human must Destroy() every organ. The organs list is mutated by
// each organ's own Destroy() (self-removal + children/internal cascades), so a
// live-list iteration in /mob/living/carbon/human/Destroy skipped entries —
// skipped organs kept `owner` set and pinned the whole mob against GC.
/datum/unit_test/dq_human_deletion_destroys_all_organs

/datum/unit_test/dq_human_deletion_destroys_all_organs/Run()
	var/mob/living/carbon/human/H = new(null)
	TEST_ASSERT(length(H.organs), "freshly created human has no external organs")
	var/list/snapshot = H.organs.Copy()
	for(var/obj/item/organ/external/E as anything in H.organs)
		snapshot |= E.internal_organs
	qdel(H)
	TEST_ASSERT(QDELETED(H), "qdel(human) did not run Destroy()")
	for(var/obj/item/organ/O as anything in snapshot)
		TEST_ASSERT(QDELETED(O), "[O.type] was skipped by human deletion (Destroy never ran) — it will pin the mob against GC")
		TEST_ASSERT(isnull(O.owner), "[O.type] kept its owner ref after Destroy()")

// A medical condition qdel'd with its host organ must break the
// condition <-> symptom reference cycle (cure_issue isn't on the qdel path).
/datum/unit_test/dq_medical_condition_breaks_symptom_cycle

/datum/unit_test/dq_medical_condition_breaks_symptom_cycle/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.organs_by_name[BP_TORSO]
	TEST_ASSERT_NOTNULL(chest, "test human has no chest organ")
	var/datum/medical_issue/condition/tissue_hypoxia/C = new
	C.owner = H
	C.affectedorgan = chest
	chest.add_medical_issue(C, H)
	C.roll_symptoms()
	var/list/symptoms = C.active_symptoms?.Copy() || list()
	TEST_ASSERT(length(symptoms), "condition rolled no symptoms; cycle test is vacuous")
	qdel(C)
	TEST_ASSERT(QDELETED(C), "condition Destroy() did not run")
	TEST_ASSERT(isnull(C.owner), "condition kept its owner ref after Destroy()")
	for(var/datum/medical_symptom/S as anything in symptoms)
		TEST_ASSERT(isnull(S.source_condition), "[S.type] kept source_condition after the condition was destroyed — refcount cycle")
	chest.remove_medical_issue(C)

// Items that build an /obj/item/storage/internal must release it on Destroy —
// the un-nulled forward var was the GC pin for 22 leaked internals per run.
/datum/unit_test/dq_internal_storage_released_on_destroy

/datum/unit_test/dq_internal_storage_released_on_destroy/Run()
	// accessory webbing
	var/obj/item/clothing/accessory/storage/webbing/A = new(null)
	var/obj/item/storage/internal/ah = A.hold
	TEST_ASSERT_NOTNULL(ah, "accessory made no internal storage")
	qdel(A)
	TEST_ASSERT(QDELETED(ah), "accessory internal storage not destroyed with its master")
	TEST_ASSERT(isnull(A.hold), "accessory kept its hold ref after Destroy()")
	// PDA storage cartridge
	var/obj/item/cartridge/storage/PC = new(null)
	var/obj/item/storage/internal/ch = PC.hold
	TEST_ASSERT_NOTNULL(ch, "cartridge made no internal storage")
	qdel(PC)
	TEST_ASSERT(QDELETED(ch), "cartridge internal storage not destroyed with its master")
	// e-cig cartridge
	var/obj/item/clothing/mask/smokable/ecig/E = new(null)
	var/obj/item/reagent_containers/ecig_cartridge/ec = E.ec_cartridge
	TEST_ASSERT_NOTNULL(ec, "ecig made no cartridge")
	qdel(E)
	TEST_ASSERT(QDELETED(ec), "ecig cartridge not destroyed with its master")

// Deleting a mob with a shadekin component must not resurrect HUD objects:
// the component's Destroy() used to rebuild owner.ability_master AFTER
// /mob/Destroy had already cleared it — allocating a fresh screen atom inside
// the dying mob (my_mob ref + contents + var = immortal cycle pinning the mob).
/datum/unit_test/dq_shadekin_mob_deletion_leaves_no_hud

/datum/unit_test/dq_shadekin_mob_deletion_leaves_no_hud/Run()
	var/mob/living/carbon/human/H = new(null)
	var/datum/component/shadekin/SK = H.AddComponent(/datum/component/shadekin/phase_only)
	TEST_ASSERT_NOTNULL(SK, "shadekin component failed to attach")
	qdel(H)
	TEST_ASSERT(QDELETED(H), "mob Destroy() did not run")
	TEST_ASSERT(QDELETED(SK), "shadekin component was not destroyed with its mob")
	TEST_ASSERT(isnull(H.ability_master), "mob deletion left a resurrected ability_master screen object — immortal GC cycle")

// Deleting a container must Destroy() every item inside it — the base
// /atom/movable/Destroy contents loop had the same live-list skip hazard
// (each member's Destroy pulls it out of contents via moveToNullspace).
/datum/unit_test/dq_container_deletion_destroys_all_contents

/datum/unit_test/dq_container_deletion_destroys_all_contents/Run()
	var/obj/item/storage/box/B = new(null)
	// Ensure a healthy number of members so a skip is very likely to manifest.
	for(var/i in 1 to 6)
		new /obj/item/pen(B)
	var/list/snapshot = B.contents.Copy()
	TEST_ASSERT(length(snapshot) >= 6, "box did not accept its contents")
	qdel(B)
	TEST_ASSERT(QDELETED(B), "box Destroy() did not run")
	for(var/atom/movable/AM as anything in snapshot)
		TEST_ASSERT(QDELETED(AM), "[AM.type] inside a deleted container was skipped by the contents qdel loop")

// Docking controllers expose typed aliases for the two programs used by their
// UI. Those aliases must not outlive the base controller's owning `program` var.
/datum/unit_test/dq_docking_controller_releases_program_aliases

/datum/unit_test/dq_docking_controller_releases_program_aliases/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/obj/machinery/embedded_controller/radio/airlock/docking_port/controller = new(test_turf)
	var/datum/embedded_program/docking/airlock/docking = controller.docking_program
	var/datum/embedded_program/airlock/docking/airlock = controller.airlock_program
	TEST_ASSERT_NOTNULL(docking, "docking controller made no docking program")
	TEST_ASSERT_NOTNULL(airlock, "docking controller made no airlock program")
	qdel(controller)
	TEST_ASSERT(QDELETED(docking), "docking program was not destroyed with its controller")
	TEST_ASSERT(QDELETED(airlock), "airlock program was not destroyed with its controller")
	TEST_ASSERT_NULL(controller.docking_program, "destroyed controller retained its docking-program alias")
	TEST_ASSERT_NULL(controller.airlock_program, "destroyed controller retained its airlock-program alias")

// Integrated-electronics cases and their internal device form an ownership
// pair. Both deletion directions must sever the pair rather than leave the two
// qdel'd objects retaining one another until a hard delete.
/datum/unit_test/dq_electronic_assembly_breaks_device_cycle

/datum/unit_test/dq_electronic_assembly_breaks_device_cycle/Run()
	var/obj/item/assembly/electronic_assembly/case = new(null)
	var/obj/item/electronic_assembly/device/device = case.EA
	TEST_ASSERT_NOTNULL(device, "electronic assembly made no internal device")
	qdel(case)
	TEST_ASSERT(QDELETED(device), "internal electronic device was not destroyed with its case")
	TEST_ASSERT_NULL(case.EA, "destroyed electronic assembly retained its internal device")
	TEST_ASSERT_NULL(device.holder, "destroyed electronic device retained its case")

// A radio whose frequency was changed must not strand itself in SSradio's
// per-frequency listener list on deletion (registered at old freq, removed at
// new). set_frequency() is the only legal way to retune.
/datum/unit_test/dq_retuned_radio_unregisters_from_ssradio

/datum/unit_test/dq_retuned_radio_unregisters_from_ssradio/Run()
	var/obj/item/radio/headset/R = new(null)
	// Retune the WRONG way a mob subtype used to (direct var write bypasses
	// re-registration)... which is now impossible to test through the public
	// API since callers were fixed — so retune correctly and assert both
	// directions of the registration moved.
	var/datum/radio_frequency/old_freq = SSradio.return_frequency(R.frequency)
	R.set_frequency(ERT_FREQ)
	if(old_freq)
		for(var/list/devices in old_freq.devices)
			TEST_ASSERT(!(R in old_freq.devices[devices]), "retuned radio still registered on its old frequency")
	var/datum/radio_frequency/new_freq = SSradio.return_frequency(ERT_FREQ)
	TEST_ASSERT_NOTNULL(new_freq, "ERT frequency datum missing after retune")
	qdel(R)
	var/found = FALSE
	for(var/filter_key in new_freq.devices)
		if(R in new_freq.devices[filter_key])
			found = TRUE
	TEST_ASSERT(!found, "deleted radio still registered in SSradio listener list — hard GC leak")
