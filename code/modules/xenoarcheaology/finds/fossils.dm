
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// fossils

/obj/item/fossil
	name = "Fossil"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "bone"
	desc = "It's a fossil."
	var/animal = 1

CAPABILITIES(/obj/item/fossil/base)
	map_resolver(GLOBAL_PROC_REF(resolve_loot))
	loot(table = list(/obj/item/fossil/bone = 9, /obj/item/fossil/skull = 3, /obj/item/fossil/skull/horned = 2))

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

CAPABILITIES(/obj/item/fossil/skull)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/fossil/skull/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W,/obj/item/fossil/bone))
		var/obj/o = new /obj/skeleton(get_turf(src))
		new /obj/item/fossil/bone(o)
		new src.type(o)
		consume(W, user)
		consume(src, user)
	return OP_PASS

/obj/skeleton
	name = "Incomplete skeleton"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "uskel"
	desc = "Incomplete skeleton."
	var/bnum = 1
	var/breq
	var/bstate = 0
	var/plaque_contents = "Unnamed alien creature"

// ALLOW(init/INSTANCE_STATE): rolls how many bones it still needs
/obj/skeleton/Initialize(mapload)
	. = ..()
	breq = rand(6)+3
	desc = "An incomplete skeleton, looks like it could use [breq-bnum] more bones."

CAPABILITIES(/obj/skeleton)
	op("skeleton_bone", item(/obj/item/fossil/bone), label("Use"), then(PROC_REF(skeleton_bone)))
	op("skeleton_plaque", item(/obj/item/pen), label("Use"),
		asks(/datum/prompt/text, fields = list("question" = "What would you like to write on the plaque:", "title" = "Skeleton plaque", "timeout" = 0), step = "plaque"),
		then(PROC_REF(skeleton_plaque)))

/// Old attackby: add bones until complete.
/obj/skeleton/proc/skeleton_bone(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
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
			return OP_DECLINE
	else
		return OP_DECLINE
	return OP_OK

/// Old attackby with a pen: relabel the plaque.
/obj/skeleton/proc/skeleton_plaque(datum/act/op/A)
	var/mob/user = A.actor
	plaque_contents = A.step_value("plaque")
	act_message(user, src, MSG_SELF("You relabel the plaque on the base of [icon2html(src,viewers(src))] %T%."), \
		MSG_OTHERS("%U% writes something on the base of %T%."))
	if(src.contents.Find(/obj/item/fossil/skull/horned))
		src.desc = "A creature made of [src.contents.len-1] assorted bones and a horned skull. The plaque reads \'[plaque_contents]\'."
	else
		src.desc = "A creature made of [src.contents.len-1] assorted bones and a skull. The plaque reads \'[plaque_contents]\'."
	return OP_OK

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

CAPABILITIES(/obj/item/fossil/plant)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/fossil/plant/proc/roll_icon_state(datum/roller/R)
	return "plant[R.number(1, 4)]"

