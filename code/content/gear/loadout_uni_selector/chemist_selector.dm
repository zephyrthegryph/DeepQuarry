/datum/gear/uniform/chemist_selector
	display_name = "Medical - " + JOB_CHEMIST + "'s Uniforms"
	description = "Select from a range of outfits available to all Chemists."
	allowed_roles = list(JOB_CHIEF_MEDICAL_OFFICER,JOB_CHEMIST)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/neo_chem
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/chemist_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/chemist/skirt,
		"TG&C chemist's jumpsuit"=/obj/item/clothing/under/rank/neo_chem,
		"TG&C chemist's jumpskirt"=/obj/item/clothing/under/rank/neo_chem_skirt,
		"TG&C pharmacy jumpsuit"=/obj/item/clothing/under/rank/neo_pharma,
		"TG&C pharmacy jumpskirt"=/obj/item/clothing/under/rank/neo_pharma_skirt
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
