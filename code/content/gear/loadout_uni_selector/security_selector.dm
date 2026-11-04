//Security

/datum/gear/uniform/security_selector
	display_name = "Security - Basic Uniforms"
	description = "Select from a range of outfits available to all Security personnel."
	allowed_roles = list(JOB_HEAD_OF_SECURITY, JOB_WARDEN, JOB_DETECTIVE, JOB_SECURITY_OFFICER,JOB_TALON_GUARD)
	show_roles = FALSE
	path = /obj/item/clothing/under/rank/security/corp
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/security_selector/New()
	..()
	var/list/selector_uniforms = list(
		"undersuit, modernized"=/obj/item/clothing/under/rank/security/modern,
		"GE uniform"=/obj/item/clothing/under/rank/khi/sec, // KHI becomes GE
		"voidsuit underlayer"=/obj/item/clothing/under/undersuit/sec,
		"skirt"=/obj/item/clothing/under/rank/security/skirt,
		"turtleneck"=/obj/item/clothing/under/rank/security/turtleneck,
		"corporate"=/obj/item/clothing/under/rank/security/corp,
		"formal, navy"=/obj/item/clothing/under/rank/security/navyblue,
		"formal, tan"=/obj/item/clothing/under/rank/security/tan,
		"Proxima Centauri Risk Control"=/obj/item/clothing/under/corp/pcrc,
		"TG&C jumpsuit"=/obj/item/clothing/under/rank/neo_sec_red,
		"TG&C jumpskirt"=/obj/item/clothing/under/rank/neo_sec_red_skirt,
		"TG&C blue jumpsuit"=/obj/item/clothing/under/rank/neo_sec_blue,
		"TG&C white"=/obj/item/clothing/under/rank/neo_sec_suit,
		"TG&C blue"=/obj/item/clothing/under/rank/neo_sec_suit_blue,
		"TG&C turtleneck"=/obj/item/clothing/under/rank/neo_sec_turtle_red,
		"TG&C turtleneck & skirt"=/obj/item/clothing/under/rank/neo_sec_turtle_red_skirt,
		"TG&C blue turtleneck"=/obj/item/clothing/under/rank/neo_sec_turtle_blue,
		"TG&C blue turtleneck & skirt"=/obj/item/clothing/under/rank/neo_sec_turtle_blue_skirt,
		"corrections officer"=/obj/item/clothing/under/rank/neo_corrections,
		"corrections officer w/ skirt"=/obj/item/clothing/under/rank/neo_corrections_skirt,
		"runner's turtleneck"=/obj/item/clothing/under/rank/neo_runner,
		"TG&C bodyguard's suit"=/obj/item/clothing/under/rank/bodyguard_suit,
		"TG&C bodyguard's skirt"=/obj/item/clothing/under/rank/bodyguard_skirt,
		"TG&C bodyguard's turtleneck"=/obj/item/clothing/under/rank/bodyguard_turtleneck,
		"TG&C bodyguard's turtleneck w/ skirt"=/obj/item/clothing/under/rank/bodyguard_turtleskirt,
		"TG&C gorka suit"=/obj/item/clothing/under/rank/neo_gorka/sec,
		"ACE security undersuit"=/obj/item/clothing/under/rank/security/aces
	)
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(selector_uniforms)))
