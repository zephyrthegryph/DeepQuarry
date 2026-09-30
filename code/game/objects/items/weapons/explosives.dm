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
	set_wires(new /datum/wires/explosive/c4(src))
	image_overlay = image('icons/obj/assemblies.dmi', "plastic-explosive2")

/// Old attackby.
/obj/item/plastique/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(I.has_tool_quality(TOOL_MULTITOOL) || istype(I, /obj/item/assembly/signaler))
		wires.Interact(user)
		return INTERACTION_HANDLED_PASS
	return FALSE

/obj/item/plastique/screwdriver_act(mob/user, obj/item/tool)
	open_panel = !open_panel
	to_chat(user, span_notice("You [open_panel ? "open" : "close"] the wire panel."))
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/item/plastique/wirecutter_act(mob/user, obj/item/tool)
	wires.Interact(user)
	return ITEM_INTERACT_SUCCESS

/obj/item/plastique/multitool_act(mob/user, obj/item/tool)
	wires.Interact(user)
	return ITEM_INTERACT_SUCCESS

DECLARE_INTERACTIONS(/obj/item/plastique, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/plastique/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	om_ask(user, /datum/om/prompt/number, PROC_REF(timer_set), title = "Timer", message = "Please set the timer.", default = 10, max = 60000, min = 10, ask_flags = ASK_HELD | ASK_CAPABLE)
	return TRUE

/obj/item/plastique/proc/timer_set(datum/om/prompt/number/ask)
	var/mob/user = ask.answerer
	var/newtime = CLAMP(ask.number, 10, 60000)
	timer = newtime
	to_chat(user, "Timer set for [timer] seconds.")

/obj/item/plastique/afterattack(atom/movable/target, mob/user, flag)
	if (!flag)
		return
	if (ismob(target) || istype(target, /turf/unsimulated) || istype(target, /turf/simulated/shuttle) || istype(target, /obj/item/storage/) || istype(target, /obj/item/clothing/accessory/storage/) || istype(target, /obj/item/clothing/under))
		return
	to_chat(user, "Planting explosives...")
	user.do_attack_animation(target)

	om_task_timed(user, 5 SECONDS, target = target, receiver = src, on_done = PROC_REF(afterattack_timed_done), done_args = list(target, user))

/obj/item/plastique/proc/afterattack_timed_done(atom/movable/target, mob/user)
	if(!(in_range(user, target)))
		return
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
	om_after(src, timer SECONDS, PROC_REF(explode), get_turf(target))

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

EXTEND_INTERACTIONS(/obj/item/plastique/seismic, INTERACT_ITEM(null, PROC_REF(seismic_interaction_item)))

/// Old attackby: it ran the parent's body first (its ..()), so this does too.
/obj/item/plastique/seismic/proc/seismic_interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	. = interaction_item(user, I, interaction)
	if(open_panel)
		if(istype(I, /obj/item/stock_parts/micro_laser))
			var/obj/item/stock_parts/SP = I
			var/new_blast_power = max(1, round(SP.rating * 2) + 1)
			if(new_blast_power > blast_heavy)
				to_chat(user, span_notice("You install \the [I] into \the [src]."))
				consume(I, user)
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
