//cyborg foam dart gun
/obj/item/borg/upgrade/no_prod/toygun
	name = "Donk-Soft " + JOB_CYBORG + " Blaster module" //Cyborg Blaster is capitalized because it's the brand name
	desc = "A foam dart gun designed for mounting into cyborgs. It's Donk or Don't! DISCLAIMER: Donk-Soft bears no responsibility for incidents relating to cyborgs becoming too accustomed to shooting at crew. Installation of the Donk-Soft Cyborg Blaster must be performed only by a licensed roboticist."
	icon_state = "cyborg_upgrade5"
	item_state = "cyborg_upgrade"
	require_module = TRUE

/obj/item/borg/upgrade/no_prod/toygun/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(is_installed(R))
		generic_error(user, R, type)
		return FALSE

	R.module.modules += new/obj/item/gun/projectile/cyborgtoy(R.module)
	return TRUE
