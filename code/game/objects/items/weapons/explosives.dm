/obj/item/plastique
	name = "plastic explosives"
	desc = "Used to put holes in specific areas without too much extra hole."
	gender = PLURAL
	icon = 'icons/obj/assemblies.dmi'
	icon_state = "plastic-explosive0"
	item_state = "plasticx"
	flags = NOBLUDGEON
	w_class = ITEMSIZE_SMALL
	var/timer = 10
	var/atom/target
	var/open_panel = 0
	var/image_overlay = null
	var/blast_dev = 0
	var/blast_heavy = 1
	var/blast_light = 2
	var/blast_flash = 3

/obj/item/plastique/Initialize(mapload)
	. = ..()
	image_overlay = image('icons/obj/assemblies.dmi', "plastic-explosive2")

/// Old attackby.
/obj/item/plastique/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(I.has_tool_quality(TOOL_MULTITOOL) || istype(I, /obj/item/assembly/signaler))
		wires_open(src, user)
		return OP_PASS
	return OP_DECLINE

/obj/item/plastique/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	open_panel = !open_panel
	to_chat(user, span_notice("You [open_panel ? "open" : "close"] the wire panel."))
	playsound(src, tool.usesound, 50, TRUE)
	return OP_OK

/obj/item/plastique/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	wires_open(src, user)
	return OP_OK

/obj/item/plastique/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	wires_open(src, user)
	return OP_OK

TRACKED(/obj/item/plastique, timer)


/obj/item/plastique/proc/explode_wire(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(istype(N) && N.mended)
		return
	explode(get_turf(src))

MSG_DEF_SELF(plastique/planting, "Planting explosives...")

CAPABILITIES(/obj/item/plastique)
	space(SPACE_PANEL, door = nameof(open_panel))
	wires(name = "Explosive wires", count = 1, tools = FALSE)
	on_wire(WIRE_EXPLODE, cut = PROC_REF(explode_wire), pulse = PROC_REF(explode_wire))
	op("plant", at_target(/obj), at_target(/turf), when(PROC_REF(plantable)), begins(MSG(plastique/planting)), starts(PROC_REF(plant_started)), wait(5 SECONDS, keeps = HELD | ADJACENT | STAY | TARGET_PRESENT), then(PROC_REF(planted)))
	op("timer", in_hand(), needs(req_self_held(), req(PROC_REF(timer_item_in_hands), because = MSG(op/not_available)), req_capable()), label("Set explosive timer"),
		asks(/datum/prompt/number, keeps = 0, fields = list("title" = "Timer", "question" = "Please set the timer.", "default" = 10, "min_value" = 10, "max_value" = 60000, "step" = 1, "timeout" = 0)), then(PROC_REF(timer_set)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))
	op("use_multitool", tool(TOOL_MULTITOOL), wait(0), then(PROC_REF(multitool_used)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// ASK_HELD used either actual hand, not the input event's saved held reference.
/obj/item/plastique/proc/timer_item_in_hands(datum/act/op/A)
	var/mob/living/actor = A.actor
	if(!istype(actor))
		return FALSE
	return actor.item_is_in_hands(src)

/obj/item/plastique/proc/timer_set(datum/act/op/A)
	var/datum/prompt/number/R = A.answer
	set_timer(CLAMP(R.value, 10, 60000))
	to_chat(A.actor, "Timer set for [timer] seconds.")
	return OP_OK

/// What a charge cannot be planted on: a mob, unsimulated or shuttle ground, storage and clothing.
/obj/item/plastique/proc/plantable(datum/act/op/A)
	var/atom/target = A.target
	return !(ismob(target) || istype(target, /turf/unsimulated) || istype(target, /turf/simulated/shuttle) || istype(target, /obj/item/storage/) || istype(target, /obj/item/clothing/accessory/storage/) || istype(target, /obj/item/clothing/under))

/obj/item/plastique/proc/plant_started(datum/act/op/A)
	A.actor.do_attack_animation(A.target)
	return null

/obj/item/plastique/proc/planted(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/target = A.target
	user.drop_item()
	rel_set(src, nameof(target), target_ref())
	moveToNullspace()

	if (ismob(target))
		add_attack_logs(user, target, "planted [name] on with [timer] second fuse")
		act_message(user, target, others = span_danger("%U% finished planting an explosive on %T%!"))
	else
		message_admins("[key_name(user, user.client)](<A href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=\ref[user]'>?</A>) planted [src.name] on [target.name] at ([target.x],[target.y],[target.z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[target.x];Y=[target.y];Z=[target.z]'>JMP</a>) with [timer] second fuse")
		log_game("[key_name(user)] planted [src.name] on [target.name] at ([target.x],[target.y],[target.z]) with [timer] second fuse")

	target.add_overlay(image_overlay)
	to_chat(user, "Bomb has been planted. Timer counting down from [timer].")
	after(src, timer SECONDS, PROC_REF(explode), with = list(get_turf(target)))
	return OP_OK

/obj/item/plastique/proc/explode(location)
	if(!target_ref())
		rel_set(src, nameof(target), get_atom_on_turf(src))
	if(!target_ref())
		rel_set(src, nameof(target), src)
	if(location)
		explosion(location, blast_dev, blast_heavy, blast_light, blast_flash)

	if(target_ref())
		if (istype(target_ref(), /turf/simulated/wall))
			var/turf/simulated/wall/W = target_ref()
			W.dismantle_wall(1,1,1)
		else if(isliving(target_ref()))
			target_ref().ex_act(2) // c4 can't gib mobs anymore.
		else
			target_ref().ex_act(1)
	if(target_ref())
		target_ref().cut_overlay(image_overlay)
	consume(src)

/obj/item/plastique/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return NONE

/obj/item/plastique/seismic
	name = "seismic charge"
	desc = "Used to dig holes in specific areas without too much extra hole."

	blast_dev = 3
	blast_heavy = 2
	blast_light = 4
	blast_flash = 7


/// Old attackby: it ran the parent's body first (its ..()), so this does too.
/obj/item/plastique/seismic/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	. = ..()
	if(open_panel)
		if(istype(I, /obj/item/stock_parts/micro_laser))
			var/obj/item/stock_parts/SP = I
			var/new_blast_power = max(1, round(SP.rating * 2) + 1)
			if(new_blast_power > blast_heavy)
				var/component_label = "\the [I]"
				if(!consume(I, user))
					return .
				to_chat(user, span_notice("You install [component_label] into \the [src]."))
				blast_heavy = new_blast_power
				blast_light = blast_heavy + round(new_blast_power * 0.5)
				blast_flash = blast_light + round(new_blast_power * 0.75)
			else
				to_chat(user, span_notice("The [I] is not any better than the component already installed into this charge!"))
	return .

/obj/item/plastique/seismic/locked
	desc = "Used to dig holes in specific areas without too much extra hole. Has extra mechanism that safely implodes the bomb if it is used in close proximity to the facility."

/obj/item/plastique/seismic/locked/explode(location)
	if(!target_ref())
		rel_set(src, nameof(target), get_atom_on_turf(src))
	if(!target_ref())
		rel_set(src, nameof(target), src)

	var/turf/T = get_turf(target_ref())
	if((T.z in using_map.station_levels) || (T.z in using_map.admin_levels))
		target_ref().visible_message(span_danger("\The [src] lets out a loud beep as safeties trigger, before imploding and falling apart."))
		target_ref().cut_overlay(image_overlay)
		consume(src)
		return 0
	else
		return ..()

/// Relation view: target (reads null once it is gone).
/obj/item/plastique/proc/target_ref() as /atom
	return target
