// The decl ratchet burn-down (tools/ci/decl_baseline.txt): holders whose Initialize() used to make a child by hand now declare it
// (owns_one / owns_many with starts =, gas_store()). Each converted holder is made and its child checked.

/// Each holder starts with the declared child in the var (type, var name, the type the child is).
/datum/unit_test/dq_decl_starts/Run()
	var/turf/T = dq_containment_floor()
	var/list/cases = list(
		list(/obj/machinery/firealarm, "soundloop", /datum/looping_sound/alarm/fire_alarm),
		list(/obj/machinery/firealarm, "causality", /datum/looping_sound/alarm/sm_causality_alarm),
		list(/obj/machinery/microwave, "soundloop", /datum/looping_sound/microwave),
		list(/obj/machinery/exonet_node, "soundloop", /datum/looping_sound/tcomms),
		list(/obj/machinery/atmospherics/binary/algae_farm, "internal", /datum/gas_mixture),
		list(/obj/machinery/bomb_tester, "faketank", /datum/gas_mixture),
		list(/obj/structure/drop_pod, "air", /datum/gas_mixture/pod_air),
		list(/obj/machinery/camera, "assembly", /obj/item/camera_assembly),
		list(/obj/machinery/computer/security, "camera", /datum/tgui_module/camera),
		list(/obj/machinery/computer/station_alert, "alarm_monitor", /datum/tgui_module/alarm_monitor),
		list(/obj/machinery/requests_console, "announcement", /datum/announcement),
		list(/obj/item/mecha_parts/mecha_equipment/combat_shield, "my_shield", /obj/item/shield_projector),
		list(/obj/structure/mob_spawner/scanner, "prox", /datum/proximity_monitor/mobspawner),
		list(/obj/structure/mirror, "M", /datum/tgui_module/appearance_changer/mirror),
		list(/obj/item/anomaly_neutralizer, "effect_remover", /datum/effect_remover),
		list(/obj/item/instrument/violin, "song", /datum/song/handheld),
		list(/obj/machinery/ore_silo, "materials", /datum/material_container),
		list(/obj/item/melee/baton/slime/loaded, "bcell", /obj/item/cell/device),
		list(/obj/item/rig_module/device/stamp, "device", /obj/item/stamp/internalaffairs),
		list(/obj/item/rig_module/device/stamp, "spare_stamp", /obj/item/stamp/denied),
	)
	for(var/list/C in cases)
		var/path = C[1]
		if(!C[3])
			continue
		var/datum/D = allocate(path, T)
		var/datum/child = D.vars[C[2]]
		TEST_ASSERT(istype(child, C[3]), "[path] starts with [C[2]] = [C[3]] (got [isdatum(child) ? child.type : child])")

/// gas_store(pressure =): a pressure tank fills its declared gas to its own start_pressure (a subtype's map value included).
/datum/unit_test/dq_decl_starts_tank_pressure/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/atmospherics/pipe/tank/oxygen/O = allocate(/obj/machinery/atmospherics/pipe/tank/oxygen, T)
	TEST_ASSERT(istype(O.air_temporary, /datum/gas_mixture), "the tank starts with its air")
	var/expected = O.start_pressure * O.volume / (R_IDEAL_GAS_EQUATION * T20C)
	TEST_ASSERT(abs(O.air_temporary.get_moles(GAS_O2) - expected) < 0.01, "its oxygen at start_pressure")
	var/obj/machinery/atmospherics/pipe/tank/air/full/A = allocate(/obj/machinery/atmospherics/pipe/tank/air/full, T)
	var/n2 = A.start_pressure * N2STANDARD * A.volume / (R_IDEAL_GAS_EQUATION * T20C)
	TEST_ASSERT(abs(A.air_temporary.get_moles(GAS_N2) - n2) < 0.01, "a /full tank fills to its own start_pressure")
