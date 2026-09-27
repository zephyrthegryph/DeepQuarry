/obj/item/mecha_parts/mecha_equipment/tool/orescanner
	name = "mounted ore scanner"
	desc = "An exosuit-mounted ore scanner."
	icon_state = "mecha_analyzer"
	equip_cooldown = 5
	energy_drain = 30
	range = MECH_MELEE|RANGED
	equip_type = EQUIP_SPECIAL
	ready_sound = 'sound/items/goggles_charge.ogg'
	required_type = list(/obj/mecha/working/ripley)

	var/obj/item/mining_scanner/my_scanner = null
	var/exact_scan = FALSE

/obj/item/mecha_parts/mecha_equipment/tool/orescanner/Initialize(mapload)
	my_scanner = new(src)
	return ..()

REF_OWNED(/obj/item/mecha_parts/mecha_equipment/tool/orescanner, "my_scanner")

/obj/item/mecha_parts/mecha_equipment/tool/orescanner/proc/scan_done(atom/target)
	my_scanner.ScanTurf(target, chassis?.slot_item(MECHA_SLOT_PILOT), exact_scan)

/obj/item/mecha_parts/mecha_equipment/tool/orescanner/action(atom/target)
	if(!action_checks(target) || get_dist(chassis, target) > 5)
		return FALSE

	if(!enable_special)
		target = get_turf(chassis)

	chassis.Beam(target, "g_beam", 'icons/effects/beam.dmi', 2 SECONDS, 10, /obj/effect/ebeam, 2)

	// The beam ends itself after 2 seconds.
	om_do_after(chassis?.slot_item(MECHA_SLOT_PILOT), 2 SECONDS, target, src, PROC_REF(scan_done), list(target), IGNORE_HELD_ITEM)

/obj/item/mecha_parts/mecha_equipment/tool/orescanner/advanced
	name = "advanced ore scanner"
	icon_state = "mecha_analyzer_adv"
	exact_scan = TRUE
