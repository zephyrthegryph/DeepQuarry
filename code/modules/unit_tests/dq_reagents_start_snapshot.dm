/**
 * The starting reagents of every type that declares a reagent holder (reagents() in CAPABILITIES; before, the DECLARE_REAGENTS
 * family), pinned per declaring root: one row per type in typesof(root), "type vol=N id=amount,...". Made at the end of a fresh
 * Initialize(), so it is what the declaration (and the type's own code after ..()) put in. Recorded on the legacy code before the
 * codemod (doc/rewrite/reagents.md "Pins"); a conversion that changes a row fails here.
 * Rows: code/modules/unit_tests/snapshots/reagents_start/<root>.txt. Re-record: bash tools/dq_focused_test.sh --bless dq_reagents_start_snapshot
 */
/datum/unit_test/dq_reagents_start_snapshot

/// Roots whose subtrees are pinned.
/datum/unit_test/dq_reagents_start_snapshot/proc/roots()
	return list(
		/mob/living/simple_mob/animal/passive/fish/koi/poisonous,
		/obj/distilling_tester,
		/obj/effect/decal/cleanable/chemcoating,
		/obj/effect/effect/smoke/chem,
		/obj/item/blobcore_chunk,
		/obj/item/clothing/accessory/ring/reagent,
		/obj/item/clothing/mask/chewable,
		/obj/item/clothing/mask/smokable,
		/obj/item/extinguisher,
		/obj/item/grenade/chem_grenade,
		/obj/item/grown,
		/obj/item/implant/reagent_generator,
		/obj/item/integrated_circuit/passive/power/chemical_cell,
		/obj/item/material/kitchen/utensil,
		/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun,
		/obj/item/mop,
		/obj/item/mop_deploy,
		/obj/item/organ,
		/obj/item/pen/reagent,
		/obj/item/reagent_containers,
		/obj/item/slime_extract,
		/obj/item/soap,
		/obj/machinery/atmospherics/unary/freezer,
		/obj/machinery/atmospherics/unary/heater,
		/obj/machinery/bunsen_burner,
		/obj/machinery/chemical_synthesizer,
		/obj/machinery/icecream_vat,
		/obj/machinery/material_furnace,
		/obj/machinery/portable_atmospherics/hydroponics,
		/obj/machinery/portable_atmospherics/powered/reagent_distillery,
		/obj/machinery/power/fusion_core,
		/obj/machinery/pump,
		/obj/machinery/pump_relay,
		/obj/machinery/radiocarbon_spectrometer,
		/obj/machinery/shower,
		/obj/machinery/smart_centrifuge,
		/obj/machinery/v_garbosystem,
		/obj/structure/bed/bath,
		/obj/structure/mopbucket,
		/obj/structure/reagent_dispensers,
		/obj/vehicle/train/engine/janicart,
		/obj/vehicle/train/trolley_tank,
	)

/// The row of one fresh instance of `type`.
/proc/dq_reagents_start_row(atom/A)
	var/datum/reagents/R = A.reagents
	if(!R)
		return "[A.type] none"
	var/list/parts = list()
	for(var/datum/reagent/reagent as anything in R.reagent_list)
		parts += "[reagent.id]=[round(reagent.volume, 0.001)]"
	sortTim(parts, GLOBAL_PROC_REF(cmp_text_asc))
	return "[A.type] vol=[R.maximum_volume] holder=[R.type] [jointext(parts, ",")]"

/datum/unit_test/dq_reagents_start_snapshot/Run()
	var/turf/T = dq_containment_floor()
	var/dir = "[DQ_SNAPSHOT_ROOT]reagents_start/"
	var/list/bad = list()
	var/list/expected = dq_snapshot_read_dir(dir, bad)
	var/list/actual = list()
	for(var/root in roots())
		var/list/rows = list()
		for(var/type in typesof(root))
			rand_seed(1) // a type that rolls its contents (random vials, old food, flavoured gum) rolls the same way whatever ran before it
			var/atom/A
			try
				if(ispath(type, /obj/item/reagent_containers/food/snacks/grown))
					var/list/seeds = SSplants.seeds
					A = allocate(type, T, length(seeds) ? seeds[1] : null)
				else
					A = allocate(type, T)
			catch
				rows += "[type] runtime" // the type's own Initialize() fails outside a body; its reagents are not pinned here
				continue
			if(QDELETED(A))
				rows += "[type] deleted"
				continue
			rows += dq_reagents_start_row(A)
			qdel(A)
		actual[root] = rows
	var/failure = dq_snapshot_compare(dir, "reagents_start", actual, expected, bad)
	TEST_ASSERT(isnull(failure), failure)
