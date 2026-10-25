/obj/item/mecha_parts/mecha_equipment/tool/orescanner
	name = "mounted ore scanner"
	desc = "An exosuit-mounted ore scanner."
	icon_state = "mecha_analyzer"
	equip_cooldown = 5
	energy_drain = 30
	range = MECH_MELEE|RANGED
	equip_type = EQUIP_SPECIAL
	ready_sound = SFX_ITEMS_GOGGLES_CHARGE
	required_type = list(/obj/mecha/working/ripley)

	var/obj/item/mining_scanner/my_scanner = null
	var/exact_scan = FALSE

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tool/orescanner)
	owns_one(nameof(my_scanner), starts = /obj/item/mining_scanner)
	op("scan", ai(), takes("spot"), wait(2 SECONDS, keeps = TARGET_PRESENT | ALIVE | STAY), then(PROC_REF(scan_done)))

/obj/item/mecha_parts/mecha_equipment/tool/orescanner/proc/scan_done(datum/act/op/A)
	var/atom/spot = A.arg("spot")
	if(QDELETED(spot))
		return OP_REFUSED
	my_scanner.ScanTurf(spot, chassis?.slot_item(MECHA_SLOT_PILOT), exact_scan)
	return OP_OK

/obj/item/mecha_parts/mecha_equipment/tool/orescanner/action(atom/target)
	if(!action_checks(target) || get_dist(chassis, target) > 5)
		return FALSE

	if(!enable_special)
		target = get_turf(chassis)

	chassis.Beam(target, "g_beam", 'icons/effects/beam.dmi', 2 SECONDS, 10, /obj/effect/ebeam, 2)

	// The beam ends itself after 2 seconds.
	perform_op(chassis?.slot_item(MECHA_SLOT_PILOT), src, "scan", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("spot" = target))

/obj/item/mecha_parts/mecha_equipment/tool/orescanner/advanced
	name = "advanced ore scanner"
	icon_state = "mecha_analyzer_adv"
	exact_scan = TRUE
