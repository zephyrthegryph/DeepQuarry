/obj/structure/bed/chair	//YES, chairs are a type of bed, which are a type of stool. This works, believe me.	-Pete
	name = "chair"
	desc = "You sit in this. Either by will or force."
	icon = 'icons/obj/furniture.dmi'
	icon_state = "chair_preview"
	color = "#666666"
	base_icon = "chair"
	buckle_dir = 0
	buckle_lying = 0 //force people to sit up in chairs when src?.buckled_to()
	var/propelled = 0 // Check for fire-extinguisher-driven chairs
	/// Whether anyone is buckled to it (the armrests are drawn over the rider).
	var/occupied = FALSE

/obj/structure/bed/chair/proc/init_update_layer(datum/act/timer/A)
	update_layer()


MSG_DEF_SELF(chair/kit_unready, "The kit is not ready to be attached!")
MSG_DEF_SELF(chair/padded, "Take the padding off first.")

CAPABILITIES(/obj/structure/bed/chair)
	after_init(0, then(PROC_REF(init_update_layer)))
	op("shock_kit", item(/obj/item/assembly/shock_kit), label("Attach kit"),
		needs(req(PROC_REF(kit_ready), because = MSG(chair/kit_unready)), req(PROC_REF(unpadded_chair), because = MSG(chair/padded))), then(PROC_REF(electrified)))
	op("interaction_tk", tk(), label("Rotate"), then(PROC_REF(interaction_tk)))

/obj/structure/bed/chair/proc/kit_ready(datum/act/op/A)
	var/obj/item/assembly/shock_kit/SK = A.held
	return !!SK.status // ALLOW(reads): a kit's secured switch is read when it is clicked on; the click asks again

/obj/structure/bed/chair/proc/unpadded_chair(datum/act/A)
	return !padding_material // ALLOW(reads): the padding is a material set when the seat is made or padded; a menu entry that asks is advisory, the click asks again

/// A secured shock kit turns the chair into an electric chair, with the kit inside.
/obj/structure/bed/chair/proc/electrified(datum/act/op/A)
	var/obj/item/assembly/shock_kit/SK = A.held
	var/mob/user = A.actor
	var/obj/structure/bed/chair/e_chair/E = new (src.loc, material.name)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	E.set_dir(dir)
	if(!move_into(E, nameof(E.part), SK, user, ledger_slot = SLOT_ECHAIR_KIT)) // out of the hand, into the chair's kit slot (its default is the buckle seat)
		spent(E)
		return OP_REFUSED
	rel_set(SK, nameof(SK.master), E)
	replace_with(src, E)
	return OP_OK

/// Old attack_tk: spin an empty chair at range; an occupied one ignores telekinesis.
/obj/structure/bed/chair/proc/interaction_tk(datum/act/op/A)
	if(has_buckled_mobs())
		return OP_DECLINE
	rotate_clockwise()
	return TRUE

/// Tracked, set from post_buckle_mob() on every buckle and unbuckle: the armrests are drawn over the rider.
TRACKED(/obj/structure/bed/chair, occupied)

/obj/structure/bed/chair/post_buckle_mob()
	set_occupied(has_buckled_mobs())

/obj/structure/bed/chair/look_parts(datum/look/look)
	..()
	if(occupied)
		look.overlay(look_cached_image("[initial(icon)]-[base_icon]-armrest-[padding_material_name() || "no_material"]", initial(icon), "[base_icon]_armrest", padding_icon_colour(), MOB_PLANE, ABOVE_MOB_LAYER))

/obj/structure/bed/chair/proc/update_layer()
	if(src.dir == NORTH)
		plane = MOB_PLANE
		layer = MOB_LAYER + 0.1
	else
		reset_plane_and_layer()

/obj/structure/bed/chair/set_dir()
	..()
	update_layer()
	if(has_buckled_mobs())
		for(var/mob/living/L as anything in src?.buckled_mob_list())
			L.set_dir(dir)

/obj/structure/bed/chair/shuttle
	name = "chair"
	icon_state = "shuttlechair"
	base_icon = "shuttlechair"
	color = null
	applies_material_colour = 0

/obj/structure/bed/chair/shuttle_padded
	icon_state = "shuttlechair2"
	base_icon = "shuttlechair2"
	color = null
	applies_material_colour = 0

/obj/structure/bed/chair/comfy
	name = "comfy chair"
	desc = "It's a chair. It looks comfy."
	icon_state = "comfychair"
	base_icon = "comfychair"

/obj/structure/bed/chair/comfy/look_parts(datum/look/look)
	..()
	look.overlay(look_cached_image("[initial(icon)]-[base_icon]-over-[material_name()]", initial(icon), "[base_icon]_over", material_icon_colour(), MOB_PLANE, ABOVE_MOB_LAYER))
	if(padding_material)
		look.overlay(look_cached_image("[initial(icon)]-[base_icon]-padding-over-[padding_material_name()]", initial(icon), "[base_icon]_padding_over", padding_icon_colour(), MOB_PLANE, ABOVE_MOB_LAYER))

/obj/structure/bed/chair/comfy/brown
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_BROWN

/obj/structure/bed/chair/comfy/red
	material_key = MAT_STEEL
	padding_key = MAT_CARPET

/obj/structure/bed/chair/comfy/teal
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_TEAL

/obj/structure/bed/chair/comfy/black
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_BLACK

/obj/structure/bed/chair/comfy/green
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_GREEN

/obj/structure/bed/chair/comfy/purp
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_PURPLE

/obj/structure/bed/chair/comfy/blue
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_BLUE

/obj/structure/bed/chair/comfy/beige
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_BEIGE

/obj/structure/bed/chair/comfy/lime
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_LIME

/obj/structure/bed/chair/comfy/yellow
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_YELLOW

/obj/structure/bed/chair/comfy/orange
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_ORANGE

/obj/structure/bed/chair/comfy/rounded
	name = "rounded chair"
	desc = "It's a rounded chair. It looks comfy."
	icon_state = "roundedchair"
	icon = 'icons/obj/furniture.dmi' //These need to be base dmi, chomp's does not have them.
	base_icon = "roundedchair"

/obj/structure/bed/chair/comfy/rounded/brown
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_BROWN

/obj/structure/bed/chair/comfy/rounded/red
	material_key = MAT_STEEL
	padding_key = MAT_CARPET

/obj/structure/bed/chair/comfy/rounded/teal
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_TEAL

/obj/structure/bed/chair/comfy/rounded/black
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_BLACK

/obj/structure/bed/chair/comfy/rounded/green
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_GREEN

/obj/structure/bed/chair/comfy/rounded/purple
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_PURPLE

/obj/structure/bed/chair/comfy/rounded/blue
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_BLUE

/obj/structure/bed/chair/comfy/rounded/beige
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_BEIGE

/obj/structure/bed/chair/comfy/rounded/lime
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_LIME

/obj/structure/bed/chair/comfy/rounded/yellow
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_YELLOW

/obj/structure/bed/chair/comfy/rounded/orange
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_ORANGE

/obj/structure/bed/chair/office
	anchored = FALSE
	buckle_movable = 1
	can_pad = FALSE
	can_unpad = FALSE

/// Draws none of what the types above draw.
/obj/structure/bed/chair/office/look_parts(datum/look/look)
	return

/obj/structure/bed/chair/office/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()

	play_sfx(src, SFX_EFFECTS_ROLL)

/obj/structure/bed/chair/office/handle_buckled_mob_movement(atom/new_loc, direction, movetime)
	for(var/mob/living/occupant as anything in src?.buckled_mob_list())
		// Transient: not establishing/breaking the buckled_to relation, just
		// stopping Move() from treating the occupant as still-BUCKLED(src) for the
		// duration of this one forced step.
		occupant.skip_buckled_move_redirect = TRUE
		occupant.Move(loc, direction, movetime)
		occupant.skip_buckled_move_redirect = FALSE
		if (occupant && (loc != occupant.loc))
			if (propelled)
				for (var/mob/O in src.loc)
					if (O != occupant)
						Bump(O)

/obj/structure/bed/chair/office/Bump(atom/A)
	..()
	if(!has_buckled_mobs())	return

	if(propelled)
		for(var/a in src?.buckled_mob_list())
			var/mob/living/occupant = unbuckle_mob(a)

			var/def_zone = ran_zone()
			var/blocked = occupant.armor_against(INJURY_BLUNT, def_zone)
			occupant.throw_at(A, 3, propelled)
			occupant.apply_effect(6, STUN, blocked)
			occupant.apply_effect(6, WEAKEN, blocked)
			occupant.apply_effect(6, STUTTER, blocked)
			occupant.injure(INJURY_BLUNT, 10, def_zone, src, flags = INJURE_ARMORED)
			play_sfx(src, SFX_WEAPONS_PUNCH1)
			if(isliving(A))
				var/mob/living/victim = A
				def_zone = ran_zone()
				blocked = victim.armor_against(INJURY_BLUNT, def_zone)
				victim.apply_effect(6, STUN, blocked)
				victim.apply_effect(6, WEAKEN, blocked)
				victim.apply_effect(6, STUTTER, blocked)
				victim.injure(INJURY_BLUNT, 10, def_zone, src, flags = INJURE_ARMORED)
			act_message(occupant, A, others = span_danger("%U% crashed into %T%!"))

/obj/structure/bed/chair/office/light
	icon_state = "officechair_white"

/obj/structure/bed/chair/office/dark
	icon_state = "officechair_dark"

// Chair types
/obj/structure/bed/chair/wood
	name = "wooden chair"
	desc = "Old is never too old to not be in fashion."
	icon_state = "wooden_chair"
	can_pad = FALSE
	can_unpad = FALSE

/// Draws none of what the types above draw.
/obj/structure/bed/chair/wood/look_parts(datum/look/look)
	return

/obj/structure/bed/chair/wood
	material_key = MAT_WOOD

/obj/structure/bed/chair/wood/wings
	icon_state = "wooden_chair_wings"

//sofa

/obj/structure/bed/chair/sofa
	name = "sofa"
	desc = "It's a sofa. You sit on it. Possibly with someone else."
	base_icon = "sofamiddle"
	icon_state = "sofamiddle"
	applies_material_colour = 1
	var/sofa_material = MAT_CARPET
	var/corner_piece = FALSE
	resistance_flags = FLAMMABLE

/// The tint of the sofa's material (a shared definition that never changes).
/obj/structure/bed/chair/sofa/proc/sofa_colour()
	var/datum/material/material = get_material_by_name(sofa_material)
	return material?.icon_colour

/obj/structure/bed/chair/sofa/look_parts(datum/look/look)
	if(applies_material_colour && sofa_material)
		look.set_color(sofa_colour())

		if(sofa_material == MAT_CARPET)
			look.identity(name = "red [initial(name)]")
		else
			look.identity(name = "[sofa_material] [initial(name)]")

/obj/structure/bed/chair/sofa/update_layer()
	// Corner east/west should be on top of mobs, any other state's north should be.
	if(!corner_piece && (dir & NORTH))
		plane = MOB_PLANE
		layer = MOB_LAYER + 0.1
	else
		reset_plane_and_layer()

/obj/structure/bed/chair/sofa/left
	icon_state = "sofaend_left"
	base_icon = "sofaend_left"

/obj/structure/bed/chair/sofa/right
	icon_state = "sofaend_right"
	base_icon = "sofaend_right"

/obj/structure/bed/chair/sofa/corner
	icon_state = "sofacorner"
	base_icon = "sofacorner"
	corner_piece = TRUE

/obj/structure/bed/chair/sofa/corner/look_parts(datum/look/look)
	..()
	look.overlay(look_cached_image("[initial(icon)]-[base_icon]-armrest-[padding_material_name() || "no_material"]-permanent", initial(icon), "[base_icon]_armrest", padding_icon_colour(), MOB_PLANE, ABOVE_MOB_LAYER))

// Wooden nonsofa - no corners
/obj/structure/bed/chair/sofa/pew
	name = "pew bench"
	desc = "If they want you to go to church, why do they make these so uncomfortable?"
	base_icon = "pewmiddle"
	icon_state = "pewmiddle"
	icon = 'icons/obj/furniture.dmi' //These need to be base dmi, chomp's does not have them.
	applies_material_colour = FALSE

/obj/structure/bed/chair/sofa/pew/left
	icon_state = "pewend_left"
	base_icon = "pewend_left"

/obj/structure/bed/chair/sofa/pew/right
	icon_state = "pewend_right"
	base_icon = "pewend_right"

// Metal benches from Skyrat
/obj/structure/bed/chair/sofa/bench
	name = "metal bench"
	desc = "Almost as comfortable as waiting at a bus station for hours on end."
	base_icon = "benchmiddle"
	icon_state = "benchmiddle"
	icon = 'icons/obj/furniture.dmi' //These need to be base dmi, chomp's does not have them.
	applies_material_colour = FALSE
	color = null
	var/padding_color = "#CC0000"

/obj/structure/bed/chair/sofa/bench/Initialize(mapload, new_material, new_padding_material)
	. = ..()
	var/mutable_appearance/MA
	// If we're north-facing, metal goes above mob, padding overlay goes below mob.
	if((dir & NORTH) && !corner_piece)
		plane = MOB_PLANE
		layer = ABOVE_MOB_LAYER
		MA = mutable_appearance(icon, icon_state = "o[icon_state]", layer = BELOW_MOB_LAYER, plane = MOB_PLANE, appearance_flags = KEEP_APART|RESET_COLOR)
	// Else just normal plane and layer for everything, which will be below mobs.
	else
		MA = mutable_appearance(icon, icon_state = "o[icon_state]", appearance_flags = KEEP_APART|RESET_COLOR)
	MA.color = padding_color
	add_overlay(MA)

/obj/structure/bed/chair/sofa/bench/left
	icon_state = "bench_left"
	base_icon = "bench_left"

/obj/structure/bed/chair/sofa/bench/right
	icon_state = "bench_right"
	base_icon = "bench_right"

/obj/structure/bed/chair/sofa/bench/corner
	icon_state = "benchcorner"
	base_icon = "benchcorner"
	//corner_piece = TRUE // These sprites work fine without the parent doing layer shenanigans

// Corporate sofa - one color fits all
/obj/structure/bed/chair/sofa/corp
	name = "black leather sofa"
	desc = "How corporate!"
	base_icon = "corp_sofamiddle"
	icon_state = "corp_sofamiddle"
	icon = 'icons/obj/furniture.dmi' //These need to be base dmi, chomp's does not have them.
	applies_material_colour = FALSE

/obj/structure/bed/chair/sofa/corp/left
	icon_state = "corp_sofaend_left"
	base_icon = "corp_sofaend_left"

/obj/structure/bed/chair/sofa/corp/right
	icon_state = "corp_sofaend_right"
	base_icon = "corp_sofaend_right"

/obj/structure/bed/chair/sofa/corp/corner
	icon_state = "corp_sofacorner"
	base_icon = "corp_sofacorner"
	corner_piece = TRUE

//color variations
//Middle sofas first
/obj/structure/bed/chair/sofa
	sofa_material = MAT_CARPET

/obj/structure/bed/chair/sofa/brown
	sofa_material = MAT_CLOTH_BROWN

/obj/structure/bed/chair/sofa/teal
	sofa_material = MAT_CLOTH_TEAL

/obj/structure/bed/chair/sofa/black
	sofa_material = MAT_CLOTH_BLACK

/obj/structure/bed/chair/sofa/green
	sofa_material = MAT_CLOTH_GREEN

/obj/structure/bed/chair/sofa/purp
	sofa_material = MAT_CLOTH_PURPLE

/obj/structure/bed/chair/sofa/blue
	sofa_material = MAT_CLOTH_BLUE

/obj/structure/bed/chair/sofa/beige
	sofa_material = MAT_CLOTH_BEIGE

/obj/structure/bed/chair/sofa/lime
	sofa_material = MAT_CLOTH_LIME

/obj/structure/bed/chair/sofa/yellow
	sofa_material = MAT_CLOTH_YELLOW

/obj/structure/bed/chair/sofa/orange
	sofa_material = MAT_CLOTH_ORANGE

//sofa directions

/obj/structure/bed/chair/sofa/left
	icon_state = "sofaend_left"

/obj/structure/bed/chair/sofa/right
	icon_state = "sofaend_right"

/obj/structure/bed/chair/sofa/corner
	icon_state = "sofacorner"

/obj/structure/bed/chair/sofa/left/brown
	sofa_material = MAT_CLOTH_BROWN

/obj/structure/bed/chair/sofa/right/brown
	sofa_material = MAT_CLOTH_BROWN

/obj/structure/bed/chair/sofa/corner/brown
	sofa_material = MAT_CLOTH_BROWN

/obj/structure/bed/chair/sofa/left/teal
	sofa_material = MAT_CLOTH_TEAL

/obj/structure/bed/chair/sofa/right/teal
	sofa_material = MAT_CLOTH_TEAL

/obj/structure/bed/chair/sofa/corner/teal
	sofa_material = MAT_CLOTH_TEAL

/obj/structure/bed/chair/sofa/left/black
	sofa_material = MAT_CLOTH_BLACK

/obj/structure/bed/chair/sofa/right/black
	sofa_material = MAT_CLOTH_BLACK

/obj/structure/bed/chair/sofa/corner/black
	sofa_material = MAT_CLOTH_BLACK

/obj/structure/bed/chair/sofa/left/green
	sofa_material = MAT_CLOTH_GREEN

/obj/structure/bed/chair/sofa/right/green
	sofa_material = MAT_CLOTH_GREEN

/obj/structure/bed/chair/sofa/corner/green
	sofa_material = MAT_CLOTH_GREEN

/obj/structure/bed/chair/sofa/left/purp
	sofa_material = MAT_CLOTH_PURPLE

/obj/structure/bed/chair/sofa/right/purp
	sofa_material = MAT_CLOTH_PURPLE

/obj/structure/bed/chair/sofa/corner/purp
	sofa_material = MAT_CLOTH_PURPLE

/obj/structure/bed/chair/sofa/left/blue
	sofa_material = MAT_CLOTH_BLUE

/obj/structure/bed/chair/sofa/right/blue
	sofa_material = MAT_CLOTH_BLUE

/obj/structure/bed/chair/sofa/corner/blue
	sofa_material = MAT_CLOTH_BLUE

/obj/structure/bed/chair/sofa/left/beige
	sofa_material = MAT_CLOTH_BEIGE

/obj/structure/bed/chair/sofa/right/beige
	sofa_material = MAT_CLOTH_BEIGE

/obj/structure/bed/chair/sofa/corner/beige
	sofa_material = MAT_CLOTH_BEIGE

/obj/structure/bed/chair/sofa/left/lime
	sofa_material = MAT_CLOTH_LIME

/obj/structure/bed/chair/sofa/right/lime
	sofa_material = MAT_CLOTH_LIME

/obj/structure/bed/chair/sofa/corner/lime
	sofa_material = MAT_CLOTH_LIME

/obj/structure/bed/chair/sofa/left/yellow
	sofa_material = MAT_CLOTH_YELLOW

/obj/structure/bed/chair/sofa/right/yellow
	sofa_material = MAT_CLOTH_YELLOW

/obj/structure/bed/chair/sofa/corner/yellow
	sofa_material = MAT_CLOTH_YELLOW

/obj/structure/bed/chair/sofa/left/orange
	sofa_material = MAT_CLOTH_ORANGE

/obj/structure/bed/chair/sofa/right/orange
	sofa_material = MAT_CLOTH_ORANGE

/obj/structure/bed/chair/sofa/corner/orange
	sofa_material = MAT_CLOTH_ORANGE


// === merged from chairs_ch.dm during hard-fork de-suffix (verified no override-order change) ===

/obj/structure/bed/chair/comfy			// Making the premade chairs not have the basic chair visible, sometime make the constructed ones work as well
	icon = 'icons/obj/furniture_ch.dmi'
	icon_state = "comfychair"
	base_icon = "comfychair"

/obj/structure/bed/chair/oldsofa //Original Paradise port kept in the event players like these couches.
	name = "sofa"
	desc = "It's a couch. It looks kinda dingy."
	icon = 'icons/obj/furniture_ch.dmi'
	icon_state = "sofamiddleOLD"
	base_icon = "sofamiddleOLD"
	applies_material_colour = 0

/obj/structure/bed/chair/oldsofa/left
	icon_state = "sofaend_leftOLD"
	base_icon = "sofaend_leftOLD"

/obj/structure/bed/chair/oldsofa/right
	icon_state = "sofaend_rightOLD"
	base_icon = "sofaend_rightOLD"

/obj/structure/bed/chair/oldsofa/corner
	icon_state = "sofacornerOLD"
	base_icon = "sofacornerOLD"

/obj/structure/bed/chair/sofa/sif_ora
	material_key = MAT_SIFWOOD
	padding_key = MAT_CARPET_ORANGE

/obj/structure/bed/chair/sofa/left/sif_ora
	material_key = MAT_SIFWOOD
	padding_key = MAT_CARPET_ORANGE

/obj/structure/bed/chair/sofa/right/sif_ora
	material_key = MAT_SIFWOOD
	padding_key = MAT_CARPET_ORANGE

/obj/structure/bed/chair/sofa/corner/sif_ora
	material_key = MAT_SIFWOOD
	padding_key = MAT_CARPET_ORANGE


// === merged from chairs_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/structure/bed/chair/sofa
	name = "sofa"
	desc = "A padded, comfy sofa. Great for lazing on."
	icon = 'icons/obj/furniture_ch.dmi' //CHOMPstation edit: Improving on the sofas by making them visually change with padding
	base_icon = "sofamiddle"
	icon_state = "sofamiddle"	//CHOMPstation edit: preview in map maker

/obj/structure/bed/chair/sofa/left
	base_icon = "sofaend_left"
	icon_state = "sofaend_left"	//CHOMPstation edit: preview in map maker

/obj/structure/bed/chair/sofa/right
	base_icon = "sofaend_right"
	icon_state = "sofaend_right"	//CHOMPstation edit: preview in map maker

/obj/structure/bed/chair/sofa/corner
	base_icon = "sofacorner"
	icon_state = "sofacorner"	//CHOMPstation edit: preview in map maker

/obj/structure/bed/chair/modern_chair
	name = "modern chair"
	desc = "It's like sitting in an egg."
	icon_state = "modern_chair"
	color = null
	base_icon = "modern_chair"
	applies_material_colour = 0

/obj/structure/bed/chair/modern_chair/Initialize(mapload, new_material, new_padding_material)
	. = ..()
	var/image/I = image(icon, "[base_icon]_over")
	I.layer = ABOVE_MOB_LAYER
	I.plane = MOB_PLANE
	add_overlay(I)

/obj/structure/bed/chair/bar_stool
	name = "bar stool"
	desc = "How vibrant!"
	icon_state = "modern_stool"
	color = null
	base_icon = "modern_stool"
	applies_material_colour = 0

/obj/structure/bed/chair/backed_grey
	name = "grey chair"
	desc = "Also available in red."
	icon_state = "onestar_chair_grey"
	color = null
	base_icon = "onestar_chair_grey"
	applies_material_colour = 0

/obj/structure/bed/chair/backed_red
	name = "red chair"
	desc = "Also available in grey."
	icon_state = "onestar_chair_red"
	color = null
	base_icon = "onestar_chair_red"
	applies_material_colour = 0

// Baystation12 chairs with their larger update_icons proc
/obj/structure/bed/chair/bay/look_parts(datum/look/look)
	// Strings.
	if(padding_material)
		look.identity(name = "[padding_display_name()] [initial(name)]") //this is not perfect but it will do for now.
		look.identity(desc = "[initial(desc)] It's made of [material_use_name()] and covered with [padding_use_name()].")
	else
		look.identity(name = "[material_display_name()] [initial(name)]")
		look.identity(desc = "[initial(desc)] It's made of [material_use_name()].")

	// Prep icon.
	look.state("")
	var/base_colour = applies_material_colour ? material_icon_colour() : null

	// Base icon (base material color)
	look.overlay(look_cached_image("[initial(icon)]-[base_icon]-[material_name()]-[applies_material_colour]", initial(icon), base_icon, base_colour))

	// Padding ('_padding') (padding material color)
	if(padding_material)
		look.overlay(look_cached_image("[initial(icon)]-[base_icon]-padding-[padding_material_name()]", initial(icon), "[base_icon]_padding", padding_icon_colour()))

	// Over ('_over') (base material color)
	look.overlay(look_cached_image("[initial(icon)]-[base_icon]-[material_name()]-[applies_material_colour]-over", initial(icon), "[base_icon]_over", base_colour, MOB_PLANE, ABOVE_MOB_LAYER))

	// Padding Over ('_padding_over') (padding material color)
	if(padding_material)
		look.overlay(look_cached_image("[initial(icon)]-[base_icon]-padding-[padding_material_name()]-over", initial(icon), "[base_icon]_padding_over", padding_icon_colour(), MOB_PLANE, ABOVE_MOB_LAYER))

	if(occupied)
		// Armrest ('_armrest') (base material color)
		look.overlay(look_cached_image("[initial(icon)]-[base_icon]-[material_name()]-[applies_material_colour]-armrest", initial(icon), "[base_icon]_armrest", base_colour, MOB_PLANE, ABOVE_MOB_LAYER))
		if(padding_material)
			// Padding Armrest ('_padding_armrest') (padding material color)
			look.overlay(look_cached_image("[initial(icon)]-[base_icon]-padding-[padding_material_name()]-armrest", initial(icon), "[base_icon]_padding_armrest", padding_icon_colour(), MOB_PLANE, ABOVE_MOB_LAYER))

/obj/structure/bed/chair/bay/chair
	name = "mounted chair"
	desc = "Like a normal chair, but more stationary."
	icon_state = "bay_chair_preview"
	base_icon = "bay_chair"
	buckle_movable = 1

/obj/structure/bed/chair/bay/chair/padded/red
	padding_key = MAT_CARPET

/obj/structure/bed/chair/bay/chair/padded/brown
	padding_key = MAT_CLOTH_BROWN

/obj/structure/bed/chair/bay/chair/padded/teal
	padding_key = MAT_CLOTH_TEAL

/obj/structure/bed/chair/bay/chair/padded/black
	padding_key = MAT_CLOTH_BLACK

/obj/structure/bed/chair/bay/chair/padded/green
	padding_key = MAT_CLOTH_GREEN

/obj/structure/bed/chair/bay/chair/padded/purple
	padding_key = MAT_CLOTH_PURPLE

/obj/structure/bed/chair/bay/chair/padded/blue
	padding_key = MAT_CLOTH_BLUE

/obj/structure/bed/chair/bay/chair/padded/beige
	padding_key = MAT_CLOTH_BEIGE

/obj/structure/bed/chair/bay/chair/padded/lime
	padding_key = MAT_CLOTH_LIME

/obj/structure/bed/chair/bay/chair/padded/yellow
	padding_key = MAT_CLOTH_YELLOW

/obj/structure/bed/chair/bay/comfy
	name = "comfy mounted chair"
	desc = "Like a normal chair, but more stationary, and with more padding."
	icon_state = "bay_comfychair_preview"
	base_icon = "bay_comfychair"

/obj/structure/bed/chair/bay/comfy/red
	padding_key = MAT_CARPET

/obj/structure/bed/chair/bay/comfy/brown
	padding_key = MAT_CLOTH_BROWN

/obj/structure/bed/chair/bay/comfy/teal
	padding_key = MAT_CLOTH_TEAL

/obj/structure/bed/chair/bay/comfy/black
	padding_key = MAT_CLOTH_BLACK

/obj/structure/bed/chair/bay/comfy/green
	padding_key = MAT_CLOTH_GREEN

/obj/structure/bed/chair/bay/comfy/purple
	padding_key = MAT_CLOTH_PURPLE

/obj/structure/bed/chair/bay/comfy/blue
	padding_key = MAT_CLOTH_BLUE

/obj/structure/bed/chair/bay/comfy/beige
	padding_key = MAT_CLOTH_BEIGE

/obj/structure/bed/chair/bay/comfy/lime
	padding_key = MAT_CLOTH_LIME

/obj/structure/bed/chair/bay/comfy/yellow
	padding_key = MAT_CLOTH_YELLOW

/obj/structure/bed/chair/bay/comfy/captain
	name = "captain chair"
	desc = "It's a chair. Only for the highest ranked asses."
	icon_state = "capchair_preview"
	base_icon = "capchair"

/obj/structure/bed/chair/bay/comfy/captain/look_parts(datum/look/look)
	..()
	look.overlay(look_cached_image("[initial(icon)]-[base_icon]-special", initial(icon), "[base_icon]_special", null, MOB_PLANE, ABOVE_MOB_LAYER))

/obj/structure/bed/chair/bay/comfy/captain
	material_key = MAT_STEEL
	padding_key = MAT_CLOTH_BLUE

/obj/structure/bed/chair/bay/shuttle
	name = "shuttle seat"
	desc = "A comfortable, secure seat. It has a sturdy-looking buckling system for smoother flights."
	base_icon = "shuttle_chair"
	icon_state = "shuttle_chair_preview"
	buckle_movable = 0
	var/buckling_sound = SFX_EFFECTS_METAL_CLOSE
	var/padding = MAT_CLOTH_BLUE

/obj/structure/bed/chair/bay/shuttle
	padding_key = MAT_CLOTH_BLUE

/obj/structure/bed/chair/bay/shuttle/post_buckle_mob()
	playsound(src,buckling_sound,75,1)
	if(has_buckled_mobs())
		set_base_icon("shuttle_chair-b")
	else
		set_base_icon("shuttle_chair")
	..()

/obj/structure/bed/chair/bay/shuttle/look_parts(datum/look/look)
	..()
	if(!occupied)
		look.overlay(look_cached_image("[initial(icon)]-[base_icon]-special-[applies_material_colour ? material_name() : "plain"]", initial(icon), "[base_icon]_special", applies_material_colour ? material_icon_colour() : null, MOB_PLANE, ABOVE_MOB_LAYER))

/obj/structure/bed/chair/bay/chair/padded/red/smallnest
	name = "teshari nest"
	desc = "Smells like cleaning products."
	icon_state = "nest_chair"
	base_icon = "nest_chair"

/obj/structure/bed/chair/bay/chair/padded/red/bignest
	name = "large teshari nest"
	icon_state = "nest_chair_large"
	base_icon = "nest_chair_large"
