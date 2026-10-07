
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// fossils

/obj/item/fossil
	name = "Fossil"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "bone"
	desc = "It's a fossil."
	var/animal = 1

DECLARE_LOOT(/obj/item/fossil/base, LOOT_TABLE(/obj/item/fossil/bone = 9, /obj/item/fossil/skull = 3, /obj/item/fossil/skull/horned = 2))
MAP_RESOLVER(/obj/item/fossil/base, GLOBAL_PROC_REF(resolve_loot))

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
		open_request(src, /datum/prompt/text/skeleton_plaque, PROC_REF(skeleton_plaque_answered), answerer = user, pen = W, interaction_context = interaction)
		return TRUE
	else
		return FALSE
	return TRUE

/obj/skeleton/proc/skeleton_plaque_answered(datum/act/request/context)
	if(!context.answer)
		return
	apply_skeleton_plaque(context)
	SStgui.update_uis(src)

/obj/skeleton/proc/apply_skeleton_plaque(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/text/skeleton_plaque/request = context.request
	var/mob/user = request.answerer
	plaque_contents = request.value
	act_message(user, src, MSG_SELF("You relabel the plaque on the base of [icon2html(src,viewers(src))] %T%."), \
		MSG_OTHERS("%U% writes something on the base of %T%."))
	if(src.contents.Find(/obj/item/fossil/skull/horned))
		src.desc = "A creature made of [src.contents.len-1] assorted bones and a horned skull. The plaque reads \'[plaque_contents]\'."
	else
		src.desc = "A creature made of [src.contents.len-1] assorted bones and a skull. The plaque reads \'[plaque_contents]\'."

/datum/prompt/text/skeleton_plaque
	title = "Skeleton plaque"
	question = "What would you like to write on the plaque:"
	timeout = 0
	var/obj/item/pen
	var/datum/interaction/interaction_context
	var/expected_interaction = FALSE
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/text/skeleton_plaque)
	ref_one(nameof(pen), /obj/item)
	ref_one(nameof(interaction_context), /datum/interaction)

/datum/prompt/text/skeleton_plaque/prepare(datum/act/A)
	. = ..()
	var/obj/item/captured_pen = pen
	var/datum/interaction/captured_interaction = interaction_context
	expected_interaction = !isnull(captured_interaction)
	rel_clear(src, nameof(pen))
	rel_set(src, nameof(pen), captured_pen)
	rel_clear(src, nameof(interaction_context))
	rel_set(src, nameof(interaction_context), captured_interaction)

/datum/prompt/text/skeleton_plaque/recheck_extra()
	. = ..()
	if(.)
		return
	if(QDELETED(pen) || (expected_interaction && QDELETED(interaction_context)))
		return "The original labeling interaction is no longer available."

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

