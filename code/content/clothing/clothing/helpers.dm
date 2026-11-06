/// The blood stain of an item: the blood sprite cut to the item's own silhouette, tinted `colour`; one shared image per (type, sprite, colour).
/proc/item_stain_image(item_type, icon, icon_state, colour)
	READS_FROM()
	if(!isfile(icon))
		return build_item_stain_image(item_type, icon, icon_state, colour)
	return CACHED_KEY(item_stain_images, "[item_type]|[icon]|[icon_state]|[colour]", item_type, icon, icon_state, colour)

/proc/build_item_stain_image(item_type, icon, icon_state, colour)
	var/image/blood = image(icon = 'icons/effects/blood.dmi', icon_state = "itemblood")
	blood.filters += filter(type = "alpha", icon = icon(icon, icon_state))
	blood.color = colour
	return blood

DECLARE_SHARED_CACHE_EX(item_digest_images, GLOBAL_PROC_REF(build_item_digest_image), SC_NEVER, 1024, 0)

/// The residue of a digesting item: the gurgle sludge of `colour` cut to the item's silhouette; one shared image per (icon, state, colour).
/proc/item_digest_image(icon, icon_state, colour)
	READS_FROM()
	if(!isfile(icon))
		return build_item_digest_image(icon, icon_state, colour)
	return CACHED_KEY(item_digest_images, "[icon]|[icon_state]|[colour]", icon, icon_state, colour)

/proc/build_item_digest_image(icon, icon_state, colour)
	var/image/temp = new /image(GLOB.gurgled_overlays[colour])
	temp.filters += filter(type = "alpha", icon = icon(icon, icon_state))
	return temp

/datum/prompt/choice/suit_sensor_mode
	question = "Select a sensor mode:"
	title = "Suit Sensor Mode"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/suit_sensor_mode/recheck_extra()
	var/obj/item/clothing/under/suit = owner
	if(!istype(suit) || QDELETED(suit) || QDELETED(answerer))
		return "gone"
	return suit.sensor_mode_refusal(answerer, !isnull(value))
