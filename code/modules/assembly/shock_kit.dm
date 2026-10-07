/obj/item/assembly/shock_kit
	name = "electrohelmet assembly"
	desc = "This appears to be made from both an electropack and a helmet."
	icon_state = "shock_kit"
	var/obj/item/clothing/head/helmet/part1 = null
	var/obj/item/radio/electropack/part2 = null
	var/status = 0
	w_class = ITEMSIZE_HUGE
	special_handling = TRUE

CAPABILITIES(/obj/item/assembly/shock_kit)
	owns_one(nameof(part1), /obj/item/clothing/head/helmet)
	owns_one(nameof(part2), /obj/item/radio/electropack)


/obj/item/assembly/shock_kit/wrench_act(mob/user, obj/item/tool)
	if(!status)
		if(loc?.release_refusal(src, user))
			return ITEM_INTERACT_BLOCKING
		var/turf/T = loc
		if(ismob(T))
			T = T.loc
		part1.forceMove(T)
		part2.forceMove(T)
		rel_clear(part1, nameof(part1.master))
		rel_clear(part2, nameof(part2.master))
		rel_take(src, nameof(part1))
		rel_take(src, nameof(part2))
		consume(src, user)
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

/obj/item/assembly/shock_kit/screwdriver_act(mob/user, obj/item/tool)
	status = !status
	to_chat(user, span_notice("[src] is now [status ? "secured" : "unsecured"]!"))
	playsound(src, tool.usesound, 50, 1)
	add_fingerprint(user)
	return ITEM_INTERACT_SUCCESS

/// Overrides assembly's interaction_self(): trigger both shock kit parts instead of opening the UI.
/obj/item/assembly/shock_kit/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	part1.attack_self(user, status)
	part2.attack_self(user, status)
	add_fingerprint(user)
	return OP_OK

/obj/item/assembly/shock_kit/receive_signal()
	if(istype(loc, /obj/structure/bed/chair/e_chair))
		var/obj/structure/bed/chair/e_chair/C = loc
		C.shock()
	return
