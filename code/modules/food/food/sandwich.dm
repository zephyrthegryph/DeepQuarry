/obj/item/reagent_containers/food/snacks/csandwich
	name = "sandwich"
	desc = "The best thing since sliced bread."
	icon_state = "breadslice"
	trash = /obj/item/trash/plate
	bitesize = 2

	var/list/ingredients

// A shard is hidden in it, and a food is layered on it until it would collapse.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/csandwich)
	op("hide_shard", item(/obj/item/material/shard), priority(OP_PRIORITY_PART + 1), label("Hide it inside"), then(PROC_REF(shard_hidden)))
	op("layer", item(/obj/item/reagent_containers/food/snacks), priority(OP_PRIORITY_PART), label("Layer it on"),
		needs(req_bool(PROC_REF(not_collapsing), because = MSG(snack/collapses))), then(PROC_REF(layered)))
	owns_many(nameof(ingredients))

MSG_DEF_SELF(snack/collapses, "If you put anything else on it it's going to collapse.")

/// How many things it holds at most: the bread in it makes room.
/obj/item/reagent_containers/food/snacks/csandwich/proc/sandwich_limit()
	var/limit = 4
	for(var/obj/item/O in ingredients)
		if(istype(O,/obj/item/reagent_containers/food/snacks/slice/bread))
			limit += 4
	return limit

/obj/item/reagent_containers/food/snacks/csandwich/proc/not_collapsing(datum/act/op/A)
	return length(contents) <= sandwich_limit() // ALLOW(spatial,reads): what is in it is counted when a food is added; the click asks again

/obj/item/reagent_containers/food/snacks/csandwich/proc/shard_hidden(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!own_bring_in(src, nameof(contents), W, null, user, TRUE, null, FALSE))
		return OP_REFUSED
	to_chat(user, span_blue("You hide [W] in \the [src]."))
	update()
	return OP_OK

/obj/item/reagent_containers/food/snacks/csandwich/proc/layered(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/snacks/W = A.held
	if(!move_into(src, nameof(src.ingredients), W, user))
		return OP_REFUSED
	to_chat(user, span_blue("You layer [W] over \the [src]."))
	W.reagents.trans_to_obj(src, W.reagents.total_volume)
	update()
	return OP_OK

/obj/item/reagent_containers/food/snacks/csandwich/proc/update()
	var/fullname = "" //We need to build this from the contents of the var.
	var/i = 0

	cut_overlays()

	for(var/obj/item/reagent_containers/food/snacks/O in ingredients)

		i++
		if(i == 1)
			fullname += "[O.name]"
		else if(i == length(ingredients))
			fullname += " and [O.name]"
		else
			fullname += ", [O.name]"

		var/image/I = new(src.icon, "sandwich_filling")
		I.color = O.filling_color
		I.pixel_x = pick(list(-1,0,1))
		I.pixel_y = (i*2)+1
		add_overlay(I)

	var/image/T = new(src.icon, "sandwich_top")
	T.pixel_x = pick(list(-1,0,1))
	T.pixel_y = (length(ingredients) * 2)+1
	add_overlay(T)

	name = lowertext("[fullname] sandwich")
	if(length(name) > 80) name = "[pick(list("absurd","colossal","enormous","ridiculous"))] sandwich"
	w_class = n_ceil(CLAMP((length(ingredients)/2),2,4))


/obj/item/reagent_containers/food/snacks/csandwich/examine(mob/user)
	. = ..()
	if(contents_count(src))
		var/obj/item/O = pick(contents)
		. += span_blue("You think you can see [O.name] in there.")

/obj/item/reagent_containers/food/snacks/csandwich/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)

	var/obj/item/shard
	for(var/obj/item/O in contents)
		if(istype(O,/obj/item/material/shard))
			shard = O
			break

	var/mob/living/H
	if(isliving(M))
		H = M

	if(H && shard && M == user) //This needs a check for feeding the food to other people, but that could be abusable.
		to_chat(H, span_red("You lacerate your mouth on a [shard.name] in the sandwich!"))
		H.injure(INJURY_CUT, 5, BP_HEAD, source = shard)
	..()
