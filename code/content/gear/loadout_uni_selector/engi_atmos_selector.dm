/datum/gear/uniform/engi_atmos_selector
	display_name = "Engineering - Atmos Tech's Uniforms"
	description = "Select from a range of outfits available to all Atmospherics Technicians."
	allowed_roles = list(JOB_CHIEF_ENGINEER,JOB_ATMOSPHERIC_TECHNICIAN)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/atmospheric_technician/skirt
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/engi_atmos_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/atmospheric_technician/skirt,
		"TG&C jumpsuit"=VARIANT(/obj/item/clothing/under/rank/neo_atmos),
		"TG&C jumpskirt"=VARIANT(/obj/item/clothing/under/rank/neo_atmos_skirt)
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
