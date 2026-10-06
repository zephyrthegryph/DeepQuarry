
#define JAR_NOTHING 0
#define JAR_MONEY   1
#define JAR_ANIMAL  2
#define JAR_SPIDER  3

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

/obj/item/glass_jar/Initialize(mapload)
	. = ..()
	update_icon()

/obj/item/glass_jar/afterattack(atom/A, mob/user, proximity, click_parameters, stance = I_HURT)
	if(!proximity || contains)
		return
	if(can_fill && !filled)
		if(istype(A, /obj/structure/sink) || istype(A, /turf/simulated/floor/water))
			if(contains && stance == I_HELP)
				to_chat(user, span_warning("That probably isn't the best idea."))
				return

			to_chat(user, span_notice("You fill \the [src] with water!"))
			filled = TRUE
			update_icon()
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
		contains = JAR_ANIMAL
		update_icon()
		return
	else if(istype(A, /obj/effect/spider/spiderling))
		var/obj/effect/spider/spiderling/S = A
		act_message(user, src, MSG_SELF(span_notice("You scoop [S] into %T%.")), MSG_OTHERS(span_notice("%U% scoops [S] into %T%.")))
		S.forceMove(src)
		om_task_periodic_stop(S) // No growing inside jars
		contains = JAR_SPIDER
		update_icon()
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
				filled = FALSE
				act_message(user, src, others = span_warning("%U% dumps out %T%'s water!"))
				update_icon()
				return OP_OK

		else
			act_message(user, src, others = span_notice("%U% dumps %T%'s water."))
			filled = FALSE
			update_icon()
			return OP_OK

	switch(contains)
		if(JAR_MONEY)
			for(var/obj/O in contents_of(src))
				O.forceMove(user.loc)
			to_chat(user, span_notice("You take money out of \the [src]."))
			contains = JAR_NOTHING
			update_icon()
			return OP_OK
		if(JAR_ANIMAL)
			for(var/mob/M in contents_of(src))
				M.forceMove(user.loc)
				act_message(user, src, MSG_SELF(span_notice("You release [M] from %T%.")), MSG_OTHERS(span_notice("%U% releases [M] from %T%.")))
			contains = JAR_NOTHING
			update_icon()
			return OP_OK
		if(JAR_SPIDER)
			for(var/obj/effect/spider/spiderling/S in contents_of(src))
				S.forceMove(user.loc)
				act_message(user, src, MSG_SELF(span_notice("You release [S] from %T%.")), MSG_OTHERS(span_notice("%U% releases [S] from %T%.")))
				om_task_periodic(S, PERIODIC_SLOW) // They can grow after being let out though
			contains = JAR_NOTHING
			update_icon()
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
		contains = JAR_MONEY
		act_message(user, src, others = span_notice("%U% puts [S.worth] [S.worth > 1 ? "thalers" : "thaler"] into %T%."))
		update_icon()
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
DECLARE_APPEARANCE_PROC(/obj/item/glass_jar, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/glass_jar/appearance_overlays() // Also updates name and desc
	. = list()
	underlays.Cut()

	if(filled)
		underlays += image(icon, "[icon_state]_water")

	switch(contains)
		if(JAR_NOTHING)
			name = initial(name)
			desc = initial(desc)
		if(JAR_MONEY)
			if(can_fill)
				name = "tip tank"
			else
				name = "tip jar"
			desc = "A [name] with money inside."
			for(var/obj/item/spacecash/S in contents_of(src))
				var/image/money = image(S.icon, S.icon_state)
				money.pixel_x = rand(-2, 3)
				money.pixel_y = rand(-6, 6)
				money.transform *= 0.6
				underlays += money
		if(JAR_ANIMAL)
			//tank
			if(can_fill)
				for(var/mob/M in contents_of(src))
					var/image/victim = image(M.icon, M.icon_state)
					var/initial_x_scale = M.icon_scale_x
					var/initial_y_scale = M.icon_scale_y
					M.adjust_scale(0.7)
					victim.appearance = M.appearance
					M.adjust_scale(initial_x_scale, initial_y_scale)
					victim.pixel_y = 4
					underlays += victim
					name = "[name] with [M]"
					desc = "A large [name] with [M] inside."
			else
				for(var/mob/M in contents_of(src))
					var/image/victim = image(M.icon, M.icon_state)
					victim.pixel_y = 6
					victim.color = M.color
					if(M.plane == PLANE_LIGHTING_ABOVE)	// This will only show up on the ground sprite, due to the HuD being over it, so we need both images.
						var/image/victim_glow = image(M.icon, M.icon_state)
						victim_glow.pixel_y = 6
						victim_glow.color = M.color
						underlays += victim_glow
					underlays += victim
					name = "glass jar with [M]"
					desc = "A small jar with [M] inside."
		if(JAR_SPIDER)
			for(var/obj/effect/spider/spiderling/S in contents_of(src))
				var/image/victim = image(S.icon, S.icon_state)
				underlays += victim
				if(can_fill)
					name = "[name] with [S]"
					desc = "A large tank with [S] inside."
				else
					name = "glass jar with [S]"
					desc = "A small jar with [S] inside."
				underlays += victim

	if(filled)
		desc = "[desc] It contains water."

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

#undef JAR_NOTHING
#undef JAR_MONEY
#undef JAR_ANIMAL
#undef JAR_SPIDER
