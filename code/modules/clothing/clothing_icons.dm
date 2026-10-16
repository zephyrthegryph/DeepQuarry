/obj/item/clothing/apply_accessories(image/standing)
	if(LAZYLEN(accessories))
		for(var/obj/item/clothing/accessory/A in accessories)
			standing.add_overlay(A.get_mob_overlay())

/obj/item/clothing/apply_blood(image/standing, mob/living/carbon/human/wearer)
	if(forensic_data?.has_blooddna() && blood_sprite_state && wearer)
		var/image/bloodsies	= image(icon = wearer.species.get_blood_mask(wearer), icon_state = blood_sprite_state)
		bloodsies.color		= dq_get_blood_color(src)
		standing.add_overlay(bloodsies)

//HELMET: May have a lighting overlay
/obj/item/clothing/head/make_worn_icon(body_type,slot_name,inhands,default_icon,default_layer = 0,icon/clip_mask = null, mob/living/carbon/human/wearer = null)
	var/image/standing = ..()
	if(light_on && slot_name == slot_head_str && standing)
		// The species' own sheet when the helmet has one for it (it holds the lamp state), else the shared worn lamp.
		var/lamp_icon = LAZYACCESS(sprite_sheets, body_type) || 'icons/mob/light_overlays.dmi'
		standing = look_composed_image(standing, list(look_cached_image("[light_overlay]-worn-[lamp_icon]", lamp_icon, light_overlay)))
	return standing

//SUIT: Blood state is slightly different
/obj/item/clothing/suit/apply_blood(image/standing, mob/living/carbon/human/wearer)
	if(forensic_data?.has_blooddna() && blood_sprite_state && wearer)
		set_blood_sprite_state("[blood_overlay_type]blood")
		var/image/bloodsies	= image(icon = wearer.species.get_blood_mask(wearer), icon_state = blood_sprite_state)
		bloodsies.color		= dq_get_blood_color(src)
		standing.add_overlay(bloodsies)


/obj/item/clothing/shoes/apply_blood(image/standing, mob/living/carbon/human/wearer)
	if(forensic_data?.has_blooddna() && blood_sprite_state && wearer)
		var/image/bloodsies	= image(icon = wearer.looks.digitigrade ? 'icons/mob/human_races/masks/blood_digitigrade.dmi' : wearer.species.get_blood_mask(wearer), icon_state = blood_sprite_state)
		bloodsies.color		= dq_get_blood_color(src)
		standing.add_overlay(bloodsies)
