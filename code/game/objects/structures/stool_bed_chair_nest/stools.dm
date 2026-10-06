//Todo: add leather and cloth for arbitrary coloured stools.

/obj/item/stool
	name = "stool"
	desc = "Apply butt."
	icon = 'icons/obj/furniture.dmi'
	icon_state = "stool_preview" //set for the map
	randpixel = 0
	center_of_mass_x = 0
	center_of_mass_y = 0
	force = 10
	throwforce = 10
	w_class = ITEMSIZE_HUGE
	var/base_icon = "stool_base"
	var/datum/material/material
	var/datum/material/padding_material

/obj/item/stool/padded
	icon_state = "stool_padded_preview" //set for the map

/// The stool's material and padding (its constructor params).
/obj/item/stool/var/material_key = MAT_STEEL
/obj/item/stool/var/padding_key

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/item/stool/proc/make_of(padding)
	material = get_material_by_name(material_key || MAT_STEEL)
	if(!istype(material))
		stack_trace("Material of type: [material_key] does not exist.")
		spent(src)
		return
	if(padding)
		padding_material = get_material_by_name(padding)
	force = round(material.blunt_damage()*0.4)
	update_icon()

/obj/item/stool/padded
	material_key = MAT_STEEL
	padding_key = MAT_CARPET

DECLARE_APPEARANCE_PROC(/obj/item/stool, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/stool/appearance_overlays()
	. = list()
	// Prep icon.
	icon_state = ""
	// Base icon.
	var/cache_key = "[base_icon]-[material.name]"
	if(isnull(GLOB.stool_cache[cache_key]))
		var/image/I = image(icon, base_icon)
		I.color = material.icon_colour
		GLOB.stool_cache[cache_key] = I
	. += GLOB.stool_cache[cache_key]
	// Padding overlay.
	if(padding_material)
		var/padding_cache_key = "[base_icon]-padding-[padding_material.name]"
		if(isnull(GLOB.stool_cache[padding_cache_key]))
			var/image/I =  image(icon, "[base_icon]_padding")
			I.color = padding_material.icon_colour
			GLOB.stool_cache[padding_cache_key] = I
		. += GLOB.stool_cache[padding_cache_key]
	// Strings.
	if(padding_material)
		name = "[padding_material.display_name] [initial(name)]" //this is not perfect but it will do for now.
		desc = "A padded stool. Apply butt. It's made of [material.use_name] and covered with [padding_material.use_name]."
	else
		name = "[material.display_name] [initial(name)]"
		desc = "A stool. Apply butt with care. It's made of [material.use_name]."

/obj/item/stool/proc/add_padding(padding_type)
	padding_material = get_material_by_name(padding_type)
	update_icon()

/obj/item/stool/proc/remove_padding()
	if(padding_material)
		padding_material.place_sheet(get_turf(src), 1)
		padding_material = null
	update_icon()

/obj/item/stool/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if (prob(5) && isliving(M))
		act_message(user, src, others = span_danger("%U% breaks %T% over [M]'s back!"))
		user.setClickCooldown(user.get_attack_speed())
		user.do_attack_animation(M)

		user.drop_from_inventory(src)

		user.remove_from_mob(src)
		dismantle(user)
		var/mob/living/T = M
		T.status_at_least(STAT_WEAKENED, 10)
		T.injure(INJURY_BLUNT, 20, null, src)
		return ITEM_INTERACT_SUCCESS
	..()

/obj/item/stool/proc/dismantle(mob/user)
	var/turf/T = get_turf(src)
	var/datum/material/frame_material = material
	var/datum/material/cover_material = padding_material
	if(!consume(src, user))
		return FALSE
	if(frame_material)
		frame_material.place_sheet(T, 1)
	if(cover_material)
		cover_material.place_sheet(T, 1)
	return TRUE

CAPABILITIES(/obj/item/stool)
	op("pad", stack(/obj/item/stack, 1), wait(0), label("Pad"),
		needs(req(PROC_REF(can_be_padded), because = PROC_REF(padding_refusal))), then(PROC_REF(padded_with)), says(MSG(bed/padded)))
	op("unpad", tool(TOOL_WIRECUTTER), wait(0), label("Remove padding"),
		needs(req(PROC_REF(has_padding), because = MSG(bed/no_padding))), then(PROC_REF(unpadded)), says(MSG(bed/unpadded)))
	op("dismantle", tool(TOOL_WRENCH), wait(0), label("Dismantle"), then(PROC_REF(taken_apart)))
	param(nameof(material_key), pos = 1)
	param(nameof(padding_key), pos = 2, apply = PROC_REF(make_of))

/obj/item/stool/proc/can_be_padded(datum/act/op/A)
	return !padding_material && !isnull(padding_type_of(A.held)) // ALLOW(reads): the padding is a material set when the seat is made or padded; a menu entry that asks is advisory, the click asks again

/obj/item/stool/proc/padding_refusal(datum/act/op/A)
	return padding_material ? /datum/msg/bed/already_padded : /datum/msg/bed/not_padding

/// A stack of padding goes on: the sheet is spent by the op.
/obj/item/stool/proc/padded_with(datum/act/op/A)
	if(!istype(src.loc, /turf))
		A.actor.drop_from_inventory(src)
		src.forceMove(get_turf(src))
	add_padding(padding_type_of(A.held))
	return OP_OK

/obj/item/stool/proc/has_padding(datum/act/A)
	return !!padding_material // ALLOW(reads): the padding is a material set when the seat is made or padded; a menu entry that asks is advisory, the click asks again

/obj/item/stool/proc/unpadded(datum/act/op/A)
	playsound(src, A.held.usesound, 50, 1)
	remove_padding()
	return OP_OK

/obj/item/stool/proc/taken_apart(datum/act/op/A)
	playsound(src, A.held.usesound, 50, 1)
	return dismantle(A.actor) ? OP_OK : OP_REFUSED


// === merged from stools_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/stool/baystool
	name = "bar stool"
	desc = "Apply butt."
	icon = 'icons/obj/furniture.dmi'
	icon_state = "bar_stool_preview" //set for the map
	randpixel = 0
	center_of_mass_x = 0
	center_of_mass_y = 0
	force = 10
	throwforce = 10
	w_class = ITEMSIZE_HUGE
	base_icon = "bar_stool_base"
	anchored = TRUE

/obj/item/stool/baystool/padded
	icon_state = "bar_stool_padded_preview" //set for the map

/obj/item/stool/baystool/padded
	material_key = MAT_STEEL
	padding_key = MAT_CARPET
