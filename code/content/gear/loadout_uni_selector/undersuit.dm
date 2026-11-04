/datum/gear/uniform/undersuit
	display_name = "Civilian - Void Undersuits"
	description = "Select from a range of void undersuits. Each is breathable, sleek, and has standard induction ports. Security, Engineering, and Command variants can be found under the standard uniform selectors for those departments."
	path = /obj/item/clothing/under/undersuit/
	sort_category = "Uniforms"
	cost = 1

/datum/gear/uniform/undersuit/New()
	..()
	var/list/suits = list()
	var/static/list/blacklisted_types = list(/obj/item/clothing/under/undersuit/sec,
									  /obj/item/clothing/under/undersuit/sec/hos,
									  /obj/item/clothing/under/undersuit/hazard,
									  /obj/item/clothing/under/undersuit/command,
									  /obj/item/clothing/under/undersuit/centcom)
	for(var/obj/item/clothing/under/undersuit/undersuit_type as anything in typesof(/obj/item/clothing/under/undersuit))
		if(undersuit_type in blacklisted_types)
			continue
		suits[initial(undersuit_type.name)] = undersuit_type
	rel_add(src, nameof(gear_tweaks), new/datum/gear_tweak/path(sortAssoc(suits)))
