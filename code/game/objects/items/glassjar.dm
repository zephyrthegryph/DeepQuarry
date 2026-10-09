
/obj/item/glass_jar
	name = "glass jar"
	desc = "A small empty jar."
	icon = 'icons/obj/items.dmi'
	icon_state = "jar"
	w_class = ITEMSIZE_SMALL
	MATERIAL_BULK(MAT_GLASS, 200)
	flags = NOBLUDGEON
	var/contains = 0 // 0 = nothing, 1 = money, 2 = animal, 3 = spiderling
	drop_sound = SFX_ITEMS_DROP_GLASS
	pickup_sound = SFX_ITEMS_PICKUP_GLASS

	///If we can fill it with water
	var/can_fill = FALSE
	///If we are filled with water.
	var/filled = FALSE

TYPE_TABLE_DECLARE(/obj/item/glass_jar, glass_jar_mobs, list(/mob/living/simple_mob/animal/passive/lizard, /mob/living/simple_mob/animal/passive/mouse, /mob/living/simple_mob/animal/sif/leech, /mob/living/simple_mob/animal/sif/frostfly, /mob/living/simple_mob/animal/sif/glitterfly))

/obj/item/glass_jar/afterattack(atom/A, mob/user, proximity, click_parameters, stance = I_HURT)
	if(!proximity || contains)
		return
	if(can_fill && !filled)
		if(istype(A, /obj/structure/sink) || istype(A, /turf/simulated/floor/water))
			if(contains && stance == I_HELP)
				to_chat(user, span_warning("That probably isn't the best idea."))
				return

			to_chat(user, span_notice("You fill \the [src] with water!"))
			set_filled(TRUE)
			return
	if(istype(A, /mob))
		var/accept = 0
		for(var/D in TYPE_TABLE_GET(src, glass_jar_mobs))
			if(istype(A, D))
				accept = 1
		if(!accept)
			to_chat(user, "[A] doesn't fit into \the [src].")
			return
		var/mob/L = A
		act_message(user, src, MSG_SELF(span_notice("You scoop [L] into %T%.")), MSG_OTHERS(span_notice("%U% scoops [L] into %T%.")))
		L.forceMove(src)
		set_contains(JAR_ANIMAL)
		return
	else if(istype(A, /obj/effect/spider/spiderling))
		var/obj/effect/spider/spiderling/S = A
		act_message(user, src, MSG_SELF(span_notice("You scoop [S] into %T%.")), MSG_OTHERS(span_notice("%U% scoops [S] into %T%.")))
		S.forceMove(src)
		set_contains(JAR_SPIDER)
		return

CAPABILITIES(/obj/item/glass_jar)
	// the old attack_self: empty the jar (help keeps a fish's water in)
	op("empty", in_hand(), stance(I_HELP), label("Empty"), then(PROC_REF(emptied_gently)))
	op("dump", in_hand(), stance(I_DISARM, I_GRAB, I_HURT), label("Empty, dumping the water"), then(PROC_REF(interaction_self)))
	// the old attackby: money goes in, a held micro is stuffed in
	op("put_in", inputs(item(/obj/item/spacecash), item(/obj/item/holder/micro)), label("Put in"), then(PROC_REF(interaction_item)))

/obj/item/glass_jar/proc/emptied_gently(datum/act/op/A)
	return jar_emptied(A.actor, TRUE)

/obj/item/glass_jar/proc/interaction_self(datum/act/op/A)
	return jar_emptied(A.actor, FALSE)

/// Old attack_self: let out what is inside (or the water); `gently` (help) leaves a fish its water.
/obj/item/glass_jar/proc/jar_emptied(mob/user, gently = FALSE)

	//For the fish jars
	if(can_fill && filled)
		if(contains == JAR_ANIMAL)
			if(gently)
				to_chat(user, span_notice("Maybe you shouldn't empty the water..."))
				return OP_OK

			else
				set_filled(FALSE)
				act_message(user, src, others = span_warning("%U% dumps out %T%'s water!"))
				return OP_OK

		else
			act_message(user, src, others = span_notice("%U% dumps %T%'s water."))
			set_filled(FALSE)
			return OP_OK

	switch(contains)
		if(JAR_MONEY)
			for(var/obj/O in contents_of(src))
				O.forceMove(user.loc)
			to_chat(user, span_notice("You take money out of \the [src]."))
			set_contains(JAR_NOTHING)
			return OP_OK
		if(JAR_ANIMAL)
			for(var/mob/M in contents_of(src))
				M.forceMove(user.loc)
				act_message(user, src, MSG_SELF(span_notice("You release [M] from %T%.")), MSG_OTHERS(span_notice("%U% releases [M] from %T%.")))
			set_contains(JAR_NOTHING)
			return OP_OK
		if(JAR_SPIDER)
			for(var/obj/effect/spider/spiderling/S in contents_of(src))
				S.forceMove(user.loc)
				act_message(user, src, MSG_SELF(span_notice("You release [S] from %T%.")), MSG_OTHERS(span_notice("%U% releases [S] from %T%.")))
			set_contains(JAR_NOTHING)
			return OP_OK
	for(var/mob/M in contents_of(src))
		if(istype(M,/mob/living/voice)) //Don't knock voices out!
			continue
		M.forceMove(get_turf(user))
		to_chat(M, span_warning("[user] shakes you out of \the [src]!"))
		to_chat(user, span_notice("You shake [M] out of \the [src]!"))
	return OP_OK
/// Old attackby.
/obj/item/glass_jar/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/spacecash))
		if(contains != JAR_NOTHING && contains != JAR_MONEY)
			return OP_PASS
		var/obj/item/spacecash/S = W
		if(!own_bring_in(src, nameof(contents), S, null, user, TRUE, null, FALSE))
			return OP_PASS
		set_contains(JAR_MONEY)
		act_message(user, src, others = span_notice("%U% puts [S.worth] [S.worth > 1 ? "thalers" : "thaler"] into %T%."))
	if(istype(W,/obj/item/holder/micro))
		var/full = 0
		for(var/mob/M in contents_of(src))
			if(istype(M,/mob/living/voice)) //Don't count voices as people!
				continue
			full++
		if(full >= 2)
			to_chat(user, span_warning("You can't fit anyone else into \the [src]!"))
		else
			var/obj/item/holder/micro/holder = W
			if(holder.held_mob && (is_in_holder(holder.held_mob, holder)))
				var/mob/living/M = holder.held_mob
				holder.dump_mob()
				to_chat(M, span_warning("[user] stuffs you into \the [src]!"))
				M.forceMove(src)
				to_chat(user, span_notice("You stuff \the [M] into \the [src]!"))
	return OP_PASS
TRACKED(/obj/item/glass_jar, contains)
TRACKED(/obj/item/glass_jar, filled)

/// The jar, its water and what it holds (named and described by it): coins heaped, creatures seen through the glass.
/obj/item/glass_jar/draw(datum/look/look)
	..()
	var/jar_name = initial(name)
	var/jar_desc = initial(desc)
	if(filled)
		look.underlay(look_overlay_image(icon, "[initial(icon_state)]_water"))

	switch(contains)
		if(JAR_MONEY)
			jar_name = can_fill ? "tip tank" : "tip jar"
			jar_desc = "A [jar_name] with money inside."
			var/i = 0
			for(var/obj/item/spacecash/S in look.things_in(src, null, /obj/item/spacecash))
				i++
				var/matrix/small = matrix()
				small.Scale(0.6)
				look.underlay(look_overlay_image(of = S, pixel_x = ((i * 5) % 6) - 2, pixel_y = ((i * 7) % 13) - 6, transform = small))
		if(JAR_ANIMAL)
			//tank
			if(can_fill)
				for(var/mob/M in look.things_in(src, null, /mob))
					var/matrix/shrunk = matrix()
					shrunk.Scale(0.7)
					look.underlay(look_overlay_image(of = M, pixel_y = 4, transform = shrunk))
					jar_name = "[initial(name)] with [M]"
					jar_desc = "A large [jar_name] with [M] inside."
			else
				for(var/mob/M in look.things_in(src, null, /mob))
					look.underlay(look_overlay_image(of = M, pixel_y = 6))
					jar_name = "glass jar with [M]"
					jar_desc = "A small jar with [M] inside."
		if(JAR_SPIDER)
			for(var/obj/effect/spider/spiderling/S in look.things_in(src, null, /obj/effect/spider/spiderling))
				look.underlay(look_overlay_image(of = S))
				if(can_fill)
					jar_name = "[initial(name)] with [S]"
					jar_desc = "A large tank with [S] inside."
				else
					jar_name = "glass jar with [S]"
					jar_desc = "A small jar with [S] inside."

	look.identity(name = jar_name, desc = filled ? "[jar_desc] It contains water." : jar_desc)

/obj/item/glass_jar/fish
	name = "glass tank"
	desc = "A large glass tank."

	can_fill = TRUE

	w_class = ITEMSIZE_NORMAL

TYPE_TABLE(/obj/item/glass_jar/fish, glass_jar_mobs, list(/mob/living/simple_mob/animal/passive/lizard, /mob/living/simple_mob/animal/passive/mouse, /mob/living/simple_mob/animal/sif/leech, /mob/living/simple_mob/animal/sif/frostfly, /mob/living/simple_mob/animal/sif/glitterfly, /mob/living/simple_mob/animal/passive/fish))


/obj/item/glass_jar/fish/plastic
	name = "plastic tank"
	desc = "A large plastic tank."
	MATERIAL_BULK(MAT_PLASTIC, 4000)

