/obj/structure/bed/chair	//YES, chairs are a type of bed, which are a type of stool. This works, believe me.	-Pete
	name = "chair"
	desc = "You sit in this. Either by will or force."
	icon = 'icons/obj/furniture.dmi'
	icon_state = "chair_preview"
	color = "#666666"
	base_icon = "chair"
	buckle_dir = 0
	buckle_lying = 0 //force people to sit up in chairs when buckled
	var/propelled = 0 // Check for fire-extinguisher-driven chairs

/obj/structure/bed/chair/Initialize(mapload, new_material, new_padding_material)
	. = ..()
	update_layer()

/obj/structure/bed/chair/attackby(obj/item/W as obj, mob/user as mob)
	..()
	if(!padding_material && istype(W, /obj/item/assembly/shock_kit))
		var/obj/item/assembly/shock_kit/SK = W
		if(!SK.status)
			to_chat(user, span_notice("\The [SK] is not ready to be attached!"))
			return
		user.drop_item()
		var/obj/structure/bed/chair/e_chair/E = new (src.loc, material.name)
		playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
		E.set_dir(dir)
		E.part = SK
		SK.loc = E
		SK.master = E
		qdel(src)

/obj/structure/bed/chair/attack_tk(mob/user as mob)
	if(has_buckled_mobs())
		..()
	else
		rotate_clockwise()
	return

/obj/structure/bed/chair/post_buckle_mob()
	update_icon()

/obj/structure/bed/chair/update_icon()
	..()
	if(has_buckled_mobs())
		var/cache_key = "[base_icon]-armrest-[padding_material ? padding_material.name : "no_material"]"
		if(isnull(GLOB.stool_cache[cache_key]))
			var/image/I = image(icon, "[base_icon]_armrest")
			I.plane = MOB_PLANE
			I.layer = ABOVE_MOB_LAYER
			if(padding_material)
				I.color = padding_material.icon_colour
			GLOB.stool_cache[cache_key] = I
		add_overlay(GLOB.stool_cache[cache_key])

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
		for(var/mob/living/L as anything in buckled_mobs)
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

/obj/structure/bed/chair/comfy/update_icon()
	..()
	var/image/I = image(icon, "[base_icon]_over")
	I.layer = ABOVE_MOB_LAYER
	I.plane = MOB_PLANE
	I.color = material.icon_colour
	add_overlay(I)
	if(padding_material)
		I = image(icon, "[base_icon]_padding_over")
		I.layer = ABOVE_MOB_LAYER
		I.plane = MOB_PLANE
		I.color = padding_material.icon_colour
		add_overlay(I)

/obj/structure/bed/chair/comfy/brown/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_BROWN)

/obj/structure/bed/chair/comfy/red/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CARPET)

/obj/structure/bed/chair/comfy/teal/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_TEAL)

/obj/structure/bed/chair/comfy/black/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_BLACK)

/obj/structure/bed/chair/comfy/green/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_GREEN)

/obj/structure/bed/chair/comfy/purp/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_PURPLE)

/obj/structure/bed/chair/comfy/blue/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_BLUE)

/obj/structure/bed/chair/comfy/beige/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_BEIGE)

/obj/structure/bed/chair/comfy/lime/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_LIME)

/obj/structure/bed/chair/comfy/yellow/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_YELLOW)

/obj/structure/bed/chair/comfy/orange/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_ORANGE)

/obj/structure/bed/chair/comfy/rounded
	name = "rounded chair"
	desc = "It's a rounded chair. It looks comfy."
	icon_state = "roundedchair"
	icon = 'icons/obj/furniture.dmi' //CHOMP Edit - These need to be base dmi, chomp's does not have them.
	base_icon = "roundedchair"

/obj/structure/bed/chair/comfy/rounded/brown/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_BROWN)

/obj/structure/bed/chair/comfy/rounded/red/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CARPET)

/obj/structure/bed/chair/comfy/rounded/teal/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_TEAL)

/obj/structure/bed/chair/comfy/rounded/black/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_BLACK)

/obj/structure/bed/chair/comfy/rounded/green/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_GREEN)

/obj/structure/bed/chair/comfy/rounded/purple/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_PURPLE)

/obj/structure/bed/chair/comfy/rounded/blue/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_BLUE)

/obj/structure/bed/chair/comfy/rounded/beige/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_BEIGE)

/obj/structure/bed/chair/comfy/rounded/lime/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_LIME)

/obj/structure/bed/chair/comfy/rounded/yellow/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_YELLOW)

/obj/structure/bed/chair/comfy/rounded/orange/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_ORANGE)

/obj/structure/bed/chair/office
	anchored = FALSE
	buckle_movable = 1

/obj/structure/bed/chair/office/update_icon()
	return

/obj/structure/bed/chair/office/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W,/obj/item/stack) || W.has_tool_quality(TOOL_WIRECUTTER))
		return
	..()

/obj/structure/bed/chair/office/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()

	playsound(src, 'sound/effects/roll.ogg', 100, 1)

/obj/structure/bed/chair/office/handle_buckled_mob_movement(atom/new_loc, direction, movetime)
	for(var/mob/living/occupant as anything in buckled_mobs)
		occupant.buckled = null
		occupant.Move(loc, direction, movetime)
		occupant.buckled = src
		if (occupant && (loc != occupant.loc))
			if (propelled)
				for (var/mob/O in src.loc)
					if (O != occupant)
						Bump(O)

/obj/structure/bed/chair/office/Bump(atom/A)
	..()
	if(!has_buckled_mobs())	return

	if(propelled)
		for(var/a in buckled_mobs)
			var/mob/living/occupant = unbuckle_mob(a)

			var/def_zone = ran_zone()
			var/blocked = occupant.run_armor_check(def_zone, "melee")
			occupant.throw_at(A, 3, propelled)
			occupant.apply_effect(6, STUN, blocked)
			occupant.apply_effect(6, WEAKEN, blocked)
			occupant.apply_effect(6, STUTTER, blocked)
			occupant.apply_damage(10, BRUTE, def_zone, blocked)
			playsound(src, 'sound/weapons/punch1.ogg', 50, 1, -1)
			if(isliving(A))
				var/mob/living/victim = A
				def_zone = ran_zone()
				blocked = victim.run_armor_check(def_zone, "melee")
				victim.apply_effect(6, STUN, blocked)
				victim.apply_effect(6, WEAKEN, blocked)
				victim.apply_effect(6, STUTTER, blocked)
				victim.apply_damage(10, BRUTE, def_zone, blocked)
			occupant.visible_message(span_danger("[occupant] crashed into \the [A]!"))

/obj/structure/bed/chair/office/light
	icon_state = "officechair_white"

/obj/structure/bed/chair/office/dark
	icon_state = "officechair_dark"

// Chair types
/obj/structure/bed/chair/wood
	name = "wooden chair"
	desc = "Old is never too old to not be in fashion."
	icon_state = "wooden_chair"

/obj/structure/bed/chair/wood/update_icon()
	return

/obj/structure/bed/chair/wood/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W,/obj/item/stack) || W.has_tool_quality(TOOL_WIRECUTTER))
		return
	..()

/obj/structure/bed/chair/wood/Initialize(mapload)
	. = ..(mapload, MAT_WOOD)

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

/obj/structure/bed/chair/sofa/update_icon()
	if(applies_material_colour && sofa_material)
		var/datum/material/color_material = get_material_by_name(sofa_material)
		color = color_material.icon_colour

		if(sofa_material == MAT_CARPET)
			name = "red [initial(name)]"
		else
			name = "[sofa_material] [initial(name)]"

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

/obj/structure/bed/chair/sofa/corner/update_icon()
	..()
	var/cache_key = "[base_icon]-armrest-[padding_material ? padding_material.name : "no_material"]-permanent"
	if(isnull(GLOB.stool_cache[cache_key]))
		var/image/I = image(icon, "[base_icon]_armrest")
		I.plane = MOB_PLANE
		I.layer = ABOVE_MOB_LAYER
		if(padding_material)
			I.color = padding_material.icon_colour
		GLOB.stool_cache[cache_key] = I
	add_overlay(GLOB.stool_cache[cache_key])

// Wooden nonsofa - no corners
/obj/structure/bed/chair/sofa/pew
	name = "pew bench"
	desc = "If they want you to go to church, why do they make these so uncomfortable?"
	base_icon = "pewmiddle"
	icon_state = "pewmiddle"
	icon = 'icons/obj/furniture.dmi' //CHOMP Edit - These need to be base dmi, chomp's does not have them.
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
	icon = 'icons/obj/furniture.dmi' //CHOMP Edit - These need to be base dmi, chomp's does not have them.
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
	icon = 'icons/obj/furniture.dmi' //CHOMP Edit - These need to be base dmi, chomp's does not have them.
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

/obj/structure/bed/chair/sofa/sif_ora/Initialize(mapload,newmaterial)
	. = ..(mapload,MAT_SIFWOOD,MAT_CARPET_ORANGE)

/obj/structure/bed/chair/sofa/left/sif_ora/Initialize(mapload,newmaterial)
	. = ..(mapload,MAT_SIFWOOD,MAT_CARPET_ORANGE)

/obj/structure/bed/chair/sofa/right/sif_ora/Initialize(mapload,newmaterial)
	. = ..(mapload,MAT_SIFWOOD,MAT_CARPET_ORANGE)

/obj/structure/bed/chair/sofa/corner/sif_ora/Initialize(mapload,newmaterial)
	. = ..(mapload,MAT_SIFWOOD,MAT_CARPET_ORANGE)


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
/obj/structure/bed/chair/bay/update_icon()
	// Strings.
	desc = initial(desc)
	if(padding_material)
		name = "[padding_material.display_name] [initial(name)]" //this is not perfect but it will do for now.
		desc += " It's made of [material.use_name] and covered with [padding_material.use_name]."
	else
		name = "[material.display_name] [initial(name)]"
		desc += " It's made of [material.use_name]."

	// Prep icon.
	icon_state = ""
	cut_overlays()

	// Base icon (base material color)
	var/cache_key = "[base_icon]-[material.name]"
	if(isnull(GLOB.stool_cache[cache_key]))
		var/image/I = image(icon, base_icon)
		if(applies_material_colour)
			I.color = material.icon_colour
		GLOB.stool_cache[cache_key] = I
	add_overlay(GLOB.stool_cache[cache_key])

	// Padding ('_padding') (padding material color)
	if(padding_material)
		var/padding_cache_key = "[base_icon]-padding-[padding_material.name]"
		if(isnull(GLOB.stool_cache[padding_cache_key]))
			var/image/I =  image(icon, "[base_icon]_padding")
			I.color = padding_material.icon_colour
			GLOB.stool_cache[padding_cache_key] = I
		add_overlay(GLOB.stool_cache[padding_cache_key])

	// Over ('_over') (base material color)
	cache_key = "[base_icon]-[material.name]-over"
	if(isnull(GLOB.stool_cache[cache_key]))
		var/image/I = image(icon, "[base_icon]_over")
		I.plane = MOB_PLANE
		I.layer = ABOVE_MOB_LAYER
		if(applies_material_colour)
			I.color = material.icon_colour
		GLOB.stool_cache[cache_key] = I
	add_overlay(GLOB.stool_cache[cache_key])

	// Padding Over ('_padding_over') (padding material color)
	if(padding_material)
		var/padding_cache_key = "[base_icon]-padding-[padding_material.name]-over"
		if(isnull(GLOB.stool_cache[padding_cache_key]))
			var/image/I =  image(icon, "[base_icon]_padding_over")
			I.color = padding_material.icon_colour
			I.plane = MOB_PLANE
			I.layer = ABOVE_MOB_LAYER
			GLOB.stool_cache[padding_cache_key] = I
		add_overlay(GLOB.stool_cache[padding_cache_key])

	if(has_buckled_mobs())
		if(padding_material)
			cache_key = "[base_icon]-armrest-[padding_material.name]"
		// Armrest ('_armrest') (base material color)
		if(isnull(GLOB.stool_cache[cache_key]))
			var/image/I = image(icon, "[base_icon]_armrest")
			I.plane = MOB_PLANE
			I.layer = ABOVE_MOB_LAYER
			if(applies_material_colour)
				I.color = material.icon_colour
			GLOB.stool_cache[cache_key] = I
		add_overlay(GLOB.stool_cache[cache_key])
		if(padding_material)
			cache_key = "[base_icon]-padding-armrest-[padding_material.name]"
			// Padding Armrest ('_padding_armrest') (padding material color)
			if(isnull(GLOB.stool_cache[cache_key]))
				var/image/I = image(icon, "[base_icon]_padding_armrest")
				I.plane = MOB_PLANE
				I.layer = ABOVE_MOB_LAYER
				I.color = padding_material.icon_colour
				GLOB.stool_cache[cache_key] = I
			add_overlay(GLOB.stool_cache[cache_key])

/obj/structure/bed/chair/bay/chair
	name = "mounted chair"
	desc = "Like a normal chair, but more stationary."
	icon_state = "bay_chair_preview"
	base_icon = "bay_chair"
	buckle_movable = 1

/obj/structure/bed/chair/bay/chair/padded/red/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CARPET)

/obj/structure/bed/chair/bay/chair/padded/brown/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_BROWN)

/obj/structure/bed/chair/bay/chair/padded/teal/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_TEAL)

/obj/structure/bed/chair/bay/chair/padded/black/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_BLACK)

/obj/structure/bed/chair/bay/chair/padded/green/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_GREEN)

/obj/structure/bed/chair/bay/chair/padded/purple/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_PURPLE)

/obj/structure/bed/chair/bay/chair/padded/blue/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_BLUE)

/obj/structure/bed/chair/bay/chair/padded/beige/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_BEIGE)

/obj/structure/bed/chair/bay/chair/padded/lime/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_LIME)

/obj/structure/bed/chair/bay/chair/padded/yellow/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_YELLOW)

/obj/structure/bed/chair/bay/comfy
	name = "comfy mounted chair"
	desc = "Like a normal chair, but more stationary, and with more padding."
	icon_state = "bay_comfychair_preview"
	base_icon = "bay_comfychair"

/obj/structure/bed/chair/bay/comfy/red/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CARPET)

/obj/structure/bed/chair/bay/comfy/brown/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_BROWN)

/obj/structure/bed/chair/bay/comfy/teal/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_TEAL)

/obj/structure/bed/chair/bay/comfy/black/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_BLACK)

/obj/structure/bed/chair/bay/comfy/green/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_GREEN)

/obj/structure/bed/chair/bay/comfy/purple/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_PURPLE)

/obj/structure/bed/chair/bay/comfy/blue/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_BLUE)

/obj/structure/bed/chair/bay/comfy/beige/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_BEIGE)

/obj/structure/bed/chair/bay/comfy/lime/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_LIME)

/obj/structure/bed/chair/bay/comfy/yellow/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, new_material, MAT_CLOTH_YELLOW)

/obj/structure/bed/chair/bay/comfy/captain
	name = "captain chair"
	desc = "It's a chair. Only for the highest ranked asses."
	icon_state = "capchair_preview"
	base_icon = "capchair"

/obj/structure/bed/chair/bay/comfy/captain/update_icon()
	..()
	var/image/I = image(icon, "[base_icon]_special")
	I.plane = MOB_PLANE
	I.layer = ABOVE_MOB_LAYER
	add_overlay(I)

/obj/structure/bed/chair/bay/comfy/captain/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, MAT_CLOTH_BLUE)

/obj/structure/bed/chair/bay/shuttle
	name = "shuttle seat"
	desc = "A comfortable, secure seat. It has a sturdy-looking buckling system for smoother flights."
	base_icon = "shuttle_chair"
	icon_state = "shuttle_chair_preview"
	buckle_movable = 0
	var/buckling_sound = 'sound/effects/metal_close.ogg'
	var/padding = MAT_CLOTH_BLUE

/obj/structure/bed/chair/bay/shuttle/Initialize(mapload, new_material, new_padding_material)
	. = ..(mapload, MAT_STEEL, padding)

/obj/structure/bed/chair/bay/shuttle/post_buckle_mob()
	playsound(src,buckling_sound,75,1)
	if(has_buckled_mobs())
		base_icon = "shuttle_chair-b"
	else
		base_icon = "shuttle_chair"
	..()

/obj/structure/bed/chair/bay/shuttle/update_icon()
	..()
	if(!has_buckled_mobs())
		var/image/I = image(icon, "[base_icon]_special")
		I.plane = MOB_PLANE
		I.layer = ABOVE_MOB_LAYER
		if(applies_material_colour)
			I.color = material.icon_colour
		add_overlay(I)

/obj/structure/bed/chair/bay/chair/padded/red/smallnest
	name = "teshari nest"
	desc = "Smells like cleaning products."
	icon_state = "nest_chair"
	base_icon = "nest_chair"

/obj/structure/bed/chair/bay/chair/padded/red/bignest
	name = "large teshari nest"
	icon_state = "nest_chair_large"
	base_icon = "nest_chair_large"
