// Upgrade detection. Each upgrade knows how to tell whether it is already in a
// robot (is_installed) and whether the part it modifies is missing
// (host_missing). This replaces the robot's has_*_upgrade type ladders.

/// Is this upgrade already applied to `R`?
/obj/item/borg/upgrade/proc/is_installed(mob/living/silicon/robot/R)
	return FALSE

/// Is the module item this upgrade modifies missing from `R`? (Analyzer ERROR.)
/obj/item/borg/upgrade/proc/host_missing(mob/living/silicon/robot/R)
	return FALSE

/// A shared, never-used instance per upgrade type, for detection by type
/// (analyzers, admin tools).
/proc/robot_upgrade_prototype(upgrade_type)
	var/static/list/prototypes = list()
	if(!ispath(upgrade_type, /obj/item/borg/upgrade))
		return null
	var/obj/item/borg/upgrade/proto = prototypes[upgrade_type]
	if(!proto)
		proto = new upgrade_type(null)
		prototypes[upgrade_type] = proto
	return proto

// --- Basic: robot variables -----------------------------------------------------------------

/obj/item/borg/upgrade/basic/vtec/is_installed(mob/living/silicon/robot/R)
	return (/mob/living/silicon/robot/proc/toggle_vtec in R.verbs)

/obj/item/borg/upgrade/basic/sizeshift/is_installed(mob/living/silicon/robot/R)
	return (/mob/living/proc/set_size in R.verbs)

/obj/item/borg/upgrade/basic/syndicate/is_installed(mob/living/silicon/robot/R)
	return R.emag_items

/obj/item/borg/upgrade/basic/language/is_installed(mob/living/silicon/robot/R)
	return length(R.speech_synthesizer_langs) > 20 // Service with the most has 18

// --- Advanced ---------------------------------------------------------------------------------

/obj/item/borg/upgrade/advanced/bellysizeupgrade/host_missing(mob/living/silicon/robot/R)
	return !R.has_upgrade_module(/obj/item/dogborg/sleeper)

/obj/item/borg/upgrade/advanced/bellysizeupgrade/is_installed(mob/living/silicon/robot/R)
	var/obj/item/dogborg/sleeper/T = R.has_upgrade_module(/obj/item/dogborg/sleeper)
	return T?.upgraded_capacity

/obj/item/borg/upgrade/advanced/jetpack/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/tank/jetpack/carbondioxide)

/obj/item/borg/upgrade/advanced/advhealth/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/healthanalyzer/advanced)

/obj/item/borg/upgrade/advanced/sizegun/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/gun/energy/sizegun/mounted)

// --- Restricted -------------------------------------------------------------------------------

/obj/item/borg/upgrade/restricted/bellycapupgrade/host_missing(mob/living/silicon/robot/R)
	return !R.has_upgrade_module(/obj/item/dogborg/sleeper)

/obj/item/borg/upgrade/restricted/bellycapupgrade/is_installed(mob/living/silicon/robot/R)
	var/obj/item/dogborg/sleeper/T = R.has_upgrade_module(/obj/item/dogborg/sleeper)
	return T?.compactor

/obj/item/borg/upgrade/restricted/tasercooler/host_missing(mob/living/silicon/robot/R)
	return !R.has_upgrade_module(/obj/item/gun/energy/robotic/taser)

/obj/item/borg/upgrade/restricted/tasercooler/is_installed(mob/living/silicon/robot/R)
	var/obj/item/gun/energy/robotic/taser/T = R.has_upgrade_module(/obj/item/gun/energy/robotic/taser)
	return T && T.recharge_time < T::recharge_time

/obj/item/borg/upgrade/restricted/adv_scanner/host_missing(mob/living/silicon/robot/R)
	return !R.has_upgrade_module(/obj/item/mining_scanner/robot)

/obj/item/borg/upgrade/restricted/adv_scanner/is_installed(mob/living/silicon/robot/R)
	var/obj/item/mining_scanner/robot/robot_scanner = R.has_upgrade_module(/obj/item/mining_scanner/robot)
	return robot_scanner?.exact

/obj/item/borg/upgrade/restricted/adv_snatcher/host_missing(mob/living/silicon/robot/R)
	return !R.has_upgrade_module(/obj/item/storage/bag/sheetsnatcher/borg)

/obj/item/borg/upgrade/restricted/adv_snatcher/is_installed(mob/living/silicon/robot/R)
	var/obj/item/storage/bag/sheetsnatcher/borg/robot_snatcher = R.has_upgrade_module(/obj/item/storage/bag/sheetsnatcher/borg)
	return robot_snatcher && robot_snatcher.capacity > robot_snatcher::capacity

/obj/item/borg/upgrade/restricted/adv_mailbag/host_missing(mob/living/silicon/robot/R)
	return !R.has_upgrade_module(/obj/item/storage/bag/mail/borg)

/obj/item/borg/upgrade/restricted/adv_mailbag/is_installed(mob/living/silicon/robot/R)
	var/obj/item/storage/bag/mail/borg/letter_bag = R.has_upgrade_module(/obj/item/storage/bag/mail/borg)
	return letter_bag && letter_bag.storage_slots > letter_bag::storage_slots

/obj/item/borg/upgrade/restricted/advrped/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/storage/part_replacer/adv)

/obj/item/borg/upgrade/restricted/diamonddrill/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/pickaxe/diamonddrill)

/obj/item/borg/upgrade/restricted/pka/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/gun/energy/kinetic_accelerator/cyborg)

// --- Non-production ---------------------------------------------------------------------------

/obj/item/borg/upgrade/no_prod/toygun/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/gun/projectile/cyborgtoy)

/obj/item/borg/upgrade/no_prod/vision_xray/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/borg/sight/xray)

/obj/item/borg/upgrade/no_prod/vision_thermal/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/borg/sight/thermal)

/obj/item/borg/upgrade/no_prod/vision_meson/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/borg/sight/meson)

/obj/item/borg/upgrade/no_prod/vision_material/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/borg/sight/material)

/obj/item/borg/upgrade/no_prod/vision_anomalous/is_installed(mob/living/silicon/robot/R)
	return !!R.has_upgrade_module(/obj/item/borg/sight/anomalous)
