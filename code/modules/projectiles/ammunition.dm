/obj/item/ammo_casing
	name = "bullet casing"
	desc = "A bullet casing."
	icon = 'icons/obj/ammo.dmi'
	icon_state = "s-casing"
	randpixel = 10
	slot_flags = SLOT_BELT | SLOT_EARS
	throwforce = 1
	w_class = ITEMSIZE_TINY
	preserve_item = 1
	drop_sound = SFX_ITEMS_DROP_RING
	pickup_sound = SFX_ITEMS_PICKUP_RING

	var/leaves_residue = 1
	var/caliber = ""					//Which kind of guns it can be loaded into
	var/projectile_type					//The bullet type to create when New() is called
	var/obj/item/projectile/BB = null	//The loaded bullet - make it so that the projectiles are created only when needed?
	var/caseless = null					//Caseless ammo deletes its self once the projectile is fired.

CAPABILITIES(/obj/item/ammo_casing)
	owns_one(nameof(BB), /obj/item/projectile, starts = nameof(projectile_type))
	rolls(ROLL_PIXEL, PIXEL_JITTER(nameof(randpixel)))

//removes the projectile from the ammo casing
/obj/item/ammo_casing/proc/expend()
	. = BB
	own_take(src, nameof(BB))
	set_dir(pick(GLOB.cardinal)) //spin spent casings
	update_icon()

/// Mass reloading: one matching shell from `floor` into the box every half second.
/obj/item/ammo_casing/proc/collect_shell(mob/user, obj/item/ammo_magazine/box, turf/floor)
	if(next_shell(box, floor))
		to_chat(user, span_notice("You start collecting shells.")) // Say it here so it doesn't get said if we don't find anything useful.
		om_task_start(/datum/om/task/timed/collect_shells, user, box, duration = 0.5 SECONDS, receiver = src, floor = floor)
		return
	collect_done(user, box, 0)

/// The next shell on `floor` that fits `box`, or null (the box is full, or there is none).
/obj/item/ammo_casing/proc/next_shell(obj/item/ammo_magazine/box, turf/floor)
	if(length(box.stored_ammo) >= box.max_ammo)
		return null
	for(var/obj/item/ammo_casing/bullet in floor)
		if(box.caliber == bullet.caliber && bullet.BB)
			return bullet
	return null

/// Collecting shells from the floor into the box (the target), one every half second.
/datum/om/task/timed/collect_shells
	steps = list(/obj/item/ammo_casing/proc/shell_collected = 0.5 SECONDS)
	complete_proc = /obj/item/ammo_casing/proc/collect_ended
	cancel_proc = /obj/item/ammo_casing/proc/collect_ended
	var/turf/floor
	var/collected = 0

/obj/item/ammo_casing/proc/shell_collected(datum/om/task/timed/collect_shells/task)
	var/obj/item/ammo_magazine/box = task.target
	var/obj/item/ammo_casing/bullet = next_shell(box, task.floor)
	if(!bullet)
		return STEP_DONE
	move_into(box, nameof(box.stored_ammo), bullet)
	box.update_icon()
	task.collected++
	return next_shell(box, task.floor) ? STEP_REPEAT(0.5 SECONDS) : STEP_DONE

/obj/item/ammo_casing/proc/collect_ended(datum/om/task/timed/collect_shells/task)
	collect_done(task.actor, task.target, task.collected)

/obj/item/ammo_casing/proc/collect_done(mob/user, obj/item/ammo_magazine/box, boolets)
	if(!box)
		return
	if(boolets > 0)
		to_chat(user, span_notice("You collect [boolets] shell\s. [box] now contains [length(box.stored_ammo)] shell\s."))
	else
		to_chat(user, span_warning("You fail to collect anything!"))
	box.reloading = FALSE

DECLARE_INTERACTIONS(/obj/item/ammo_casing, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/ammo_casing/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/ammo_magazine) && isturf(loc)) // Mass magazine reloading.
		var/obj/item/ammo_magazine/box = I
		if (!box.can_remove_ammo || box.reloading)
			return FALSE
		box.reloading = TRUE
		collect_shell(user, box, loc)
	else if(istype(I, /obj/item/ammo_casing)) // Gather two loose rounds into a handful.
		var/obj/item/ammo_casing/other = I
		if(other == src)
			return INTERACTION_HANDLED_PASS
		if(other.caliber != caliber)
			to_chat(user, span_warning("Those rounds aren't the same caliber."))
			return INTERACTION_HANDLED_PASS
		var/obj/item/ammo_magazine/handful/H = make_ammo_handful(src, other, user)
		if(H)
			user.put_in_hands(H)
			act_message(user, null, MSG_SELF(span_notice("You gather the rounds into a handful.")), MSG_OTHERS("%U% gathers some rounds into a handful."))
			play_sfx(H, SFX_WEAPONS_EMPTY, 0.5)
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/item/ammo_casing/screwdriver_act(mob/user, obj/item/tool)
	return weapon_label_inscription_stage(user, tool)

/obj/item/ammo_casing/proc/weapon_label_inscription_stage(mob/user, obj/item/tool, weapon_answer, weapon_answer_ready = FALSE)
	if(!BB)
		to_chat(user, span_blue("There is no bullet in the casing to inscribe anything into."))
		return ITEM_INTERACT_BLOCKING
	if(!weapon_answer_ready)
		open_request(src, /datum/prompt/text/weapon_label_review, PROC_REF(weapon_label_inscription_answered), answerer = user, weapon_operator = user, weapon_held = tool, question = "Inscribe some text into \the [initial(BB.name)]", title = "Inscription", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE)
		return ITEM_INTERACT_BLOCKING
	var/_answer_k91 = weapon_answer
	if(isnull(_answer_k91))
		return ITEM_INTERACT_BLOCKING
	var/label_text = sanitizeSafe(_answer_k91, MAX_NAME_LEN)
	if(length(label_text) > 20)
		to_chat(user, span_red("The inscription can be at most 20 characters long."))
	else if(!label_text)
		to_chat(user, span_blue("You scratch the inscription off of [initial(BB)]."))
		BB.name = initial(BB.name)
	else
		to_chat(user, span_blue("You inscribe \"[label_text]\" into \the [initial(BB.name)]."))
		BB.name = "[initial(BB.name)] (\"[label_text]\")"
	return ITEM_INTERACT_SUCCESS

DECLARE_APPEARANCE_PROC(/obj/item/ammo_casing, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/ammo_casing/appearance_overlays()
	. = list()
	if(!BB)
		icon_state = "[initial(icon_state)]-spent"

/obj/item/ammo_casing/examine(mob/user)
	. = ..()
	if (!BB)
		. += "This one is spent."
	material_round_examine(forged_material(), .)

//An item that holds casings and can be used to put them inside guns
/obj/item/ammo_magazine
	name = "magazine"
	desc = "A magazine for some kind of gun."
	icon_state = ".357"
	icon = 'icons/obj/ammo.dmi'
	slot_flags = SLOT_BELT
	item_state = "syringe_kit"
	MATERIAL_BULK(MAT_STEEL, 500)
	throwforce = 5
	w_class = ITEMSIZE_SMALL
	throw_speed = 4
	throw_range = 10
	preserve_item = 1

	var/list/stored_ammo = list() // ALLOW(instance_list): d: magazines are filled with rounds on creation
	var/mag_type = SPEEDLOADER //ammo_magazines can only be used with compatible guns. This is not a bitflag, the load_method var on guns is.
	var/caliber = ".357"
	var/max_ammo = 7

	var/ammo_type = /obj/item/ammo_casing //ammo type that is initially loaded
	var/initial_ammo = null
	/// Pristine ammo_type rounds held as a count (C5), loaded before stored_ammo.
	/// make_rounds_real() creates them; ammo_count() includes them.
	var/latent_rounds = 0

	var/can_remove_ammo = TRUE	// Can this thing have bullets removed one-by-one? As of first implementation, only affects smart magazines
	var/reloading = FALSE		//  Is this magazine being reloaded, currently? - Currently only useful for automatic pickups, ignored by manual reloading.

	var/multiple_sprites = 0
	//because BYOND doesn't support numbers as keys in associative lists
	var/list/icon_keys		//keys
	var/list/ammo_states	//values

CAPABILITIES(/obj/item/ammo_magazine)
	owns_many(nameof(stored_ammo))
	param(nameof(forge_material), pos = 1)
	rolls(ROLL_PIXEL, PIXEL_JITTER(5))

/// The construction material a lathe forged the magazine from (its constructor param), or null.
/obj/item/ammo_magazine/var/forge_material

// ALLOW(init/INSTANCE_STATE): a magazine fills with its rounds (a latent count while it lies on a turf) and stamps them with the material it was forged from
/obj/item/ammo_magazine/Initialize(mapload)
	. = ..()
	if(multiple_sprites)
		initialize_magazine_icondata(src)

	if(isnull(initial_ammo))
		initial_ammo = max_ammo

	if(initial_ammo)
		// Lying on a turf or in a latent holder, the rounds are a count until
		// something handles the magazine (C5). Forged rounds are always real.
		if(!forge_material && (isturf(loc) || loc?.latent_contents) && dq_latent_eligible(ammo_type))
			latent_rounds = initial_ammo
		else
			for(var/i in 1 to initial_ammo)
				rel_add(src, nameof(stored_ammo), new ammo_type(src))

	// A lathe can forge a magazine from chosen construction materials,
	// passing its key as the second Initialize arg — stamp the rounds with it.
	if(forge_material)
		var/datum/material/forged = get_material_by_name(forge_material)
		if(forged)
			set_forged_material(forged)
	update_icon()

DECLARE_INTERACTIONS(/obj/item/ammo_magazine, \
	INTERACT_ITEM("Load", PROC_REF(magazine_interaction_item)), \
	INTERACT_USE("Empty", PROC_REF(magazine_interaction_self)), \
	INTERACT_HAND_UNGATED(null, PROC_REF(magazine_interaction_hand)), \
)

/// Old attackby (both of its definitions: magazine-to-magazine loading ran first). It never
/// called the base attackby: any item stops here, but afterattack still follows.
/obj/item/ammo_magazine/proc/magazine_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	. = INTERACTION_HANDLED_PASS
	if(!load_from_magazine(W, user))
		return
	make_rounds_real()
	if(istype(W, /obj/item/ammo_casing))
		var/obj/item/ammo_casing/C = W
		if(C.caliber != caliber)
			to_chat(user, span_warning("[C] does not fit into [src]."))
			return
		if(length(stored_ammo) >= max_ammo)
			to_chat(user, span_warning("[src] is full!"))
			return
		if(!move_into(src, nameof(src.stored_ammo), C, user))
			return
		update_icon()
	if(istype(W, /obj/item/ammo_magazine/clip))
		var/obj/item/ammo_magazine/clip/L = W
		if(L.caliber != caliber)
			to_chat(user, span_warning("The ammo in [L] does not fit into [src]."))
			return
		if(!length(L.stored_ammo))
			to_chat(user, span_warning("There's no more ammo [L]!"))
			return
		if(length(stored_ammo) >= max_ammo)
			to_chat(user, span_warning("[src] is full!"))
			return
		var/obj/item/ammo_casing/AC = L.stored_ammo[1] //select the next casing.
		AC.forceMove(src)
		own_transfer(L, nameof(L.stored_ammo), src, nameof(stored_ammo), AC) //move this casing from the clip's loaded list to ours
		moveElement(stored_ammo, length(stored_ammo), 1) //to the head of our magazine's list
		L.update_icon()
	play_sfx(src, SFX_WEAPONS_FLIPBLADE)
	update_icon()

/// Old attack_self: this dumps all the bullets right on the floor.
/obj/item/ammo_magazine/proc/magazine_interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	make_rounds_real()
	if(can_remove_ammo)
		if(!length(stored_ammo))
			to_chat(user, span_notice("[src] is already empty!"))
			return
		to_chat(user, span_notice("You empty [src]."))
		play_sfx(src, SFX_CASING_SOUND)
		after(src, 0.7 SECONDS, TYPE_PROC_REF(/atom, om_playsound), with = list("casing_sound", 50, 1))
		after(src, 1 SECOND, TYPE_PROC_REF(/atom, om_playsound), with = list("casing_sound", 50, 1))
		for(var/obj/item/ammo_casing/C in stored_ammo)
			C.forceMove(user.loc)
			C.set_dir(pick(GLOB.cardinal))
		own_take_all(src, nameof(stored_ammo))
		update_icon()
	else
		to_chat(user, span_notice("\The [src] is not designed to be unloaded."))
		return

/// Old attack_hand: this puts one bullet from the magazine into your hand. FALSE goes on to pickup.
/obj/item/ammo_magazine/proc/magazine_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	make_rounds_real()
	if(can_remove_ammo)	// For Smart Magazines
		if(user.get_inactive_hand() == src)
			if(length(stored_ammo))
				var/obj/item/ammo_casing/C = stored_ammo[length(stored_ammo)]
				own_take_member(src, nameof(stored_ammo), C)
				user.put_in_hands(C)
				act_message(user, src, MSG_SELF(span_notice("You remove \a [C] from %T%.")), MSG_OTHERS("%U% removes \a [C] from %T%."))
				update_icon()
				return TRUE
	return FALSE

/// Rounds loaded, real and latent.
/obj/item/ammo_magazine/proc/ammo_count()
	return length(stored_ammo) + latent_rounds

/// Creates the latent rounds (C5), ahead of the real ones as Initialize() would have.
/obj/item/ammo_magazine/proc/make_rounds_real()
	if(!latent_rounds)
		return
	var/list/rounds = list()
	for(var/i in 1 to latent_rounds)
		rounds += new ammo_type(src)
	latent_rounds = 0
	// The new rounds go to the head of the list, in order.
	var/head = 1
	for(var/obj/item/ammo_casing/new_round as anything in rounds)
		if(rel_add(src, nameof(stored_ammo), new_round))
			moveElement(stored_ammo, length(stored_ammo), head++)

/obj/item/ammo_magazine/pickup(mob/user)
	make_rounds_real()
	return ..()

/obj/item/ammo_magazine/equipped(mob/user, slot)
	make_rounds_real()
	return ..()

/// Anywhere but a turf or a latent holder, legacy gun code reads stored_ammo.
/obj/item/ammo_magazine/Moved(atom/old_loc, direction, forced = FALSE, movetime)
	. = ..()
	if(latent_rounds && loc && !isturf(loc) && !loc.latent_contents)
		make_rounds_real()

DECLARE_APPEARANCE_PROC(/obj/item/ammo_magazine, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/ammo_magazine/appearance_overlays()
	. = list()
	if(multiple_sprites)
		//find the lowest key greater than or equal to length(stored_ammo)
		var/new_state = null
		for(var/idx in 1 to length(icon_keys))
			var/threshold = LAZYACCESS(icon_keys, idx)
			if (threshold >= ammo_count())
				new_state = LAZYACCESS(ammo_states, idx)
				break
		icon_state = (new_state)? new_state : initial(icon_state)

/obj/item/ammo_magazine/examine(mob/user)
	. = ..()
	var/rounds = ammo_count()
	. += "There [(rounds == 1)? "is" : "are"] [rounds] round\s left!"
	material_round_examine(forged_material(), .)

//magazine icon state caching
GLOBAL_LIST_EMPTY(magazine_icondata_keys)
GLOBAL_LIST_EMPTY(magazine_icondata_states)

/proc/initialize_magazine_icondata(obj/item/ammo_magazine/M)
	var/typestr = M.type
	if(!(typestr in GLOB.magazine_icondata_keys) || !(typestr in GLOB.magazine_icondata_states))
		magazine_icondata_cache_add(M)

	M.icon_keys = GLOB.magazine_icondata_keys[typestr]
	M.ammo_states = GLOB.magazine_icondata_states[typestr]

/proc/magazine_icondata_cache_add(obj/item/ammo_magazine/M)
	var/list/icon_keys = list()
	var/list/ammo_states = list()
	var/list/states = icon_states_fast(M.icon)
	for(var/i = 0, i <= M.max_ammo, i++)
		var/ammo_state = "[M.icon_state]-[i]"
		if(ammo_state in states)
			icon_keys += i
			ammo_states += ammo_state

	GLOB.magazine_icondata_keys[M.type] = icon_keys
	GLOB.magazine_icondata_states[M.type] = ammo_states

/*
 * Ammo Boxes
 */

/obj/item/ammo_magazine/ammo_box
	name = "ammo box"
	desc = "A box that holds some kind of ammo."
	icon = 'icons/obj/ammo_boxes.dmi'
	icon_state = "pistol"
	slot_flags = null //You can't fit a box on your belt
	item_state = "paper"
	MATERIAL_NONE
	throwforce = 3
	throw_speed = 5
	throw_range = 12
	preserve_item = 1
	caliber = ".357"
	drop_sound = SFX_ITEMS_DROP_MATCHBOX
	pickup_sound = SFX_ITEMS_PICKUP_MATCHBOX

EXTEND_INTERACTIONS(/obj/item/ammo_magazine/ammo_box, INTERACT_ALT(null, PROC_REF(interaction_alt)))

/// Old click_alt.
/obj/item/ammo_magazine/ammo_box/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	make_rounds_real()
	if(can_remove_ammo)
		if(isliving(user) && Adjacent(user))
			if(length(stored_ammo))
				var/obj/item/ammo_casing/C = stored_ammo[length(stored_ammo)]
				own_take_member(src, nameof(stored_ammo), C)
				user.put_in_hands(C)
				act_message(user, src, MSG_SELF(span_notice("You remove \a [C] from %T%.")), MSG_OTHERS("%U% removes \a [C] from %T%."))
				update_icon()
				return TRUE
	return FALSE

/obj/item/ammo_magazine/ammo_box/examine(mob/user)
	. = ..()

	. += span_notice("Alt-click to extract contents.")


/obj/item/ammo_casing/proc/weapon_label_inscription_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = weapon_label_inscription_apply(A)
	SStgui.update_uis(src)

/obj/item/ammo_casing/proc/weapon_label_inscription_apply(datum/act/request/A)
	var/datum/prompt/text/weapon_label_review/ask = A.answer
	return weapon_label_inscription_stage(ask.weapon_operator, ask.weapon_held, ask.value, TRUE)

/datum/prompt/text/weapon_label_review
	timeout = 0
	var/mob/weapon_operator
	var/weapon_operator_expected = FALSE
	var/obj/item/weapon_held
	var/weapon_held_expected = FALSE
	var/datum/interaction/weapon_interaction
	var/weapon_interaction_expected = FALSE

CAPABILITIES(/datum/prompt/text/weapon_label_review)
	ref_one(nameof(weapon_operator), /mob)
	ref_one(nameof(weapon_held), /obj/item)
	ref_one(nameof(weapon_interaction), /datum/interaction)

/datum/prompt/text/weapon_label_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_weapon_operator = weapon_operator
	weapon_operator_expected = !isnull(captured_weapon_operator)
	rel_clear(src, nameof(weapon_operator))
	if(captured_weapon_operator && !QDELETED(captured_weapon_operator))
		rel_set(src, nameof(weapon_operator), captured_weapon_operator)
	var/obj/item/captured_weapon_held = weapon_held
	weapon_held_expected = !isnull(captured_weapon_held)
	rel_clear(src, nameof(weapon_held))
	if(captured_weapon_held && !QDELETED(captured_weapon_held))
		rel_set(src, nameof(weapon_held), captured_weapon_held)
	var/datum/interaction/captured_weapon_interaction = weapon_interaction
	weapon_interaction_expected = !isnull(captured_weapon_interaction)
	rel_clear(src, nameof(weapon_interaction))
	if(captured_weapon_interaction && !QDELETED(captured_weapon_interaction))
		rel_set(src, nameof(weapon_interaction), captured_weapon_interaction)

/datum/prompt/text/weapon_label_review/recheck_extra()
	if((weapon_operator_expected && QDELETED(weapon_operator)) || (weapon_held_expected && QDELETED(weapon_held)) || (weapon_interaction_expected && QDELETED(weapon_interaction)))
		return "gone"

/datum/prompt/choice/weapon_label_review
	timeout = 0
	var/mob/weapon_operator
	var/weapon_operator_expected = FALSE
	var/obj/item/weapon_held
	var/weapon_held_expected = FALSE
	var/datum/interaction/weapon_interaction
	var/weapon_interaction_expected = FALSE

CAPABILITIES(/datum/prompt/choice/weapon_label_review)
	ref_one(nameof(weapon_operator), /mob)
	ref_one(nameof(weapon_held), /obj/item)
	ref_one(nameof(weapon_interaction), /datum/interaction)

/datum/prompt/choice/weapon_label_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_weapon_operator = weapon_operator
	weapon_operator_expected = !isnull(captured_weapon_operator)
	rel_clear(src, nameof(weapon_operator))
	if(captured_weapon_operator && !QDELETED(captured_weapon_operator))
		rel_set(src, nameof(weapon_operator), captured_weapon_operator)
	var/obj/item/captured_weapon_held = weapon_held
	weapon_held_expected = !isnull(captured_weapon_held)
	rel_clear(src, nameof(weapon_held))
	if(captured_weapon_held && !QDELETED(captured_weapon_held))
		rel_set(src, nameof(weapon_held), captured_weapon_held)
	var/datum/interaction/captured_weapon_interaction = weapon_interaction
	weapon_interaction_expected = !isnull(captured_weapon_interaction)
	rel_clear(src, nameof(weapon_interaction))
	if(captured_weapon_interaction && !QDELETED(captured_weapon_interaction))
		rel_set(src, nameof(weapon_interaction), captured_weapon_interaction)

/datum/prompt/choice/weapon_label_review/recheck_extra()
	if((weapon_operator_expected && QDELETED(weapon_operator)) || (weapon_held_expected && QDELETED(weapon_held)) || (weapon_interaction_expected && QDELETED(weapon_interaction)))
		return "gone"
