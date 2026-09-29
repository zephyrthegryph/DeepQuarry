
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// fossils

/obj/item/fossil
	name = "Fossil"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "bone"
	desc = "It's a fossil."
	var/animal = 1

/obj/item/fossil/base/Initialize(mapload)
	..()
	var/list/l = list(/obj/item/fossil/bone = 9,/obj/item/fossil/skull = 3,
	/obj/item/fossil/skull/horned = 2)
	var/t = pickweight(l)
	new t(src.loc)
	return INITIALIZE_HINT_QDEL

/obj/item/fossil/bone
	name = "Fossilised bone"
	icon_state = "bone"
	desc = "It's a fossilised bone."

/obj/item/fossil/skull
	name = "Fossilised skull"
	icon_state = "skull"
	desc = "It's a fossilised skull."

/obj/item/fossil/skull/horned
	icon_state = "hskull"
	desc = "It's a fossilised, horned skull."

DECLARE_INTERACTIONS(/obj/item/fossil/skull, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/fossil/skull/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W,/obj/item/fossil/bone))
		var/obj/o = new /obj/skeleton(get_turf(src))
		new /obj/item/fossil/bone(o)
		new src.type(o)
		consume(W, user)
		consume(src, user)
	return INTERACTION_HANDLED_PASS

/obj/skeleton
	name = "Incomplete skeleton"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "uskel"
	desc = "Incomplete skeleton."
	var/bnum = 1
	var/breq
	var/bstate = 0
	var/plaque_contents = "Unnamed alien creature"

/obj/skeleton/Initialize(mapload)
	. = ..()
	breq = rand(6)+3
	desc = "An incomplete skeleton, looks like it could use [breq-bnum] more bones."

DECLARE_INTERACTIONS(/obj/skeleton, INTERACT_ITEM(null, PROC_REF(interaction_skeleton_item)))

/// Old attackby: add bones until complete, or relabel the plaque with a pen.
/obj/skeleton/proc/interaction_skeleton_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W,/obj/item/fossil/bone))
		if(!bstate)
			bnum++
			new /obj/item/fossil/bone(src)
			consume(W, user)
			if(bnum==breq)
				icon_state = "skel"
				src.bstate = 1
				set_density(TRUE)
				src.name = "alien skeleton display"
				if(src.contents.Find(/obj/item/fossil/skull/horned))
					src.desc = "A creature made of [src.contents.len-1] assorted bones and a horned skull. The plaque reads \'[plaque_contents]\'."
				else
					src.desc = "A creature made of [src.contents.len-1] assorted bones and a skull. The plaque reads \'[plaque_contents]\'."
			else
				src.desc = "Incomplete skeleton, looks like it could use [src.breq-src.bnum] more bones."
				to_chat(user, "Looks like it could use [src.breq-src.bnum] more bones.")
		else
			return FALSE
	else if(istype(W,/obj/item/pen))
		var/_answer_k80 = rerun_ask(user, "k80", PROC_REF(interaction_skeleton_item), args, /datum/om/prompt/text, message = "What would you like to write on the plaque:", title = "Skeleton plaque")
		if(isnull(_answer_k80))
			return TRUE
		plaque_contents = _answer_k80
		user.visible_message("[user] writes something on the base of [src].","You relabel the plaque on the base of [icon2html(src,viewers(src))] [src].")
		if(src.contents.Find(/obj/item/fossil/skull/horned))
			src.desc = "A creature made of [src.contents.len-1] assorted bones and a horned skull. The plaque reads \'[plaque_contents]\'."
		else
			src.desc = "A creature made of [src.contents.len-1] assorted bones and a skull. The plaque reads \'[plaque_contents]\'."
	else
		return FALSE
	return TRUE

//shells and plants do not make skeletons
/obj/item/fossil/shell
	name = "Fossilised shell"
	icon_state = "shell"
	desc = "It's a fossilised shell."

/obj/item/fossil/plant
	name = "Fossilised plant"
	icon_state = "plant1"
	desc = "It's fossilised plant remains."
	animal = 0

/obj/item/fossil/plant/Initialize(mapload)
	. = ..()
	icon_state = "plant[rand(1,4)]"
