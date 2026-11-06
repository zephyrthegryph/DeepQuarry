/obj/item/borg/upgrade/advanced/advhealth
	name = "advanced health analyzer module"
	desc = "An Advanced Health Analyzer, optimized for borg mounting."
	icon_state = "cyborg_upgrade3"
	item_state = "cyborg_upgrade"
	require_module = TRUE

/obj/item/borg/upgrade/advanced/advhealth/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE

	if(is_installed(R))
		generic_error(user, R, type)
		return FALSE

	R.module.modules += new/obj/item/healthanalyzer/advanced(R.module)
	to_chat(R, span_notice("Advanced health analyzer initialized!"))
	return TRUE
