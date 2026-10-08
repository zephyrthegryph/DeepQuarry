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

TRACKED(/obj/item/stool, material)
TRACKED(/obj/item/stool, padding_material)
TRACKED(/obj/item/stool, base_icon)

/// What a draw reads of the frame and the padding: shared material definitions, which never change, so the look reads them through these and does
/// not watch them (the redraw comes from the tracked material / padding_material vars).
/obj/item/stool/proc/material_icon_colour()
	return material?.icon_colour

/obj/item/stool/proc/material_name()
	return material?.name

/obj/item/stool/proc/material_display_name()
	return material?.display_name

/obj/item/stool/proc/material_use_name()
	return material?.use_name

/obj/item/stool/proc/padding_icon_colour()
	return padding_material?.icon_colour

/obj/item/stool/proc/padding_material_name()
	return padding_material?.name

/obj/item/stool/proc/padding_display_name()
	return padding_material?.display_name

/obj/item/stool/proc/padding_use_name()
	return padding_material?.use_name

/// The stool's material and padding (its constructor params).
/obj/item/stool/var/material_key = MAT_STEEL
/obj/item/stool/var/padding_key

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/item/stool/proc/make_of(padding)
	set_material(get_material_by_name(material_key || MAT_STEEL))
	if(!istype(material))
		stack_trace("Material of type: [material_key] does not exist.")
		spent(src)
		return
	if(padding)
		set_padding_material(get_material_by_name(padding))
	force = round(material.blunt_damage()*0.4)

/obj/item/stool/padded
	material_key = MAT_STEEL
	padding_key = MAT_CARPET

/obj/item/stool/draw(datum/look/look)
	..()
	// Prep icon.
	look.state("")
	// Base icon.
	look.overlay(look_cached_image("[initial(icon)]-[base_icon]-[material_name()]-1", initial(icon), base_icon, material_icon_colour()))
	// Padding overlay.
	if(padding_material)
		look.overlay(look_cached_image("[initial(icon)]-[base_icon]-padding-[padding_material_name()]", initial(icon), "[base_icon]_padding", padding_icon_colour()))
	// Strings.
	if(padding_material)
		look.identity(name = "[padding_display_name()] [initial(name)]") //this is not perfect but it will do for now.
		look.identity(desc = "A padded stool. Apply butt. It's made of [material_use_name()] and covered with [padding_use_name()].")
	else
		look.identity(name = "[material_display_name()] [initial(name)]")
		look.identity(desc = "A stool. Apply butt with care. It's made of [material_use_name()].")

/obj/item/stool/proc/add_padding(padding_type)
	set_padding_material(get_material_by_name(padding_type))

/obj/item/stool/proc/remove_padding()
	if(padding_material)
		padding_material.place_sheet(get_turf(src), 1)
		set_padding_material(null)

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
