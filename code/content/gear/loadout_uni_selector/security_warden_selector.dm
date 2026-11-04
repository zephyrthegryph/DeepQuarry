/datum/gear/uniform/security_warden_selector
	display_name = "Security - "+ JOB_WARDEN + "'s Uniforms"
	description = "Select from a range of outfits available to Wardens."
	allowed_roles = list(JOB_HEAD_OF_SECURITY,JOB_WARDEN)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/warden/corp
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/security_warden_selector/New()
	..()
	var/list/selector_uniforms = list(
		"skirt"=/obj/item/clothing/under/rank/warden/skirt,
		"corporate"=/obj/item/clothing/under/rank/warden/corp,
		"formal, navy"=/obj/item/clothing/under/rank/warden/navyblue,
		"formal, tan"=/obj/item/clothing/under/rank/warden/navyblue,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_warden_red,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_warden_red_skirt,
		"TG&C blue jumpsuit"=/obj/item/clothing/under/rank/neo_warden_blue
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
