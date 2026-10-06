/obj/item/capture_crystal
	name = "capture crystal"
	desc = "A silent, unassuming crystal in what appears to be some kind of steel housing."
	icon = 'icons/obj/capture_crystal_vr.dmi'
	icon_state = "inactive"
	drop_sound = SFX_ITEMS_DROP_RING
	pickup_sound = SFX_ITEMS_PICKUP_RING
	throwforce = 0
	force = 0
	actions_types = list(/datum/action/item_action/command)
	w_class = ITEMSIZE_SMALL

	var/active = FALSE					//Is it set up?
	var/mob/living/owner				//Reference to the owner
	var/mob/living/bound_mob			//Reference to our bound mob
	var/spawn_mob_type					//The kind of mob an inactive crystal will try to spawn when activated
	var/activate_cooldown = 30 SECONDS	//How long do we wait between unleashing and recalling
	COOLDOWN_DECLARE(activate_cooldown_until) //Automatically set by things that try to move the bound mob or capture things
	var/empty_icon = "empty"
	var/full_icon = "full"
	var/spawn_mob_name = "A mob"
	var/capture_chance_modifier = 1		//So we can have special subtypes with different capture rates!
	var/loadout = FALSE

/obj/item/capture_crystal/Initialize(mapload)
	. = ..()
	update_icon()

//Let's make sure we clean up our references and things if the crystal goes away (such as when it's digested)
// the bound mob is unleashed and freed of its command.
/obj/item/capture_crystal/on_destroy(force)
	if(bound_mob)
		if(bound_mob in contents)
			unleash()
		to_chat(bound_mob, span_notice("You feel like yourself again. You are no longer under the influence of \the [src]'s command."))
		bound_mob.capture_caught = FALSE
	..()

/obj/item/capture_crystal/examine(user)
	. = ..()
	if(user == owner && bound_mob)
		. += span_notice("[bound_mob]'s crystal")
		if(isanimal(bound_mob))
			. += span_notice("[round(bound_mob.vitality() * 100)]%")
		if(bound_mob.identity().ooc_notes)
			. += span_deptradio("OOC Notes:") + " <a href='byond://?src=\ref[bound_mob];ooc_notes=1'>\[View\]</a> - <a href='byond://?src=\ref[src];print_ooc_notes_chat=1'>\[Print\]</a>"
		. += span_deptradio("<a href='byond://?src=\ref[bound_mob];vore_prefs=1'>\[Mechanical Vore Preferences\]</a>")

//Command! This lets the owner toggle hostile on AI controlled mobs, or send a silent command message to your bound mob, wherever they may be.
/obj/item/capture_crystal/ui_action_click(mob/user, actiontype)
	if(!ismob(loc))
		return
	var/mob/living/M = src.loc
	if(M != owner)
		to_chat(M, span_notice("\The [src] emits an unpleasant tone... It does not respond to your command."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else if(!bound_mob)
		to_chat(M, span_notice("\The [src] emits an unpleasant tone... There is nothing to command."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else if(isanimal(bound_mob) && !bound_mob.client)
		if(bound_mob.ai_brain)
			var/datum/ai_brain/AI = bound_mob.ai_brain
			AI.set_hostile(!AI.get_hostile())
			to_chat(M, span_notice("\The [bound_mob] is now [AI.get_hostile() ? "hostile" : "passive"]."))
			log_admin("[key_name_admin(M)] set [bound_mob] to [AI.get_hostile()].")
	else if(bound_mob.client)
		open_request(src, /datum/prompt/text/crystal_command, PROC_REF(command_entered), answerer = user)
	else
		to_chat(M, span_notice("\The [src] emits an unpleasant tone... \The [bound_mob] is unresponsive."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)

//Lets the owner get AI controlled bound mobs to follow them, or tells player controlled mobs to follow them.
/obj/item/capture_crystal/proc/follow_owner_effect(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ismob(loc))
		return
	var/mob/living/M = src.loc
	if(M != owner)
		to_chat(M, span_notice("\The [src] emits an unpleasant tone... It does not respond to your command."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else if(!bound_mob || bound_mob.stat != CONSCIOUS)
		to_chat(M, span_notice("\The [src] emits an unpleasant tone... \The [bound_mob] is not able to hear your command."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else if(bound_mob.client)
		to_chat(bound_mob, span_notice("\The [owner] wishes for you to follow them."))
	else if(bound_mob in contents)
		if(!bound_mob.ai_brain)
			to_chat(M, span_notice("\The [src] emits an unpleasant tone... \The [bound_mob] is not able to follow your command."))
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			return
		var/datum/ai_brain/AI = bound_mob.ai_brain
		var/mob/current_leader = AI.get_leader()
		if(current_leader)
			to_chat(M, span_notice("\The [src] chimes~ \The [bound_mob] stopped following [current_leader]."))
			AI.lose_follow()
		else
			AI.set_follow(M)
			to_chat(M, span_notice("\The [src] chimes~ \The [bound_mob] started following [M]."))
	else if(!(bound_mob in view(M)))
		to_chat(M, span_notice("\The [src] emits an unpleasant tone... \The [bound_mob] is not able to hear your command."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		if(!bound_mob.ai_brain)
			to_chat(M, span_notice("\The [src] emits an unpleasant tone... \The [bound_mob] is not able to follow your command."))
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			return
		var/datum/ai_brain/AI = bound_mob.ai_brain
		var/mob/current_leader = AI.get_leader()
		if(current_leader)
			to_chat(M, span_notice("\The [src] chimes~ \The [bound_mob] stopped following [current_leader]."))
			AI.lose_follow()
		else
			AI.set_follow(M)
			to_chat(M, span_notice("\The [src] chimes~ \The [bound_mob] started following [M]."))

//Don't really want people 'haha funny' capturing and releasing one another willy nilly. So! If you wanna release someone, you gotta destroy the thingy.
//(Which is consistent with how it works with digestion anyway.)
/obj/item/capture_crystal/proc/destroy_crystal_effect(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ismob(loc))
		return
	var/mob/living/M = src.loc
	if(M != owner)
		to_chat(M, span_notice("\The [src] is too hard for you to break."))
	else
		// Render labels while the crystal exists; announce only an accepted consumption.
		var/self_message = msg_fill("%T% cracks and disintegrates in your hand.", M, src)
		var/others_message = msg_fill("%U% crushes %T% into dust...", M, src)
		if(consume(src, user))
			act_message(M, null, MSG_SELF(self_message), MSG_OTHERS(others_message))

//If you catch something/someone and want to give it to someone else though, that's fine.
/obj/item/capture_crystal/proc/release_ownership_effect(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ismob(loc))
		return
	var/mob/living/M = src.loc
	if(M != owner)
		to_chat(M, span_notice("\The [src] emits an unpleasant tone... It does not respond to your command."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else
		act_message(M, src, MSG_SELF("%T% flickers in your hand and emits a little tone."), MSG_OTHERS("%T% flickers in %U%'s hand and emits a little tone."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_OUT)
		rel_clear(src, nameof(owner))

//Let's make inviting ghosts be an option you can do instead of an automatic thing!
/// A command to the bound mob. Re-checked on the answer: the crystal is still carried by its owner and still bound.
/datum/prompt/text/crystal_command
	title = "Command"
	question = "What is your command?"
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	timeout = 0

/datum/prompt/text/crystal_command/recheck_extra()
	var/obj/item/capture_crystal/crystal = owner
	if(answerer != crystal.owner || !crystal.bound_mob)
		return "not the owner"
	return null

/obj/item/capture_crystal/proc/command_entered(datum/act/request/A)
	if(!A.answer)
		if(A.request.outcome == REQ_CANCELLED && isnull(A.request.value) && !QDELETED(A.request.answerer))
			to_chat(A.request.answerer, span_notice("You decided against it."))
		return
	var/mob/living/M = A.request.answerer
	var/transmit_msg = A.answer.value
	if(length(transmit_msg) >= MAX_MESSAGE_LEN)
		to_chat(M, span_danger("Your message was TOO LONG!:[transmit_msg]"))
		return
	transmit_msg = sanitize(transmit_msg, max_length = MAX_MESSAGE_LEN)
	if(isnull(transmit_msg))
		to_chat(M, span_notice("You decided against it."))
		return
	to_chat(bound_mob, span_notice("\The [owner] commands, '[transmit_msg]'"))
	to_chat(M, span_notice("Your command has been transmitted, '[transmit_msg]'"))
	log_admin("[key_name_admin(M)] sent the command, '[transmit_msg]' to [bound_mob].")

/obj/item/capture_crystal/proc/invite_ghost_effect(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ismob(loc))
		return
	var/mob/living/U = src.loc
	if(!bound_mob)
		to_chat(U, span_notice("\The [src] emits an unpleasant tone... There is nothing to enhance."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		return
	else if(U != owner)
		to_chat(U, span_notice("\The [src] emits an unpleasant tone... It does not respond to your command."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		return
	else if(bound_mob.client || !isanimal(bound_mob))
		to_chat(U, span_notice("\The [src] emits an unpleasant tone... \The [bound_mob] is not eligable for enhancement."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_PROBLEM)
		return		//Need to type cast the mob so it can detect ghostjoin
	var/mob/living/simple_mob/M = bound_mob
	if(M.ghostjoin)
		M.ghostjoin = FALSE
		to_chat(U, span_notice("\The [bound_mob] is no longer eligable to be joined by ghosts."))
	else
		open_request(src, /datum/prompt/choice/crystal_ghost_invite, PROC_REF(ghost_invite_answered), answerer = U, question = "Do you want to offer your [bound_mob] up to ghosts to play as? There is no way undo this once a ghost takes over.", bound = M)

/// Offering the bound mob to ghosts. Re-checked on the answer: the crystal is still carried by its owner, still bound to that mob, which has no player.
/datum/prompt/choice/crystal_ghost_invite
	title = "Invite ghosts?"
	choices = list("No", "Yes")
	buttons = TRUE
	timeout = 0
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	var/mob/living/simple_mob/bound

CAPABILITIES(/datum/prompt/choice/crystal_ghost_invite)
	ref_one(nameof(bound), /mob/living/simple_mob)

/datum/prompt/choice/crystal_ghost_invite/prepare(datum/act/A)
	..()
	var/mob/living/simple_mob/captured_bound = bound
	rel_clear(src, nameof(bound))
	rel_set(src, nameof(bound), captured_bound)

/datum/prompt/choice/crystal_ghost_invite/recheck_extra()
	if(QDELETED(bound))
		return "gone"
	var/obj/item/capture_crystal/crystal = owner
	if(bound != crystal.bound_mob || answerer != crystal.owner || bound.client)
		return "not eligible"
	return null

/obj/item/capture_crystal/proc/ghost_invite_answered(datum/act/request/A)
	var/datum/prompt/choice/crystal_ghost_invite/ask = A.request
	if(!A.answer)
		if(ask.outcome == REQ_CANCELLED && (!isnull(ask.value) || QDELETED(ask.bound)) && !QDELETED(ask.answerer))
			to_chat(ask.answerer, span_notice("You decided against it."))
		return
	var/mob/living/U = ask.answerer
	var/mob/living/simple_mob/M = ask.bound
	if(ask.value == "No")
		to_chat(U, span_notice("You decided against it."))
		return
	M.ghostjoin = TRUE
	to_chat(U, span_notice("\The [bound_mob] is now eligable to be joined by ghosts. It will need to be out of the crystal to be able to be joined."))

DECLARE_APPEARANCE_PROC(/obj/item/capture_crystal, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/capture_crystal/appearance_overlays()
	. = list()
	. += ..()
	if(spawn_mob_type)
		icon_state = full_icon
	else if(!bound_mob)
		icon_state = "inactive"
	else if(bound_mob in contents)
		icon_state = full_icon
	else
		icon_state = empty_icon
	if(!cooldown_check())
		icon_state = "[icon_state]-busy"

/// Starts the activation cooldown; the busy sprite is fixed once, when it ends.
/obj/item/capture_crystal/proc/start_activate_cooldown()
	COOLDOWN_START(src, activate_cooldown_until, activate_cooldown)
	after(src, activate_cooldown, TYPE_PROC_REF(/atom, update_icon), key = "cooldown_icon")

/obj/item/capture_crystal/proc/cooldown_check()
	if(!COOLDOWN_FINISHED(src, activate_cooldown_until))
		return FALSE
	else return TRUE

/obj/item/capture_crystal/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(bound_mob)
		if(!bound_mob.devourable)	//Don't eat if prefs are bad
			return ITEM_INTERACT_FAILURE
		if(user.zone_sel.selecting == "mouth")	//Click while targetting the mouth and you eat/feed the stored mob to whoever you clicked on
			if(bound_mob in contents)
				act_message(user, src, others = "%U% moves %T% to [M]'s [M.vore_selected]...")
				M.perform_the_nom(M, bound_mob, M, M.vore_selected)
				return ITEM_INTERACT_SUCCESS
	else if(M == user)		//You don't have a mob, you ponder the orb instead of trying to capture yourself
		act_message(user, src, MSG_SELF("You ponder %T%..."), MSG_OTHERS("%U% ponders %T%..."))
		return ITEM_INTERACT_FAILURE
	else if (cooldown_check())	//Try to capture someone without throwing
		act_message(user, src, others = "%U% taps \the [M] with %T%.")
		activate(user, M)
		return ITEM_INTERACT_SUCCESS
	else
		to_chat(user, span_notice("\The [src] emits an unpleasant tone... It is not ready yet."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		return ITEM_INTERACT_FAILURE

//Tries to unleash or recall your stored mob
DECLARE_INTERACTIONS(/obj/item/capture_crystal, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/capture_crystal/proc/interaction_self(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(loadout && !bound_mob)
		to_chat(user, span_notice("\The [src] emits an unpleasant tone... It is not ready yet."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_PROBLEM)
		return TRUE
	if(bound_mob && !owner)
		if(bound_mob == user)
			to_chat(user, span_notice("\The [src] emits an unpleasant tone... It does not activate for you."))
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			return TRUE
		open_request(src, /datum/prompt/choice, PROC_REF(claim_answered), answerer = user, title = "Claim ownership", question = "\The [src] hasn't got an owner. It has \the [bound_mob] registered to it. Would you like to claim this as yours?", buttons = TRUE, choices = list("No", "Yes"), ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
		return TRUE
	use_crystal(user)
	return TRUE

/obj/item/capture_crystal/proc/claim_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/user = A.request.answerer
	if(A.answer.value == "Yes" && !owner && bound_mob && bound_mob != user)
		rel_set(src, nameof(owner), user)
	use_crystal(user)

/obj/item/capture_crystal/proc/use_crystal(mob/living/user)
	if(!cooldown_check())
		to_chat(user, span_notice("\The [src] emits an unpleasant tone... It is not ready yet."))
		if(bound_mob)
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_PROBLEM)
		else
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else if(user == bound_mob)	//You can't recall yourself
		to_chat(user, span_notice("\The [src] emits an unpleasant tone... It does not activate for you."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else if(!active)
		activate(user)
	else
		determine_action(user)

//Make it so the crystal knows if its mob references get deleted to make sure things get cleaned up
/obj/item/capture_crystal/proc/knowyoursignals(mob/living/M, mob/living/U)
	observe(M, /datum/notice/qdeleting, src, then(PROC_REF(mob_was_deleted)))
	observe(U, /datum/notice/qdeleting, src, then(PROC_REF(owner_was_deleted)))

//The basic capture command does most of the registration work.
/obj/item/capture_crystal/proc/capture(mob/living/M, mob/living/U)
	if(!M.capture_crystal || M.capture_caught)
		to_chat(U, span_warning("This creature is not suitable for capture."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		return
	knowyoursignals(M, U)
	rel_set(src, nameof(owner), U)
	if(isanimal(M))
		var/mob/living/simple_mob/S = M
		S.revivedby = U.name
	if(!bound_mob)
		rel_set(src, nameof(bound_mob), M)
		bound_mob.capture_caught = TRUE
		persist_storable = FALSE
	desc = "A glowing crystal in what appears to be some kind of steel housing."

//Determines the capture chance! So you can't capture AI mobs if they're perfectly healthy and all that
/obj/item/capture_crystal/proc/capture_chance(mob/living/M, user)
	if(capture_chance_modifier >= 100)		//Master crystal always work
		return 100
	var/capture_chance = ((1 - M.vitality()) * 100)	//Inverted health percent! 100% = 0%
	//So I don't know how this works but here's a kind of explanation
	//Basic chance + ((Mob's max health - minimum calculated health) / (Max allowed health - Min allowed health)*(Chance at Max allowed health - Chance at minimum allowed health)
	capture_chance += 35 + ((M.get_endurance() - 5)/ (1000-5)*(-100 - 35))
	//Basically! Mobs over 1000 max health will be unable to be caught without using status effects.
	//Thanks Aronai!
	var/effect_count = 0	//This will give you a smol chance to capture if you have applied status effects, even if the chance would ordinarily be <0
	if(M.stat == UNCONSCIOUS)
		capture_chance += 0.1
		effect_count += 1
	else if(M.stat == CONSCIOUS)
		capture_chance *= 0.9
	else
		capture_chance = 0
	if(M.has_status(STAT_WEAKENED))			//Haha you fall down
		capture_chance += 0.1
		effect_count += 1
	if(M.has_status(STAT_STUNNED))			//What's the matter???
		capture_chance += 0.1
		effect_count += 1
	if(M.on_fire)			//AAAAAAAA
		capture_chance += 0.1
		effect_count += 1
	if(M.has_status(STAT_PARALYZED))			//Oh noooo
		capture_chance += 0.1
		effect_count += 1
	if((M.ai_brain && M.ai_brain.primary_threat ? STANCE_FIGHT : STANCE_IDLE) == STANCE_IDLE)	//SNEAK ATTACK???
		capture_chance += 0.1
		effect_count += 1

	capture_chance *= capture_chance_modifier

	if(capture_chance <= 0)
		capture_chance = 0 + effect_count
		if(capture_chance <= 0)
			capture_chance = 0
			to_chat(user, span_notice("There's no chance... It needs to be weaker."))

	start_activate_cooldown()
	log_admin("[user] threw a capture crystal at [M] and got [capture_chance]% chance to catch.")
	return capture_chance

//Handles checking relevent bans, preferences, and asking the player if they want to be caught
/obj/item/capture_crystal/proc/capture_player(mob/living/M, mob/living/U)
	if(jobban_isbanned(M, JOB_GHOSTROLES))
		to_chat(U, span_warning("This creature is not suitable for capture."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else if(!M.capture_crystal || M.capture_caught)
		to_chat(U, span_warning("This creature is not suitable for capture."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else
		if(!isnull(U) && QDELETED(U))
			return
		open_request(src, /datum/prompt/choice/crystal_capture, PROC_REF(ask_capture_sure), answerer = M, question = "Would you like to be caught by in [src] by [U]? You will be bound to their will.", capturer = U)
		return
	to_chat(U, span_warning("This creature is too strong willed to be captured."))
	play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)

/// Consent to being caught, asked twice. Re-checked on each answer: still conscious, the crystal
/// still empty, still catchable, the capturer within 7 tiles. A no, a cancel or a failed check
/// tells the capturer they were refused.
/datum/prompt/choice/crystal_capture
	title = "Become Caught"
	choices = list("No", "Yes")
	buttons = TRUE
	timeout = 0
	var/mob/living/capturer
	var/capturer_required = FALSE

CAPABILITIES(/datum/prompt/choice/crystal_capture)
	ref_one(nameof(capturer), /mob/living)

/datum/prompt/choice/crystal_capture/prepare(datum/act/A)
	..()
	var/mob/living/captured_capturer = capturer
	capturer_required = !isnull(captured_capturer)
	rel_clear(src, nameof(capturer))
	rel_set(src, nameof(capturer), captured_capturer)

/datum/prompt/choice/crystal_capture/recheck_extra()
	if(capturer_required && QDELETED(capturer))
		return "gone"
	var/mob/living/M = answerer
	if(!istype(M) || M.stat != CONSCIOUS)
		return "not conscious"
	var/obj/item/capture_crystal/crystal = owner
	if(crystal.bound_mob || !M.capture_crystal || M.capture_caught || get_dist(capturer, M) > 7)
		return "not catchable"
	return null

/obj/item/capture_crystal/proc/ask_capture_sure(datum/act/request/A)
	var/datum/prompt/choice/crystal_capture/ask = A.request
	if(QDELETED(ask.answerer))
		return
	if(!A.answer || ask.value != "Yes")
		if(ask.outcome == REQ_CANCELLED || A.answer)
			capture_refused(ask.capturer)
		return
	open_request(src, /datum/prompt/choice/crystal_capture, PROC_REF(capture_answered), answerer = ask.answerer, question = "Are you really sure? The only way to undo this is to OOC escape while you're in the crystal.", capturer = ask.capturer)

/obj/item/capture_crystal/proc/capture_refused(mob/living/U)
	if(U)
		to_chat(U, span_warning("This creature is too strong willed to be captured."))
	play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)

/obj/item/capture_crystal/proc/capture_answered(datum/act/request/A)
	var/datum/prompt/choice/crystal_capture/ask = A.request
	if(QDELETED(ask.answerer))
		return
	if(!A.answer || ask.value != "Yes")
		if(ask.outcome == REQ_CANCELLED || A.answer)
			capture_refused(ask.capturer)
		return
	var/mob/living/M = ask.answerer
	var/mob/living/U = ask.capturer
	log_admin("[key_name(M)] has agreed to become caught by [key_name(U)].")
	capture(M, U)
	recall(U)

//The clean up procs!
/obj/item/capture_crystal/proc/mob_was_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	unobserve(bound_mob, /datum/notice/qdeleting, src)
	unobserve(owner, /datum/notice/qdeleting, src)
	bound_mob.capture_caught = FALSE
	rel_clear(src, nameof(bound_mob))
	rel_clear(src, nameof(owner))
	active = FALSE
	persist_storable = TRUE
	update_icon()

/obj/item/capture_crystal/proc/owner_was_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	unobserve(owner, /datum/notice/qdeleting, src)
	rel_clear(src, nameof(owner))
	active = FALSE
	update_icon()

//If the crystal hasn't been set up, it does this
/obj/item/capture_crystal/proc/activate(mob/living/user, target)
	if(!cooldown_check())		//Are we ready to do things yet?
		to_chat(user, span_notice("\The [src] clicks unsatisfyingly... It is not ready yet."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		return
	if(spawn_mob_type && !bound_mob)			//We don't already have a mob, but we know what kind of mob we want
		rel_set(src, nameof(bound_mob), new spawn_mob_type(src)) //Well let's spawn it then!
		bound_mob.faction = user.faction
		spawn_mob_type = null
		capture(bound_mob, user)
	if(bound_mob)								//We have a mob! Let's finish setting up.
		act_message(user, src, MSG_SELF("%T% grows warm in your hand, something inside is awake."), MSG_OTHERS("%T% clicks, and then emits a small chime."))
		active = TRUE
		if(!owner)								//Do we have an owner? It's pretty unlikely that this would ever happen! But it happens, let's claim the crystal.
			rel_set(src, nameof(owner), user)
			if(isanimal(bound_mob))
				var/mob/living/simple_mob/S = bound_mob
				S.revivedby = user.name
		determine_action(user, target)
		return
	else if(isliving(target))						//So we don't have a mob, let's try to claim one! Is the target a mob?
		var/mob/living/M = target
		start_activate_cooldown()
		if(M.capture_caught)					//Can't capture things that were already caught.
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			to_chat(user, span_notice("\The [src] clicks unsatisfyingly... \The [M] is already under someone else's control."))
			return
		else if(M.stat == DEAD)						//Is it dead? We can't influence dead things.
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			to_chat(user, span_notice("\The [src] clicks unsatisfyingly... \The [M] is not in a state to be captured."))
			return
		else if(M.client)							//Is it player controlled?
			capture_player(M, user)				//We have to do things a little differently if so.
			return
		else if(!isanimal(M))						//So it's not player controlled, but it's also not a simplemob?
			to_chat(user, span_warning("This creature is not suitable for capture."))
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			return
		var/mob/living/simple_mob/S = M
		if(!S.ai_brain)						//We don't really want to capture simplemobs that don't have an AI
			to_chat(user, span_warning("This creature is not suitable for capture."))
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		else if(prob(capture_chance(S, user)))				//OKAY! So we have an NPC simplemob with an AI, let's calculate its capture chance! It varies based on the mob's condition.
			capture(S, user)					//We did it! Woo! We capture it!
			act_message(user, src, MSG_SELF("Alright! \The [S] was caught!"), MSG_OTHERS("%T% clicks, and then emits a small chime."))
			recall(user)
			active = TRUE
		else									//Shoot, it didn't work and now it's mad!!!
			S.ai_brain.go_wake()
			S.ai_brain.give_target(user, TRUE)
			user.visible_message("\The [src] bonks into \the [S], angering it!")
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			to_chat(user, span_notice("\The [src] clicks unsatisfyingly."))
		update_icon()
		return
	//The target is not a mob, so let's not do anything.
	play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	to_chat(user, span_notice("\The [src] clicks unsatisfyingly."))

//We're using the crystal, but what will it do?
/obj/item/capture_crystal/proc/determine_action(mob/living/U, T)
	if(!cooldown_check())	//Are we ready yet?
		to_chat(U, span_notice("\The [src] clicks unsatisfyingly... It is not ready yet."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		return				//No
	if(bound_mob in contents)	//Do we have our mob?
		if(T)
			unleash(U, T)		//Yes, let's let it out!
		else
			unleash(U)
	else if (bound_mob)			//Do we HAVE a mob?
		recall(U)				//Yes, let's try to put it back in the crystal
	else						//No we don't have a mob, let's reset the crystal.
		to_chat(U, span_notice("\The [src] clicks unsatisfyingly."))
		active = FALSE
		update_icon()
		rel_clear(src, nameof(owner))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)

//Let's try to call our mob back!
/obj/item/capture_crystal/proc/recall(mob/living/user)
	if(bound_mob in view(user))		//We can only recall it if we can see it
		var/turf/turfmemory = get_turf(bound_mob)
		if(isanimal(bound_mob) && bound_mob.ai_brain)
			var/mob/living/simple_mob/M = bound_mob
			M.ai_brain.go_sleep()	//AI doesn't need to think when it's in the crystal
		bound_mob.forceMove(src)
		start_activate_cooldown()
		act_message(bound_mob, src, MSG_SELF("%T% pulls you back into confinement in a flash of light!!!"), MSG_OTHERS("\The [user]'s [src] flashes, disappearing %U% in an instant!!!"))
		animate_action(turfmemory)
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_IN)
		update_icon()
	else
		to_chat(user, span_notice("\The [src] clicks and emits a small, unpleasant tone. \The [bound_mob] cannot be recalled."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)

//Let's let our mob out!
/obj/item/capture_crystal/proc/unleash(mob/living/user, atom/target)
	if(!user && !target)			//We got thrown but we're not sure who did it, let's go to where the crystal is
		var/drop_loc = get_turf(src)
		if (drop_loc)
			bound_mob.forceMove(drop_loc)
		return
	if(!target)						//We know who wants to let us out, but they didn't say where, so let's drop us on them
		bound_mob.forceMove(user.drop_location())
	else							//We got thrown! Let's go where we got thrown
		bound_mob.forceMove(target.drop_location())
	start_activate_cooldown()
	if(isanimal(bound_mob))
		var/mob/living/simple_mob/M = bound_mob
		M.ai_brain.go_wake()		//Okay it's time to do work, let's wake up!
	bound_mob.faction = owner.faction	//Let's make sure we aren't hostile to our owner or their friends
	act_message(bound_mob, src, MSG_SELF("The world around you rematerialize as you are unleashed from %T% next to \the [user]. You feel a strong compulsion to enact \the [owner]'s will."), MSG_OTHERS("\The [user]'s [src] flashes, %U% appears in an instant!!!"))
	animate_action(get_turf(bound_mob))
	play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_OUT)
	update_icon()

//Let's make a flashy sparkle when someone appears or disappears!
/obj/item/capture_crystal/proc/animate_action(atom/thing)
	var/image/coolanimation = image('icons/obj/capture_crystal_vr.dmi', null, "animation")
	coolanimation.plane = PLANE_LIGHTING_ABOVE
	thing.overlays += coolanimation
	after(src, 1.1 SECOND, PROC_REF(animate_action_finished), with = list(thing, coolanimation))

/obj/item/capture_crystal/proc/animate_action_finished(atom/thing,image/coolanimation)
	SHOULD_NOT_OVERRIDE(TRUE)
	PROTECTED_PROC(TRUE)
	thing.overlays -= coolanimation
	spent(coolanimation)

//IF the crystal somehow ends up in a tummy and digesting with a bound mob who doesn't want to be eaten, let's move them to the ground
/obj/item/capture_crystal/digest_act(atom/movable/item_storage = null)
	if(bound_mob)
		if((bound_mob in contents) && !bound_mob.devourable)
			bound_mob.forceMove(src.drop_location())
	return ..()

//We got thrown! Let's figure out what to do
/obj/item/capture_crystal/throw_at(atom/target, range, speed, mob/thrower, spin = TRUE, datum/callback/callback)
	. = ..()
	if(target == bound_mob && thrower != bound_mob)		//We got thrown at our bound mob (and weren't thrown by the bound mob) let's ignore the cooldown and just put them back in
		recall(thrower)
	else if(!cooldown_check())		//OTHERWISE let's obey the cooldown
		to_chat(thrower, span_notice("\The [src] emits an soft tone... It is not ready yet."))
		if(bound_mob)
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_PROBLEM)
		else
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else if(!active)					//The ball isn't set up, let's try to set it up.
		if(isliving(target))	//We're hitting a mob, let's try to capture it.
			after(src, 1 SECONDS, PROC_REF(activate), with = list(thrower, target))
			return
		after(src, 1 SECONDS, PROC_REF(activate), with = list(thrower, src))
	else if(!bound_mob)				//We hit something else, and we don't have a mob, so we can't really do anything!
		to_chat(thrower, span_notice("\The [src] clicks unpleasantly..."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	else if(bound_mob in contents)	//We have our mob! Let's try to let it out.
		after(src, 1 SECONDS, PROC_REF(unleash), with = list(thrower, src))
	else						//Our mob isn't here, we can't do anything.
		to_chat(thrower, span_notice("\The [src] clicks unpleasantly..."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)

/obj/item/capture_crystal/basic

/obj/item/capture_crystal/great
	name = "great capture crystal"
	capture_chance_modifier = 1.5

/obj/item/capture_crystal/ultra
	name = "ultra capture crystal"
	capture_chance_modifier = 2

/obj/item/capture_crystal/master
	name = "master capture crystal"
	capture_chance_modifier = 100

/obj/item/capture_crystal/cass
	spawn_mob_type = /mob/living/simple_mob/vore/woof/cass
/obj/item/capture_crystal/adg
	spawn_mob_type = /mob/living/simple_mob/mechanical/mecha/combat/gygax/dark/advanced
/obj/item/capture_crystal/bigdragon
	spawn_mob_type = /mob/living/simple_mob/vore/bigdragon
/obj/item/capture_crystal/bigdragon/friendly
	spawn_mob_type = /mob/living/simple_mob/vore/bigdragon/friendly
/obj/item/capture_crystal/teppi
	spawn_mob_type = /mob/living/simple_mob/vore/alienanimals/teppi
/obj/item/capture_crystal/broodmother
	spawn_mob_type = /mob/living/simple_mob/animal/giant_spider/broodmother
/obj/item/capture_crystal/skeleton
	spawn_mob_type = /mob/living/simple_mob/vore/alienanimals/skeleton
/obj/item/capture_crystal/dustjumper
	spawn_mob_type = /mob/living/simple_mob/vore/alienanimals/dustjumper

/obj/item/capture_crystal/random
	var/static/list/possible_mob_types = list(
		list(/mob/living/simple_mob/animal/goat),
		list(
			/mob/living/simple_mob/animal/passive/bird,
			/mob/living/simple_mob/animal/passive/bird/azure_tit,
			/mob/living/simple_mob/animal/passive/bird/black_bird,
			/mob/living/simple_mob/animal/passive/bird/european_robin,
			/mob/living/simple_mob/animal/passive/bird/goldcrest,
			/mob/living/simple_mob/animal/passive/bird/ringneck_dove,
			/mob/living/simple_mob/animal/passive/bird/parrot,
			/mob/living/simple_mob/animal/passive/bird/parrot/black_headed_caique,
			/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar,
			/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/blue,
			/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/bluegreen,
			/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel,
			/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/grey,
			/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/white,
			/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/yellowish,
			/mob/living/simple_mob/animal/passive/bird/parrot/eclectus,
			/mob/living/simple_mob/animal/passive/bird/parrot/grey_parrot,
			/mob/living/simple_mob/animal/passive/bird/parrot/kea,
			/mob/living/simple_mob/animal/passive/bird/parrot/pink_cockatoo,
			/mob/living/simple_mob/animal/passive/bird/parrot/sulphur_cockatoo,
			/mob/living/simple_mob/animal/passive/bird/parrot/white_caique,
			/mob/living/simple_mob/animal/passive/bird/parrot/white_cockatoo
		),
		list(
			/mob/living/simple_mob/animal/passive/cat,
			/mob/living/simple_mob/animal/passive/cat/black
		),
		list(/mob/living/simple_mob/animal/passive/chick),
		list(/mob/living/simple_mob/animal/passive/cow),
		list(/mob/living/simple_mob/animal/passive/dog/brittany),
		list(/mob/living/simple_mob/animal/passive/dog/corgi),
		list(/mob/living/simple_mob/animal/passive/dog/tamaskan),
		list(/mob/living/simple_mob/animal/passive/fox),
		list(/mob/living/simple_mob/animal/passive/hare),
		list(/mob/living/simple_mob/animal/passive/lizard),
		list(/mob/living/simple_mob/animal/passive/mouse),
		list(/mob/living/simple_mob/animal/passive/mouse/jerboa),
		list(/mob/living/simple_mob/animal/passive/opossum),
		list(/mob/living/simple_mob/animal/passive/pillbug),
		list(/mob/living/simple_mob/animal/passive/snake),
		list(/mob/living/simple_mob/animal/passive/tindalos),
		list(/mob/living/simple_mob/animal/passive/yithian),
		list(
			/mob/living/simple_mob/vore/wolf,
			/mob/living/simple_mob/vore/wolf/direwolf
			),
		list(/mob/living/simple_mob/vore/rabbit),
		list(/mob/living/simple_mob/vore/redpanda),
		list(/mob/living/simple_mob/vore/woof),
		list(/mob/living/simple_mob/vore/fennec),
		list(/mob/living/simple_mob/vore/fennix),
		list(/mob/living/simple_mob/vore/hippo),
		list(/mob/living/simple_mob/vore/horse),
		list(/mob/living/simple_mob/vore/bee),
		list(
			/mob/living/simple_mob/animal/space/bear,
			/mob/living/simple_mob/animal/space/bear/brown
			),
		list(
			/mob/living/simple_mob/vore/otie/feral,
			/mob/living/simple_mob/vore/otie/feral/chubby,
			/mob/living/simple_mob/vore/otie/red,
			/mob/living/simple_mob/vore/otie/red/chubby
			),
		list(/mob/living/simple_mob/animal/sif/diyaab),
		list(/mob/living/simple_mob/animal/sif/duck),
		list(/mob/living/simple_mob/animal/sif/frostfly),
		list(
			/mob/living/simple_mob/animal/sif/glitterfly =50,
			/mob/living/simple_mob/animal/sif/glitterfly/rare = 1
			),
		list(
			/mob/living/simple_mob/animal/sif/kururak = 10,
			/mob/living/simple_mob/animal/sif/kururak/leader = 1,
			/mob/living/simple_mob/animal/sif/kururak/hibernate = 2,
			),
		list(
			/mob/living/simple_mob/animal/sif/sakimm = 10,
			/mob/living/simple_mob/animal/sif/sakimm/intelligent = 1
			),
		list(/mob/living/simple_mob/animal/sif/savik) = 5,
		list(
			/mob/living/simple_mob/animal/sif/shantak = 10,
			/mob/living/simple_mob/animal/sif/shantak/leader = 1
			),
		list(/mob/living/simple_mob/animal/sif/siffet),
		list(/mob/living/simple_mob/animal/sif/tymisian),
		list(
			/mob/living/simple_mob/animal/giant_spider/electric = 5,
			/mob/living/simple_mob/animal/giant_spider/frost = 5,
			/mob/living/simple_mob/animal/giant_spider/hunter = 10,
			/mob/living/simple_mob/animal/giant_spider/ion = 5,
			/mob/living/simple_mob/animal/giant_spider/lurker = 10,
			/mob/living/simple_mob/animal/giant_spider/pepper = 10,
			/mob/living/simple_mob/animal/giant_spider/phorogenic = 10,
			/mob/living/simple_mob/animal/giant_spider/thermic = 5,
			/mob/living/simple_mob/animal/giant_spider/tunneler = 10,
			/mob/living/simple_mob/animal/giant_spider/webslinger = 5,
			/mob/living/simple_mob/animal/giant_spider/broodmother = 1),
		list(
			/mob/living/simple_mob/vore/wolf = 10,
			/mob/living/simple_mob/vore/wolf/direwolf = 5,
			/mob/living/simple_mob/vore/greatwolf = 1,
			/mob/living/simple_mob/vore/greatwolf/black = 1,
			/mob/living/simple_mob/vore/greatwolf/grey = 1
			),
		list(/mob/living/simple_mob/creature/strong),
		list(/mob/living/simple_mob/faithless/strong),
		list(/mob/living/simple_mob/animal/goat),
		list(
			/mob/living/simple_mob/animal/sif/shantak/leader = 1,
			/mob/living/simple_mob/animal/sif/shantak = 10),
		list(/mob/living/simple_mob/animal/sif/savik,),
		list(/mob/living/simple_mob/animal/sif/hooligan_crab),
		list(
			/mob/living/simple_mob/animal/space/alien = 50,
			/mob/living/simple_mob/animal/space/alien/drone = 40,
			/mob/living/simple_mob/animal/space/alien/sentinel = 25,
			/mob/living/simple_mob/animal/space/alien/sentinel/praetorian = 15,
			/mob/living/simple_mob/animal/space/alien/queen = 10,
			/mob/living/simple_mob/animal/space/alien/queen/empress = 5,
			/mob/living/simple_mob/animal/space/alien/queen/empress/mother = 1
			),
		list(/mob/living/simple_mob/animal/space/bats/cult/strong),
		list(
			/mob/living/simple_mob/animal/space/bear,
			/mob/living/simple_mob/animal/space/bear/brown
			),
		list(
			/mob/living/simple_mob/animal/space/carp = 50,
			/mob/living/simple_mob/animal/space/carp/large = 10,
			/mob/living/simple_mob/animal/space/carp/large/huge = 5
			),
		list(/mob/living/simple_mob/animal/space/goose),
		list(/mob/living/simple_mob/vore/jelly),
		list(/mob/living/simple_mob/animal/space/tree),
		list(
			/mob/living/simple_mob/vore/aggressive/corrupthound = 10,
			/mob/living/simple_mob/vore/aggressive/corrupthound/prettyboi = 1,
			),
		list(/mob/living/simple_mob/vore/aggressive/deathclaw),
		list(/mob/living/simple_mob/vore/aggressive/dino),
		list(/mob/living/simple_mob/vore/aggressive/dragon),
		list(/mob/living/simple_mob/vore/aggressive/dragon/virgo3b),
		list(/mob/living/simple_mob/vore/aggressive/frog),
		list(/mob/living/simple_mob/vore/aggressive/giant_snake),
		list(/mob/living/simple_mob/vore/aggressive/mimic),
		list(/mob/living/simple_mob/vore/aggressive/panther),
		list(/mob/living/simple_mob/vore/aggressive/rat),
		list(/mob/living/simple_mob/vore/bee),
		list(
			/mob/living/simple_mob/vore/sect_drone = 10,
			/mob/living/simple_mob/vore/sect_queen = 1
			),
		list(/mob/living/simple_mob/vore/solargrub),
		list(
			/mob/living/simple_mob/vore/oregrub = 5,
			/mob/living/simple_mob/vore/oregrub/lava = 1
			),
		list(/mob/living/simple_mob/vore/catgirl),
		list(/mob/living/simple_mob/vore/wolfgirl),
		list(
			/mob/living/simple_mob/vore/lamia,
			/mob/living/simple_mob/vore/lamia/albino,
			/mob/living/simple_mob/vore/lamia/albino/bra,
			/mob/living/simple_mob/vore/lamia/albino/shirt,
			/mob/living/simple_mob/vore/lamia/bra,
			/mob/living/simple_mob/vore/lamia/cobra,
			/mob/living/simple_mob/vore/lamia/cobra/bra,
			/mob/living/simple_mob/vore/lamia/cobra/shirt,
			/mob/living/simple_mob/vore/lamia/copper,
			/mob/living/simple_mob/vore/lamia/copper/bra,
			/mob/living/simple_mob/vore/lamia/copper/shirt,
			/mob/living/simple_mob/vore/lamia/green,
			/mob/living/simple_mob/vore/lamia/green/bra,
			/mob/living/simple_mob/vore/lamia/green/shirt,
			/mob/living/simple_mob/vore/lamia/zebra,
			/mob/living/simple_mob/vore/lamia/zebra/bra,
			/mob/living/simple_mob/vore/lamia/zebra/shirt
			),
		list(
			/mob/living/simple_mob/humanoid/merc = 100,
			/mob/living/simple_mob/humanoid/merc/melee/sword = 50,
			/mob/living/simple_mob/humanoid/merc/ranged = 25,
			/mob/living/simple_mob/humanoid/merc/ranged/grenadier = 1,
			/mob/living/simple_mob/humanoid/merc/ranged/ionrifle = 10,
			/mob/living/simple_mob/humanoid/merc/ranged/laser = 5,
			/mob/living/simple_mob/humanoid/merc/ranged/rifle = 5,
			/mob/living/simple_mob/humanoid/merc/ranged/smg = 5,
			/mob/living/simple_mob/humanoid/merc/ranged/sniper = 1,
			/mob/living/simple_mob/humanoid/merc/ranged/space = 10,
			/mob/living/simple_mob/humanoid/merc/ranged/technician = 5
			),
		list(
			/mob/living/simple_mob/humanoid/pirate = 3,
			/mob/living/simple_mob/humanoid/pirate/ranged = 1
			),
		list(/mob/living/simple_mob/mechanical/combat_drone),
		list(/mob/living/simple_mob/mechanical/corrupt_maint_drone),
		list(
			/mob/living/simple_mob/mechanical/hivebot = 100,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage = 20,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/backline = 10,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/basic = 20,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/dot = 5,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/ion = 20,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/laser = 10,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/rapid = 2,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege = 1,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege/emp = 5,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege/fragmentation = 1,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege/radiation = 1,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong = 3,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong/guard = 3,
			/mob/living/simple_mob/mechanical/hivebot/support = 8,
			/mob/living/simple_mob/mechanical/hivebot/support/commander = 5,
			/mob/living/simple_mob/mechanical/hivebot/support/commander/autofollow = 10,
			/mob/living/simple_mob/mechanical/hivebot/swarm = 20,
			/mob/living/simple_mob/mechanical/hivebot/tank = 20,
			/mob/living/simple_mob/mechanical/hivebot/tank/armored = 20,
			/mob/living/simple_mob/mechanical/hivebot/tank/armored/anti_bullet = 20,
			/mob/living/simple_mob/mechanical/hivebot/tank/armored/anti_laser = 20,
			/mob/living/simple_mob/mechanical/hivebot/tank/armored/anti_melee = 20,
			/mob/living/simple_mob/mechanical/hivebot/tank/meatshield = 20
			),
		list(/mob/living/simple_mob/mechanical/infectionbot),
		list(/mob/living/simple_mob/mechanical/mining_drone),
		list(/mob/living/simple_mob/mechanical/technomancer_golem),
		list(
			/mob/living/simple_mob/mechanical/viscerator,
			/mob/living/simple_mob/mechanical/viscerator/piercing
			),
		list(/mob/living/simple_mob/mechanical/wahlem),
		list(/mob/living/simple_mob/animal/passive/fox/syndicate),
		list(/mob/living/simple_mob/animal/passive/fox),
		list(/mob/living/simple_mob/vore/wolf/direwolf),
		list(/mob/living/simple_mob/vore/jelly),
		list(
			/mob/living/simple_mob/vore/otie/feral,
			/mob/living/simple_mob/vore/otie/feral/chubby,
			/mob/living/simple_mob/vore/otie/red,
			/mob/living/simple_mob/vore/otie/red/chubby
			),
		list(
			/mob/living/simple_mob/shadekin/blue = 100,
			/mob/living/simple_mob/shadekin/green = 50,
			/mob/living/simple_mob/shadekin/orange = 20,
			/mob/living/simple_mob/shadekin/purple = 60,
			/mob/living/simple_mob/shadekin/red = 40,
			/mob/living/simple_mob/shadekin/yellow = 1
			),
		list(
			/mob/living/simple_mob/vore/aggressive/corrupthound,
			/mob/living/simple_mob/vore/aggressive/corrupthound/prettyboi
			),
		list(/mob/living/simple_mob/vore/aggressive/deathclaw),
		list(/mob/living/simple_mob/vore/aggressive/dino),
		list(/mob/living/simple_mob/vore/aggressive/dragon),
		list(/mob/living/simple_mob/vore/aggressive/dragon/virgo3b),
		list(/mob/living/simple_mob/vore/aggressive/frog),
		list(/mob/living/simple_mob/vore/aggressive/giant_snake),
		list(/mob/living/simple_mob/vore/aggressive/mimic),
		list(/mob/living/simple_mob/vore/aggressive/panther),
		list(/mob/living/simple_mob/vore/aggressive/rat),
		list(/mob/living/simple_mob/vore/bee),
		list(/mob/living/simple_mob/vore/catgirl),
		list(/mob/living/simple_mob/vore/cookiegirl),
		list(/mob/living/simple_mob/vore/fennec),
		list(/mob/living/simple_mob/vore/fennix),
		list(/mob/living/simple_mob/vore/hippo),
		list(/mob/living/simple_mob/vore/horse),
		list(/mob/living/simple_mob/vore/oregrub),
		list(/mob/living/simple_mob/vore/rabbit),
		list(
			/mob/living/simple_mob/vore/redpanda = 50,
			/mob/living/simple_mob/vore/redpanda/fae = 1
			),
		list(
			/mob/living/simple_mob/vore/sect_drone = 10,
			/mob/living/simple_mob/vore/sect_queen = 1
			),
		list(/mob/living/simple_mob/vore/solargrub),
		list(/mob/living/simple_mob/vore/woof),
		list(/mob/living/simple_mob/vore/alienanimals/teppi),
		list(/mob/living/simple_mob/vore/alienanimals/space_ghost),
		list(/mob/living/simple_mob/vore/alienanimals/catslug),
		list(/mob/living/simple_mob/vore/alienanimals/space_jellyfish),
		list(/mob/living/simple_mob/vore/alienanimals/startreader),
		list(/mob/living/simple_mob/vore/bigdragon),
		list(
			/mob/living/simple_mob/vore/leopardmander = 50,
			/mob/living/simple_mob/vore/leopardmander/blue = 10,
			/mob/living/simple_mob/vore/leopardmander/exotic = 1
			),
		list(/mob/living/simple_mob/vore/sheep),
		list(/mob/living/simple_mob/vore/weretiger),
		list(/mob/living/simple_mob/vore/alienanimals/skeleton),
		list(/mob/living/simple_mob/vore/alienanimals/dustjumper),
		list(/mob/living/simple_mob/vore/cryptdrake),
		list(/mob/living/simple_mob/vore/stalker),
		list(/mob/living/simple_mob/vore/horse/kelpie),
		list(/mob/living/simple_mob/vore/scrubble),
		list(/mob/living/simple_mob/vore/sonadile),
		list(/mob/living/simple_mob/vore/devil)
		)

/obj/item/capture_crystal/random/Initialize(mapload)
	var/subchoice = pickweight(possible_mob_types)		//Some of the lists have nested lists, so let's pick one of them
	var/choice = pickweight(subchoice)					//And then we'll pick something from whatever's left
	spawn_mob_type = choice								//Now when someone uses this, we'll spawn whatever we picked!
	return ..()

/mob/living
	var/capture_crystal = TRUE		//If TRUE, the mob is capturable. Otherwise it isn't.
	var/capture_caught = FALSE		//If TRUE, the mob has already been caught, and so cannot be caught again.

/obj/item/capture_crystal/loadout
	active = TRUE
	loadout = TRUE

/obj/item/capture_crystal/loadout/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!bound_mob && M != user)
		to_chat(user, span_notice("\The [src] emits an unpleasant tone..."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		return ITEM_INTERACT_FAILURE
	. = ..()

/obj/item/capture_crystal/loadout/capture_chance()
	return 0

/obj/item/capture_crystal/cheap
	name = "cheap capture crystal"
	desc = "A silent, unassuming crystal in what appears to be some kind of steel housing. This one seems to be cheaply made and can only handle a willing mind."
	icon = 'icons/obj/capture_crystal_vr.dmi'

//The basic capture command does most of the registration work.
/obj/item/capture_crystal/cheap/capture(mob/living/M, mob/living/U)
	if(!M.capture_crystal || M.capture_caught)
		to_chat(U, span_warning("This creature is not suitable for capture with this crystal."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		return
	knowyoursignals(M, U)
	if(isanimal(M) || !M.client)
		to_chat(U, span_warning("This creature is not suitable for capture."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		return
	rel_set(src, nameof(owner), U)
	if(!bound_mob)
		rel_set(src, nameof(bound_mob), M)
		bound_mob.capture_caught = TRUE
		persist_storable = FALSE
	desc = "A silent, unassuming crystal in what appears to be some kind of steel housing. This one seems to be cheaply made and can only handle a willing mind."

/obj/item/capture_crystal/cheap/activate(mob/living/user, target)
	if(!cooldown_check())		//Are we ready to do things yet?
		to_chat(user, span_notice("\The [src] clicks unsatisfyingly... It is not ready yet."))
		play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		return
	if(spawn_mob_type && !bound_mob)			//We don't already have a mob, but we know what kind of mob we want
		rel_set(src, nameof(bound_mob), new spawn_mob_type(src)) //Well let's spawn it then!
		bound_mob.faction = user.faction
		spawn_mob_type = null
		capture(bound_mob, user)
	if(bound_mob)								//We have a mob! Let's finish setting up.
		act_message(user, src, MSG_SELF("%T% grows warm in your hand, something inside is awake."), MSG_OTHERS("%T% clicks, and then emits a small chime."))
		active = TRUE
		if(!owner)								//Do we have an owner? It's pretty unlikely that this would ever happen! But it happens, let's claim the crystal.
			rel_set(src, nameof(owner), user)
			if(isanimal(bound_mob))
				var/mob/living/simple_mob/S = bound_mob
				S.revivedby = user.name
		determine_action(user, target)
		return
	else if(isliving(target))						//So we don't have a mob, let's try to claim one! Is the target a mob?
		var/mob/living/M = target
		start_activate_cooldown()
		if(M.capture_caught)					//Can't capture things that were already caught.
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			to_chat(user, span_notice("\The [src] clicks unsatisfyingly... \The [M] is already under someone else's control."))
			return
		else if(M.stat == DEAD)						//Is it dead? We can't influence dead things.
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			to_chat(user, span_notice("\The [src] clicks unsatisfyingly... \The [M] is not in a state to be captured."))
			return
		else if(M.client)							//Is it player controlled?
			capture_player(M, user)				//We have to do things a little differently if so.
			return
		else if(!isanimal(M))						//So it's not player controlled, but it's also not a simplemob?
			to_chat(user, span_warning("This creature is not suitable for capture."))
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			return
		var/mob/living/simple_mob/S = M
		if(!S.ai_brain)						//We don't really want to capture simplemobs that don't have an AI
			to_chat(user, span_warning("This creature is not suitable for capture."))
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
		else									//Shoot, it didn't work and now it's mad!!!
			S.ai_brain.go_wake()
			S.ai_brain.give_target(user, TRUE)
			user.visible_message("\The [src] bonks into \the [S], angering it!")
			play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
			to_chat(user, span_notice("\The [src] clicks unsatisfyingly."))
		update_icon()
		return
	//The target is not a mob, so let's not do anything.
	play_sfx(src, SFX_EFFECTS_CAPTURE_CRYSTAL_NEGATIVE)
	to_chat(user, span_notice("\The [src] clicks unsatisfyingly."))

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/capture_crystal, \
	INTERACT_VERB("Toggle Follow", PROC_REF(follow_owner_effect), REQ_IN_INVENTORY), \
	INTERACT_VERB("Destroy Crystal", PROC_REF(destroy_crystal_effect), REQ_IN_INVENTORY), \
	INTERACT_VERB("Release Ownership", PROC_REF(release_ownership_effect), REQ_IN_INVENTORY), \
	INTERACT_VERB("Enhance (Toggle Ghost Join)", PROC_REF(invite_ghost_effect), REQ_IN_INVENTORY), \
)

