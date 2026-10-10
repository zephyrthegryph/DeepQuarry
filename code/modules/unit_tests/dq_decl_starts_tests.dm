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

/// Looks rolled before init (rolls()) instead of drawn from the world RNG in Initialize(): each lands in its type's set.
/datum/unit_test/dq_decl_rolled_looks/Run()
	var/turf/T = dq_containment_floor()
	var/list/cases = list(
		/obj/structure/flora/ausbushes/sunnybush = "sunnybush_",
		/obj/structure/flora/ausbushes/reedbush = "reedbush_",
		/obj/structure/flora/mushroom = "mush",
		/obj/structure/flora/tree/pine = "pine_",
		/obj/item/reagent_containers/food/snacks/nugget = "nugget_",
		/obj/structure/salvageable/personal = "personal",
	)
	for(var/path in cases)
		var/atom/A = allocate(path, T)
		TEST_ASSERT(findtext(A.icon_state, cases[path]) == 1, "[path] rolls a look starting [cases[path]] (got [A.icon_state])")
	var/obj/structure/noticeboard/medical/board = allocate(/obj/structure/noticeboard/medical, T)
	var/obj/item/paper/P = locate() in board
	TEST_ASSERT(length(P?.stamp_marks), "a noticeboard's memo carries its stamp as a stamp mark")

/// reagents() and typed fills replace create_reagents() / add_reagent() in Initialize().
/datum/unit_test/dq_decl_reagent_fills/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/microwave/MW = allocate(/obj/machinery/microwave, T)
	TEST_ASSERT(MW.reagents?.my_atom == MW, "the microwave has its reagent holder (its parts then size it)")
	var/obj/item/grenade/chem_grenade/frost/G = allocate(/obj/item/grenade/chem_grenade/frost, T)
	TEST_ASSERT_EQUAL(length(G.beakers), 2, "the frost grenade starts with two beakers")
	var/obj/item/reagent_containers/B = G.beakers[1]
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_CRYOSLURRY), 150, "its first beaker holds the cryoslurry")
	var/obj/item/mecha_parts/mecha_equipment/tool/extinguisher/E = allocate(/obj/item/mecha_parts/mecha_equipment/tool/extinguisher, T)
	TEST_ASSERT_EQUAL(E.reagents.get_reagent_amount(REAGENT_ID_FIREFOAM), E.max_water, "the exosuit extinguisher starts full of foam")

/// Starting children made by a starts = PROC_REF (a constructor that needs the holder's state, a list of them).
/datum/unit_test/dq_decl_starts_procs/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/appliance/cooker/oven/O = allocate(/obj/machinery/appliance/cooker/oven, T)
	TEST_ASSERT_EQUAL(length(O.cooking_objs), O.max_contents, "a cooker starts with one cooking slot per max_contents")
	var/obj/machinery/appliance/mixer/candy/M = allocate(/obj/machinery/appliance/mixer/candy, T)
	TEST_ASSERT_EQUAL(length(M.cooking_objs), 1, "a mixer starts with its one slot")
	var/obj/machinery/cablelayer/C = allocate(/obj/machinery/cablelayer, T)
	TEST_ASSERT_EQUAL(C.cable?.get_amount(), C.max_cable, "the cable layer starts full")
	var/obj/structure/bed/pillowpile/P = allocate(/obj/structure/bed/pillowpile, T)
	TEST_ASSERT(P.front?.pile == P, "a pillow pile starts with its front, which knows its pile")
	var/obj/machinery/mining/drill/D = allocate(/obj/machinery/mining/drill, T)
	TEST_ASSERT(istype(D.faultreporter, /obj/item/radio/intercom), "a drill starts with its fault reporter")

/// Subtype-declared starting children and holders: uplinks, the refinery's holder type, the fryer's oil, a full grower pod.
/datum/unit_test/dq_decl_starts_subtypes/Run()
	var/turf/T = dq_containment_floor()
	for(var/path in list(/obj/item/radio/uplink, /obj/item/multitool/uplink, /obj/item/radio/headset/uplink, /obj/item/implant/uplink))
		var/obj/item/I = allocate(path, T)
		TEST_ASSERT(istype(I.hidden_uplink, /obj/item/uplink/hidden), "[path] starts with a hidden uplink")
	var/obj/machinery/reagent_refinery/reactor/R = allocate(/obj/machinery/reagent_refinery/reactor, T)
	TEST_ASSERT(istype(R.reagents, /datum/reagents/distilling), "the reactor's holder is its reagent_type")
	var/obj/machinery/reagent_refinery/hub/H = allocate(/obj/machinery/reagent_refinery/hub, T)
	TEST_ASSERT(isnull(H.reagents), "a hub has no holder")
	var/obj/machinery/appliance/cooker/fryer/F = allocate(/obj/machinery/appliance/cooker/fryer, T)
	TEST_ASSERT(F.oil?.get_reagent_amount(REAGENT_ID_COOKINGOIL) > 0, "the fryer starts with oil")
	var/obj/machinery/clonepod/transhuman/full/P = allocate(/obj/machinery/clonepod/transhuman/full, T)
	TEST_ASSERT_EQUAL(length(P.containers), P.container_limit, "a full grower pod starts with its biomass")

/// reagents(contents_from =) for produce: the seed's chemicals at its potency, the nutriment tasting of the plant; the wish soup's rolled wish.
/datum/unit_test/dq_decl_seed_contents/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/reagent_containers/food/snacks/grown/G = allocate(/obj/item/reagent_containers/food/snacks/grown, T, "apple")
	TEST_ASSERT(G.reagents.has_reagent(REAGENT_ID_NUTRIMENT), "an apple holds its seed's nutriment")
	var/datum/reagent/N = G.reagents.get_reagent(REAGENT_ID_NUTRIMENT)
	TEST_ASSERT(islist(N?.data) && N.data[G.seed().seed_name], "the nutriment tastes of the plant")
	var/obj/item/reagent_containers/food/snacks/wishsoup/W = allocate(/obj/item/reagent_containers/food/snacks/wishsoup, T)
	TEST_ASSERT_EQUAL(W.reagents.has_reagent(REAGENT_ID_NUTRIMENT), W.wished, "a wish soup holds nutriment exactly when its wish came true")

/// membership() and after_init() replacing registry_join() / after() in Initialize().
/datum/unit_test/dq_decl_membership_timers/Run()
	var/turf/T = dq_containment_floor()
	var/obj/effect/landmark/L = allocate(/obj/effect/landmark, T)
	TEST_ASSERT(L in REGISTRY_MEMBERS(REGISTRY_LANDMARKS), "a landmark is in the landmark registry")
	var/obj/effect/decal/cleanable/blood/B = allocate(/obj/effect/decal/cleanable/blood, T)
	TEST_ASSERT(B.dry_delay > 0, "fresh blood has a drying delay")
	var/obj/item/research_sample/S = allocate(/obj/item/research_sample, T)
	TEST_ASSERT(findtext(S.icon_state, "generic_sample") == 1, "a research sample rolls its look (got [S.icon_state])")

/// Guns and magazines load through owns_many(starts =): loose rounds, a magazine, a magazine's rounds, an artifact casing's bullet.
/datum/unit_test/dq_decl_gun_loads/Run()
	var/obj/item/storage/box/B = allocate(/obj/item/storage/box, dq_containment_floor())
	var/obj/item/ammo_magazine/m9mm/M = allocate(/obj/item/ammo_magazine/m9mm, B)
	TEST_ASSERT_EQUAL(length(M.stored_ammo) + M.latent_rounds, M.max_ammo, "a magazine starts with a full load, real or latent")
	var/obj/item/gun/projectile/revolver/R = allocate(/obj/item/gun/projectile/revolver, B)
	TEST_ASSERT_EQUAL(length(R.loaded), R.max_shells, "a revolver starts with a full cylinder")
	var/obj/item/gun/projectile/artifact/G = allocate(/obj/item/gun/projectile/artifact, B)
	for(var/obj/item/ammo_casing/artifact/C in G.loaded)
		TEST_ASSERT(istype(C.BB, G.projectile_type || /obj/item/projectile/bullet/foam_dart_riot), "an artifact casing holds its gun's bullet")

/// A vehicle cage starts with its vehicle and lets it out (not deleted) when taken apart or destroyed.
/datum/unit_test/dq_decl_vehicle_cage/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/vehiclecage/spacebike/C = allocate(/obj/structure/vehiclecage/spacebike, T)
	var/obj/vehicle/V = C.my_vehicle
	TEST_ASSERT(istype(V, /obj/vehicle/bike), "the cage starts with its bike")
	qdel(C)
	TEST_ASSERT(!QDELETED(V) && V.loc == T, "a destroyed cage puts its bike out")
	var/obj/item/integrated_circuit/reagent/storage/S = allocate(/obj/item/integrated_circuit/reagent/storage, T)
	TEST_ASSERT_EQUAL(S.reagents?.maximum_volume, S.volume, "a reagent storage circuit holds its volume")
	var/obj/item/integrated_circuit/reagent/pump/P = allocate(/obj/item/integrated_circuit/reagent/pump, T)
	TEST_ASSERT(isnull(P.reagents), "a pump circuit holds nothing")
