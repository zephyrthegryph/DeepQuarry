DECLARE_SHARED_CACHE_EX(mob_hat, GLOBAL_PROC_REF(build_mob_hat), SC_NEVER, 1024, 0)

/proc/get_hat_icon(obj/item/hat, offset_x = 0, offset_y = 0)
	var/t_state = hat.icon_state
	if(LAZYACCESS(hat.item_state_slots, slot_head_str))
		t_state = hat.item_state_slots[slot_head_str]
	else if(hat.item_state)
		t_state = hat.item_state
	var/key = "[t_state]_[offset_x]_[offset_y]"
	// Not ideal as there's no guarantee all hat icon_states are unique across multiple dmis, but whatever.
	var/t_icon = INV_HEAD_DEF_ICON
	if(hat.icon_override)
		t_icon = hat.icon_override
	else if(LAZYACCESS(hat.item_icons, slot_head_str))
		t_icon = hat.item_icons[slot_head_str]
	return CACHED_KEY(mob_hat, key, t_icon, t_state, offset_x, offset_y)

/proc/build_mob_hat(t_icon, t_state, offset_x, offset_y)
	var/image/I = image(icon = t_icon, icon_state = t_state)
	I.pixel_x = offset_x
	I.pixel_y = offset_y
	return I

/mob/living/silicon/robot/drone
	name = "maintenance drone"
	real_name = "drone"
	icon = 'icons/mob/robots.dmi'
	icon_state = "repairbot"
	endurance = 35
	// Drones don't locate damage on components: one whole-body machine load.
	body_type = /datum/body/simple/machine
	cell_emp_mult = 1
	// They are unable to be upgraded, so they get a better battery.
	cell_type = /obj/item/cell/high
	photo_camera_type = /obj/item/camera/siliconcam/drone_camera
	universal_speak = 0
	universal_understand = 1
	gender = NEUTER
	pass_flags = PASSTABLE
	braintype = "Drone"
	lawupdate = FALSE
	density = TRUE
	req_access = list(ACCESS_ENGINE, ACCESS_ROBOTICS)
	integrated_light_power = 3
	local_transmit = 1

	can_pull_size = ITEMSIZE_NO_CONTAINER
	can_pull_mobs = MOB_PULL_SMALLER

	mob_bump_flag = SIMPLE_ANIMAL
	mob_swap_flags = SIMPLE_ANIMAL
	mob_push_flags = SIMPLE_ANIMAL
	mob_always_swap = 1

	mob_size = MOB_SMALL

	//Used for self-mailing.
	var/mail_destination = ""
	var/obj/machinery/drone_fabricator/master_fabricator
	var/law_type = /datum/ai_laws/drone
	var/module_type = /obj/item/robot_module/drone
	var/hat_x_offset = 0
	var/hat_y_offset = -13
	var/serial_number = 0
	var/name_override = 0

	var/foreign_droid = FALSE

	holder_type = /obj/item/holder/drone

	can_be_antagged = FALSE

	var/static/list/shell_types = list("Classic" = "repairbot", "Eris" = "maintbot")
	var/can_pick_shell = TRUE
	var/list/shell_accessories
	var/can_blitz = FALSE

/mob/living/silicon/robot/drone/is_sentient()
	return FALSE

// Yes this allows any object, yes it's silly. I don't know if it's ever been abused by drones though.
TYPE_TABLE(/mob/living/silicon/robot/drone, ventcrawl_get_item_whitelist, list( \
		/atom/movable/emissive_blocker, \
		/atom/movable/screen, \
		/obj \
		))

/mob/living/silicon/robot/drone/construction
	name = "construction drone"
	icon_state = "constructiondrone"
	law_type = /datum/ai_laws/construction_drone
	module_type = /obj/item/robot_module/drone/construction
	hat_x_offset = 1
	hat_y_offset = -12
	can_pull_mobs = MOB_PULL_SAME
	can_pick_shell = FALSE
	shell_accessories = list("eyes-constructiondrone")

/mob/living/silicon/robot/drone/mining
	icon_state = "miningdrone"
	item_state = "constructiondrone"
	law_type = /datum/ai_laws/mining_drone
	module_type = /obj/item/robot_module/drone/mining
	hat_x_offset = 1
	hat_y_offset = -12
	can_pull_mobs = MOB_PULL_SAME
	can_pick_shell = FALSE
	shell_accessories = list("eyes-miningdrone")

/mob/living/silicon/robot/drone/Initialize(mapload, is_decoy)
	. = ..(mapload, FALSE)
	remove_language(LANGUAGE_ROBOT_TALK)
	add_language(LANGUAGE_ROBOT_TALK, 0)
	add_language(LANGUAGE_DRONE_TALK, 1)
	serial_number = rand(0,999)

	grant(src, drone_shell(), src)
	grant(src, drone_mail(), src)

	if(can_pick_shell)
		var/random = pick(shell_types)
		icon_state = shell_types[random] // ALLOW(decl): Initialize rolls a random pick per instance; a declaration has no random form
		set_shell_accessories(list("[icon_state]-eyes-blue"))

	updatename()

/mob/living/silicon/robot/drone/setup_camera()
	if(scrambledcodes || foreign_droid)
		photo_camera_type = null
	..()

/mob/living/silicon/robot/drone/setup_laws()
	..()
	additional_law_channels -= "Binary"
	additional_law_channels["Drone"] = ":d"
	rel_set(src, nameof(laws), new law_type)

/mob/living/silicon/robot/drone/setup_module()
	..()
	if(!module)
		rel_set(src, nameof(module), new module_type(src))
	flavor_text = "It's a tiny little repair drone. The casing is stamped with an corporate logo and the subscript: '[using_map.company_name] Recursive Repair Systems: Fixing Tomorrow's Problem, Today!'"
	play_sfx(src, SFX_MACHINES_TWOBEEP, vary = FALSE)

/mob/living/silicon/robot/drone/Login()
	. = ..()
	if(can_pick_shell)
		to_chat(src, span_infoplain(span_bold("You can select a shell using the 'Abilities.Silicon' > 'Customize Appearance'")))

//Redefining some robot procs...
/mob/living/silicon/robot/drone/SetName(pickedName as text)
	// Would prefer to call the grandparent proc but this isn't possible, so..
	real_name = pickedName
	name = real_name

/mob/living/silicon/robot/drone/updatename()
	if(name_override)
		return

	real_name = "[initial(name)] ([serial_number])"
	name = real_name

TRACKED(/mob/living/silicon/robot/drone, shell_accessories)

/// A drone's look is its shell accessories and its hat; the sprite datum sheet is not used.
/mob/living/silicon/robot/drone/look_parts(datum/look/look)
	look.watch(hat)
	for(var/accessory in shell_accessories)
		look.overlay(accessory)
	look.overlay(hat_look())

/// Drones wear hats through the shared robot hat procs, drawn at their own offsets.
/mob/living/silicon/robot/drone/hat_look()
	if(hat)
		return get_hat_icon(hat, hat_x_offset, hat_y_offset)

/// The shells on offer: the drone type's own, and the blitz shell for a drone that can.
/mob/living/silicon/robot/drone/proc/shell_choices(datum/act/A)
	var/list/choices = shell_types.Copy()
	if(can_blitz)
		choices["Blitz"] = "blitzshell"
	return choices

/// The picture state of the shell the first question was answered with, or null.
/mob/living/silicon/robot/drone/proc/shell_state_answered(datum/act/op/A)
	var/choice = A.step_value("shell")
	return choice ? shell_choices()[choice] : null

/mob/living/silicon/robot/drone/proc/shell_has_eyes(datum/act/op/A)
	return shell_state_answered(A) in list("repairbot", "maintbot")

/mob/living/silicon/robot/drone/proc/shell_has_plating(datum/act/op/A)
	return shell_state_answered(A) == "maintbot"

/// Picking a drone shell: the shell, then optional eye and plating colours. A cancel after the shell takes what was answered so far.
/mob/living/silicon/robot/drone/proc/ability_pick_shell(datum/act/op/A)
	// If you add more, datumize these. Having 'basically two' is not enough to make me bother though.
	shell_customize_finish(shell_state_answered(A), A.step_value("eyes"), A.step_value("plating"))
	return OP_OK

/mob/living/silicon/robot/drone/proc/shell_cancelled(datum/act/op/A)
	var/shell_state = shell_state_answered(A)
	if(!shell_state)
		return
	shell_customize_finish(shell_state, A.step_value("eyes") || "", A.step_value("plating") || "")

/mob/living/silicon/robot/drone/proc/shell_customize_finish(shell_state, eyes, plating)
	icon_state = shell_state
	var/list/accessories
	if(eyes)
		LAZYADD(accessories, "[shell_state]-eyes-[eyes]")
	if(plating)
		LAZYADD(accessories, "[shell_state]-shell-[plating]")
	set_shell_accessories(accessories)
	can_pick_shell = FALSE

MSG_DEF_SELF(drone_ability/shell_picked, "you already selected a shell or this drone type isn't customizable")

CAPABILITY_DEF(drone_shell, CAP_DRONE_SHELL, key = NONE)

/datum/capability/def/drone_shell/entries()
	return list(
		op("pick_shell", label("Customize appearance"), menu(button = "Customize appearance", bind = "ability_robot_pick_shell"),
			needs(req(TYPE_PROC_REF(/mob/living/silicon/robot/drone, can_pick_shell_now), because = MSG(drone_ability/shell_picked))),
			asks(/datum/prompt/choice, fields = list("title" = "Customize Shell", "question" = "Select a shell. NOTE: You can only do this once during this drone-lifetime.", "choices" = computed(TYPE_PROC_REF(/mob/living/silicon/robot/drone, shell_choices))), step = "shell"),
			asks(/datum/prompt/choice, fields = list("title" = "Eye Color", "question" = "Select eye color:", "choices" = list("blue", "red", "orange", "green", "violet")), step = "eyes", when = TYPE_PROC_REF(/mob/living/silicon/robot/drone, shell_has_eyes)),
			asks(/datum/prompt/choice, fields = list("title" = "Eye Color", "question" = "Select plating color:", "choices" = list("blue", "red", "orange", "green", "brown")), step = "plating", when = TYPE_PROC_REF(/mob/living/silicon/robot/drone, shell_has_plating)),
			on_interrupt(TYPE_PROC_REF(/mob/living/silicon/robot/drone, shell_cancelled)),
			then(TYPE_PROC_REF(/mob/living/silicon/robot/drone, ability_pick_shell))))

/mob/living/silicon/robot/drone/proc/can_pick_shell_now(datum/act/op/A)
	return can_pick_shell

/// A drone is never named by its player.
/mob/living/silicon/robot/drone/may_pick_name()
	return FALSE

/mob/living/silicon/robot/drone/pick_module()
	return

CAPABILITIES(/mob/living/silicon/robot/drone)
	op("hat", item(/obj/item/clothing/head), stance(I_HELP), label("Put on hat"), then(PROC_REF(hat_put_on)))
	verb_entry(/mob/living/proc/ventcrawl)
	verb_entry(/mob/living/proc/hide)

/// In help stance, a hat goes on a drone that has none, before the cyborg item handling; one that wears a hat declines.
/mob/living/silicon/robot/drone/proc/hat_put_on(datum/act/op/A)
	if(hat)
		return OP_DECLINE
	var/mob/user = A.actor
	var/obj/item/held = A.held
	user.unEquip(held)
	place_on_head(held)
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " puts %I% on %T%."), item = held)

/// Drones' wiring is always reachable.
/mob/living/silicon/robot/drone/can_rewire()
	return TRUE

/mob/living/silicon/robot/drone/apply_upgrade(obj/item/borg/upgrade/U, mob/user)
	to_chat(user, span_danger("\The [src] is not compatible with \the [U]."))
	return FALSE

/// A drone's interface doesn't lock; an ID swipe on a dead drone reboots it.
/mob/living/silicon/robot/drone/swipe_id(obj/item/W, mob/user)
	if(stat != DEAD)
		return FALSE
	if(!CONFIG_GET(flag/allow_drone_spawn) || emagged || vitality() <= 0) //It's dead, Dave.
		to_chat(user, span_danger("The interface is fried, and a distressing burned smell wafts from the robot's interior. You're not rebooting this one."))
		return FALSE
	if(!allowed(user))
		to_chat(user, span_danger("Access denied."))
		return FALSE
	act_message(user, src, MSG_SELF(span_danger(">You swipe your ID card through %T%, attempting to reboot it.")), \
		MSG_OTHERS(span_danger("%U% swipes %THEIR% ID card through %T%, attempting to reboot it.")))
	var/drones = 0
	for(var/mob/living/silicon/robot/drone/D in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		drones++
	if(drones < CONFIG_GET(number/max_maint_drones))
		request_player()
	return TRUE

/mob/living/silicon/robot/drone/crowbar_act(mob/user, obj/item/tool)
	to_chat(user, span_danger("\The [src] is hermetically sealed. You can't open the case."))
	return ITEM_INTERACT_BLOCKING

/mob/living/silicon/robot/drone/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if(!client || stat == DEAD)
		to_chat(user, span_danger("There's not much point subverting this heap of junk."))
		return

	if(emagged)
		to_chat(src, span_danger("\The [user] attempts to load subversive software into you, but your hacked subroutines ignore the attempt."))
		to_chat(user, span_danger("You attempt to subvert [src], but the sequencer has no effect."))
		return

	to_chat(user, span_danger("You swipe the sequencer across [src]'s interface and watch its eyes flicker."))
	to_chat(src, span_danger("You feel a sudden burst of malware loaded into your execute-as-root buffer. Your tiny brain methodically parses, loads and executes the script."))

	subvert_laws(user)

	to_chat(src, span_infoplain(span_bold("Obey these laws:\n") + laws.get_formatted_laws()))
	to_chat(src, span_danger("ALERT: [user.real_name] is your new master. Obey your new laws and [user.p_their()] commands."))
	return 1

//DRONE LIFE/DEATH

/// The machine plan decides that a drone dies; the drone only chooses its
/// remains. Destroyed by damage, it breaks apart; shut down, it leaves an
/// intact shell that an ID swipe can reboot.
/mob/living/silicon/robot/drone/on_death(gibbed)
	. = ..()
	if(!gibbed && vitality() <= 0)
		gib()

//CONSOLE PROCS
/mob/living/silicon/robot/drone/proc/law_resync()
	if(stat != DEAD)
		if(emagged)
			to_chat(src, span_danger("You feel something attempting to modify your programming, but your hacked subroutines are unaffected."))
		else
			to_chat(src, span_danger("A reset-to-factory directive packet filters through your data connection, and you obediently modify your programming to suit it."))
			full_law_reset()
			show_laws()

/mob/living/silicon/robot/drone/proc/shut_down()
	if(stat != DEAD)
		if(emagged)
			to_chat(src, span_danger("You feel a system kill order percolate through your tiny brain, but it doesn't seem like a good idea to you."))
		else
			to_chat(src, span_danger("You feel a system kill order percolate through your tiny brain, and you obediently destroy yourself."))
			death()

/mob/living/silicon/robot/drone/proc/full_law_reset()
	clear_supplied_laws(1)
	clear_inherent_laws(1)
	clear_ion_laws(1)
	rel_set(src, nameof(laws), new law_type)

//Reboot procs.

/mob/living/silicon/robot/drone/proc/request_player()
	for(var/mob/observer/dead/O in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(jobban_isbanned(O, JOB_CYBORG))
			continue
		if(O.client)
			if(O.client.prefs.read_preference(/datum/preference/numeric/human/be_special) & BE_PAI) // migrated
				question(O.client)

/mob/living/silicon/robot/drone/proc/question(client/C)
	if(!C || jobban_isbanned(C,JOB_CYBORG))	return
	open_request(src, /datum/prompt/choice, PROC_REF(question_answered), answerer = C.mob, valid = PROC_REF(question_askable), title = "Maintenance drone reboot", question = "Someone is attempting to reboot a maintenance drone. Would you like to play as one?", choices = list("Yes", "No", "Never for this round"), buttons = TRUE, timeout = 0)

/// A ghost is offered a rebooting drone. Re-checked on the answer: still has a client, and the drone is still unoccupied.
/mob/living/silicon/robot/drone/proc/question_askable(datum/request/R)
	var/mob/answerer = R.answerer
	return answerer.client && !ckey

/mob/living/silicon/robot/drone/proc/question_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/answerer = A.request.answerer
	var/client/C = answerer.client
	var/response = A.answer.value
	if(response == "Yes")
		transfer_personality(C)
	else if (response == "Never for this round")
		C.prefs.update_preference_by_type(/datum/preference/numeric/human/be_special, C.prefs.read_preference(/datum/preference/numeric/human/be_special) ^ BE_PAI) // migrated

/mob/living/silicon/robot/drone/proc/transfer_personality(client/player)

	if(!player) return

	src.ckey = player.ckey

	if(player.mob && player.mob.mind)
		player.mob.mind.transfer_to(src)

	lawupdate = FALSE
	to_chat(src, span_infoplain(span_bold("Systems rebooted") + " Loading base pattern maintenance protocol... " + span_bold("loaded") + "."))
	full_law_reset()
	welcome_drone()

/mob/living/silicon/robot/drone/proc/welcome_drone()
	to_chat(src, span_infoplain(span_bold("You are a maintenance drone, a tiny-brained robotic repair machine") + "."))
	to_chat(src, span_infoplain("You have no individual will, no personality, and no drives or urges other than your laws."))
	to_chat(src, span_infoplain("Remember,  you are " + span_bold("lawed against interference with the crew") + ". Also remember, " + span_bold("you DO NOT take orders from the AI") + "."))
	to_chat(src, span_infoplain("Use " + span_bold("say ;Hello") + " to talk to other drones and " + span_bold("say Hello") + " to speak silently to your nearby fellows."))

/mob/living/silicon/robot/drone/add_robot_verbs()
	for(var/granted_path in silicon_subsystems)
		grant(src, granted_verb(granted_path), src)

/mob/living/silicon/robot/drone/remove_robot_verbs()
	for(var/granted_path in silicon_subsystems)
		revoke(src, granted_verb(granted_path), src)

/mob/living/silicon/robot/drone/construction/welcome_drone()
	to_chat(src, span_infoplain(span_bold("You are a construction drone, an autonomous engineering and fabrication system") + "."))
	to_chat(src, span_infoplain("You are assigned to a Sol Central construction project. The name is irrelevant. Your task is to complete construction and subsystem integration as soon as possible."))
	to_chat(src, span_infoplain("Use " + span_bold(":d") + " to talk to other drones and " + span_bold("say") + " to speak silently to your nearby fellows."))
	to_chat(src, span_infoplain(span_bold("You do not follow orders from anyone; not the AI, not humans, and not other synthetics") + "."))

/mob/living/silicon/robot/drone/construction/setup_module()
	..()
	flavor_text = "It's a bulky construction drone stamped with a Sol Central glyph."

/mob/living/silicon/robot/drone/mining/setup_module()
	..()
	flavor_text = "It's a bulky mining drone stamped with a Grayson logo."

