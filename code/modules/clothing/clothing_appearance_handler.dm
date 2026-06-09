/*
 * /datum/clothing_appearance_handler
 *
 * Centralises the sprite-selection logic that was previously duplicated across
 * /obj/item/clothing/accessory/get_inv_overlay() and get_mob_overlay(), and
 * partially repeated in choker/collar/setUniqueSpeciesSprite() overrides.
 *
 * Call sites on /obj/item/clothing/accessory delegate here; the cached
 * inv_overlay / mob_overlay vars remain on the accessory for backward compat.
 *
 * Sprite selection priority (highest → lowest):
 *   1. icon_override   — explicit per-item DMI override
 *   2. sprite_sheets   — per-species mob DMI (mob overlays only)
 *   3. default icon    — INV_ACCESSORIES_DEF_ICON fallback
 *
 * Addblend compositing (mob overlays only):
 *   If the accessory has an `addblends` icon state, a second pass blends it
 *   onto the base icon before returning the image.
 */

/datum/clothing_appearance_handler

/*
 * proc/build_inv_overlay(obj/item/clothing/accessory/acc)
 *
 * Builds and returns the inventory (item slot) overlay image for `acc`.
 * Applies a `_tie` variant of the icon state when available.
 * The result is cached on acc.inv_overlay by the caller.
 */
/datum/clothing_appearance_handler/proc/build_inv_overlay(obj/item/clothing/accessory/acc)
	var/tmp_icon_state = acc.overlay_state ? "[acc.overlay_state]" : "[acc.icon_state]"

	var/image/result
	if(acc.icon_override)
		if(icon_exists(acc.icon_override, "[tmp_icon_state]_tie"))
			tmp_icon_state = "[tmp_icon_state]_tie"
		result = image(icon = acc.icon_override, icon_state = tmp_icon_state, dir = SOUTH)
	else
		result = image(icon = INV_ACCESSORIES_DEF_ICON, icon_state = tmp_icon_state, dir = SOUTH)

	result.color = acc.color
	result.appearance_flags = acc.appearance_flags
	return result

/*
 * proc/build_mob_overlay(obj/item/clothing/accessory/acc)
 *
 * Builds and returns the on-mob overlay image for `acc`.
 * Requires the accessory to be inside a clothing item worn by a human;
 * returns null if that context is absent.
 *
 * Handles:
 *   - rolled/unrolled jumpsuit state adjustments
 *   - icon_override priority
 *   - species-specific sprite_sheets lookup
 *   - addblend compositing
 */
/datum/clothing_appearance_handler/proc/build_mob_overlay(obj/item/clothing/accessory/acc)
	if(!istype(acc.loc, /obj/item/clothing))
		return null

	var/tmp_icon_state = acc.overlay_state ? "[acc.overlay_state]" : "[acc.icon_state]"

	var/mob/living/carbon/human/H
	if(ishuman(acc.has_suit?.loc))
		H = acc.has_suit.loc

	// Adjust icon state for rolled/unrolled jumpsuit sleeves
	if(H && istype(acc.loc, /obj/item/clothing/under))
		var/obj/item/clothing/under/C = acc.loc
		if(LAZYACCESS(acc.on_rolled, "down") && C.rolled_down > 0)
			tmp_icon_state = acc.on_rolled["down"]
		else if(LAZYACCESS(acc.on_rolled, "rolled") && C.rolled_sleeves > 0)
			tmp_icon_state = acc.on_rolled["rolled"]

	var/image/result
	if(acc.icon_override)
		var/use_state = icon_exists(acc.icon_override, "[tmp_icon_state]_mob") ? "[tmp_icon_state]_mob" : tmp_icon_state
		result = image(icon = acc.icon_override, icon_state = use_state)
	else if(H && LAZYACCESS(acc.sprite_sheets, H.species.get_bodytype(H)))
		result = image(icon = acc.sprite_sheets[H.species.get_bodytype(H)], icon_state = tmp_icon_state)
	else
		result = image(icon = INV_ACCESSORIES_DEF_ICON, icon_state = tmp_icon_state)

	// Addblend compositing
	if(acc.addblends)
		var/icon/base = new/icon(icon = result.icon, icon_state = result.icon_state)
		var/icon/addblend_icon = new/icon(icon = result.icon, icon_state = acc.addblends)
		if(acc.color)
			base.Blend(acc.color, ICON_MULTIPLY)
		base.Blend(addblend_icon, ICON_ADD)
		result = image(base)
	else
		result.color = acc.color

	result.appearance_flags = acc.appearance_flags
	return result

/*
 * proc/resolve_species_icon_override(obj/item/clothing/accessory/acc, mob/living/carbon/human/H)
 *
 * Returns the appropriate icon_override for `acc` when worn by `H`, based on
 * the accessory's sprite_sheets list.  Returns null if no species-specific
 * override is defined.  Used by choker/collar setUniqueSpeciesSprite() logic.
 */
/datum/clothing_appearance_handler/proc/resolve_species_icon_override(obj/item/clothing/accessory/acc, mob/living/carbon/human/H)
	if(!istype(H))
		return null
	if(!acc.sprite_sheets)
		return null
	var/bodytype = H.species.get_bodytype(H)
	if(!bodytype)
		return null
	if(!(bodytype in acc.sprite_sheets))
		return null
	return acc.sprite_sheets[bodytype]

/// Global singleton instance — created at world startup.
GLOBAL_DATUM_INIT(clothing_appearance_handler, /datum/clothing_appearance_handler, new)
