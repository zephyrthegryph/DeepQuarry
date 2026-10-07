//This is used to check if the gripper is currently being used.
//If it is, we don't allow any other actions to be performed.
//Returns TRUE if we're in use explaining how.
/obj/item/gripper/proc/is_in_use(mob/user, visible = TRUE)
	if(gripper_in_use)
		if(visible)
			to_chat(user, span_danger("You are currently using the gripper on something!"))
		return TRUE

	if(in_radial_menu)
		if(visible)
			to_chat(user, span_danger("You are currently in the radial menu! Close it to use the gripper."))
		return TRUE
	return FALSE

/obj/item/gripper/proc/update_ref(obj/item/new_item)
	var/had_item = get_wrapped_item()
	if(new_item)
		rel_set(src, nameof(held_item), new_item)
	else if(had_item)
		rel_clear(src, nameof(held_item))
	var/holding_item = get_wrapped_item()
	// Feedback
	update_icon()

	if(had_item && !holding_item) // Dropped
		our_robot.playsound_local(get_turf(our_robot), 'sound/machines/click.ogg', 50)
		return

	if(holding_item && !had_item || (holding_item != had_item)) // Pickup or change item
		our_robot.playsound_local(get_turf(our_robot), 'sound/machines/click2.ogg', 50)

///Stops the gripper from being used multiple times when we're performing a do_after
/obj/item/gripper/proc/begin_using(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	gripper_in_use = TRUE

///Allows use of the gripper (and lets go of the item) after do_after is completed. Lets go if the wrapped item is no longer in our borg's contents (items get moved into the borgs contents when using the gripper)
/obj/item/gripper/proc/end_using(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	gripper_in_use = FALSE
	var/obj/item/wrapped = get_wrapped_item()
	if(!wrapped)
		return
	//Checks two things:
	//Is our wrapped object currently in our borg still?
	//AND Is it not a gripper pocket? If not, let go of it.
	if(item_left_gripper(wrapped))
		update_ref(null)

//This is the code that updates our pockets and decides if they should have icons or not.
//This should be called every time we use the gripper and our wrapped item is used up.
/obj/item/gripper/proc/generate_icons()
	if(LAZYLEN(pockets))


		photo_images = list()

		for(var/obj/item/storage/internal/gripper/pocket_to_check in pockets)
			if(!LAZYLEN(pocket_to_check.contents))
				photo_images[pocket_to_check.name] = image(icon = 'icons/effects/effects.dmi', icon_state = "nothing")
				continue
			var/obj/item/pocket_content = pocket_to_check.contents[1]
			var/image/pocket_image = image(icon = pocket_content.icon, icon_state = pocket_content.icon_state)
			if(pocket_content.color)
				pocket_image.color = pocket_content.color
			if(pocket_content.overlays)
				for(var/overlay in pocket_content.overlays)
					pocket_image.overlays += overlay
			photo_images["[pocket_to_check.name]" + "[pocket_content.name]"] = pocket_image

/// The pocket (when empty) or the pocket's first item that a radial choice built by
/// generate_icons() names; null when nothing matches any more.
/obj/item/gripper/proc/pocket_choice_target(choice)
	for(var/obj/item/storage/internal/gripper/pocket as anything in pockets)
		if(!LAZYLEN(pocket.contents))
			if(pocket.name == choice)
				return pocket
			continue
		var/obj/item/pocket_content = pocket.contents[1]
		if("[pocket.name]" + "[pocket_content.name]" == choice)
			return pocket_content
	return null

DECLARE_INTERACTIONS(/obj/item/gripper, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/gripper/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(special_handling)
		return TRUE
	if(is_in_use(user))
		return TRUE

	generate_icons()

	var/list/options = list()

	for(var/Iname in photo_images)
		options[Iname] = photo_images[Iname]

	in_radial_menu = TRUE
	// optional: a cancel still answers (with no choice) and falls through to the wrapped item.
	// Not shown at all (no client, or the same menu toggled shut): the gripper is free again.
	var/datum/request/pocket_question = open_request(src, /datum/prompt/choice, PROC_REF(pocket_chosen), answerer = user, radial = TRUE, choices = options, anchor = src, radius = 40, require_near = TRUE, autopick_single_option = FALSE, timeout = 0)
	if(!pocket_question || !user.client)
		in_radial_menu = FALSE
	return TRUE

/// Pocket radial answer: select the pocket, or use the held item when the ring is closed. A ring that was never shown (the same menu toggled
/// shut) or an answer dropped out of reach only frees the gripper; a dropped answer is the request's last_error.
/obj/item/gripper/proc/pocket_chosen(datum/act/request/A)
	in_radial_menu = FALSE
	var/mob/user = A.request.answerer
	if(QDELETED(user))
		return
	if(!A.answer && A.request.last_error)
		return
	var/choice = A.answer ? A.answer.value : null
	var/obj/item/wrapped = get_wrapped_item()
	if(choice)
		var/obj/item/storage/internal/gripper/selected_pocket = pocket_choice_target(choice)
		if(!selected_pocket)
			return TRUE
		if(!isgripperpocket(selected_pocket)) //The pocket we're selecting is NOT a gripper storage
			if(!isgripperpocket(selected_pocket.loc)) //We kept the radial menu opened, used the item, then selected it again.
				clear_and_select_pocket() //Pick the next open pocket.
				return TRUE

			update_ref(selected_pocket)
			return TRUE

		rel_set(src, nameof(current_pocket), selected_pocket)
		update_ref(null)
		return TRUE

	if(wrapped)
		return wrapped.attack_self(user)
	return TRUE

/// Old attackby.
/obj/item/gripper/proc/interaction_item(datum/act/op/A, stance)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(is_in_use(user))
		return OP_PASS

	var/obj/item/wrapped = get_wrapped_item()
	if(wrapped)
		wrapped.forceMove(loc) //Place it in to the robot.
		var/resolved = wrapped.attackby(O, user)
		wrapped = get_wrapped_item() //We check to see if the object exists after we do attackby.

		//The object has been deleted. Select a new pocket and stop here.
		if(!wrapped)
			clear_and_select_pocket()
			return OP_PASS

		//Object is not in our contents AND is not in the gripper storage still. AKA, it was moved into something or somewhere. Either way, it's not ours anymore.
		if(item_left_gripper(wrapped))
			clear_and_select_pocket()
			return OP_OK

		//We were not given a resolved, the object still exists, AND we hit something. Attack that thing with our wrapped item.
		if(!resolved && wrapped && O)
			O.afterattack(wrapped, user, 1, null, stance)
			wrapped = get_wrapped_item()
			//The object still exists, but is not in our contents OR back in the gripper storage.
			if(item_left_gripper(wrapped))
				clear_and_select_pocket()
			return OP_OK

		//Nothing happened to it. Just put it back into our pocket.
		wrapped.forceMove(current_pocket)
		return OP_OK

	return OP_DECLINE

/obj/item/gripper/afterattack(atom/target, mob/living/user, proximity, params, stance = I_HURT)
	if(!proximity)
		return // This will prevent them using guns at range but adminbuse can add them directly to modules, so eh.

	if(is_in_use(user))
		return

	var/obj/item/wrapped = get_wrapped_item()
	if(wrapped && item_left_gripper(wrapped)) // This is used for items that are moved out during other attack chains
		clear_and_select_item()
		return

	if(use_item(target, user, wrapped, params, stance)) //Already have an item.
		return
	update_ref(wrapped)

	if(pick_up_item(target, user))
		return

	if(item_left_gripper(wrapped))
		clear_and_select_item()

/obj/item/gripper/proc/use_item(atom/target, mob/user, obj/item/wrapped, params, stance = I_HURT)
	if(!wrapped)
		return FALSE

	var/obj/item/storage/internal/gripper/previous_pocket
	if(isgripperpocket(wrapped.loc))
		previous_pocket = wrapped.loc
	else
		previous_pocket = current_pocket

	var/original_amount = 0
	if(istype(wrapped, /obj/item/reagent_containers))
		var/obj/item/reagent_containers/wrapped_container = wrapped
		original_amount = wrapped_container.reagents?.total_volume

	wrapped.forceMove(user)

	var/resolved = target.attackby(wrapped, user)
	if(!resolved && wrapped && target)
		wrapped.afterattack(target, user, TRUE, params, stance)

	if(item_left_gripper(wrapped))
		clear_and_select_pocket()
		return TRUE

	if(istype(wrapped, /obj/item/reagent_containers))
		var/obj/item/reagent_containers/wrapped_container = wrapped
		if(wrapped_container.reagents?.total_volume != original_amount || (istype(target, /obj/item/reagent_containers)))
			wrapped.forceMove(previous_pocket)
			update_ref(wrapped)
			return TRUE

	wrapped.forceMove(previous_pocket)
	update_ref(wrapped)
	return FALSE

/obj/item/gripper/proc/pick_up_item(atom/target, mob/user)
	if(!isitem(target))
		return FALSE

	var/obj/item/I = target

	if(I.anchored)
		to_chat(user, span_notice("You are unable to lift \the [I]."))
		return FALSE

	var/obj/item/storage/internal/gripper/selected_pocket = find_empty_pocket()
	if(!selected_pocket)
		to_chat(user, "Your gripper is full!")
		return FALSE

	if(dq_constraint_refusal(src, CONSTRAINT_HOLD, I, user))
		to_chat(user, span_danger("Your gripper cannot hold \the [I]."))
		return FALSE

	if(istype(target.loc, /obj/item/storage)) //Updates the HUD and all that.
		var/obj/item/storage/S = I.loc
		if(!S.remove_from_storage(I, selected_pocket))
			to_chat(user, "Something prevents you from taking \the [I] out of \the [S].")
			return
	else
		I.forceMove(selected_pocket)

	to_chat(user, "You collect \the [I].")
	rel_set(src, nameof(current_pocket), selected_pocket)
	update_ref(I)
	return TRUE

/// Returns the first empty gripper pocket, or null
/obj/item/gripper/proc/find_empty_pocket()
	for(var/obj/item/storage/internal/gripper/P in pockets)
		if(!LAZYLEN(P.contents))
			return P
	return null

/// Returns TRUE if item is no longer in the gripper
/obj/item/gripper/proc/item_left_gripper(obj/item/I)
	if(QDELETED(I))
		return TRUE

	if(isgripperpocket(I.loc))
		return FALSE

	if(I.loc == loc)
		return FALSE

	return TRUE


/// Sets current_pocket to a valid pocket (never an item)
/obj/item/gripper/proc/select_pocket(obj/item/storage/internal/gripper/P)
	if(!P)
		P = pick(pockets)

	rel_set(src, nameof(current_pocket), P)

/// Clears the currently wrapped item and selects the pocket
/obj/item/gripper/proc/clear_and_select_pocket()
	update_ref(null)
	select_empty_pocket()

/// Clears the currently wrapped item and selects next item
/obj/item/gripper/proc/clear_and_select_item()
	update_ref(null)
	select_next_item()

/// Selects the first empty pocket, or a random one
/obj/item/gripper/proc/select_empty_pocket()
	var/obj/item/storage/internal/gripper/P = find_empty_pocket()
	select_pocket(P)

/obj/item/gripper/proc/select_next_item()
	for(var/obj/item/storage/internal/gripper/P in reverseList(pockets))
		if(!LAZYLEN(P.contents))
			continue
		var/obj/item/next_item = P.contents[1]
		update_ref(next_item)
		return

/obj/item/gripper/proc/drop_item(mob/user)
	var/obj/item/wrapped = get_wrapped_item()
	if(!wrapped)
		to_chat(user, span_warning("You have nothing to drop!"))
		return

	if(is_in_use(user))
		return

	if((item_left_gripper(wrapped)))
		clear_and_select_pocket()
		generate_icons()
		return

	to_chat(user, span_notice("You drop \the [wrapped]."))
	wrapped.forceMove(get_turf(user))
	clear_and_select_pocket()
	generate_icons()

//FORCES the item onto the ground and resets.
/obj/item/gripper/proc/drop_item_nm(atom/target)
	var/obj/item/wrapped = get_wrapped_item()
	if(!wrapped)
		return

	if((item_left_gripper(wrapped)))
		clear_and_select_pocket()
		generate_icons()
		return

	wrapped.forceMove(target ? target : get_turf(src))
	clear_and_select_pocket()
	generate_icons()

/obj/item/gripper/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(is_in_use(user))
		return ITEM_INTERACT_FAILURE

	var/obj/item/wrapped = get_wrapped_item()
	//The force of the wrapped obj gets set to zero during the attack() and afterattack().
	if(!wrapped)
		return ITEM_INTERACT_FAILURE

	//If our wrapper was deleted OR it's no longer in our internal gripper storage
	if(item_left_gripper(wrapped))
		update_ref(null)
		return ITEM_INTERACT_FAILURE

	//First, we call the item's /attack on the MOB TARGET we are clicking on.
	var/attack_result = wrapped.attack(M, user, target_zone, attack_modifier)
	if(!(attack_result == ITEM_INTERACT_SUCCESS || attack_result == ITEM_INTERACT_BLOCKING))
		//If we don't get a return value of success/failure, that means we didn't hit them with it/do a special interaction with it.
		if(item_left_gripper(wrapped))
			update_ref(null)
			return ITEM_INTERACT_SUCCESS
		//Attackby is procced when an object (non living entity) is clicked on by the user.
		M.attackby(wrapped, user, target_zone, attack_modifier)

	//If our wrapper was deleted OR it's no longer in our internal gripper storage
	if(item_left_gripper(wrapped))
		update_ref(null)

	return ITEM_INTERACT_SUCCESS

DECLARE_APPEARANCE_PROC(/obj/item/gripper, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/gripper/appearance_overlays()
	. = list()
	var/obj/item/wrapped = get_wrapped_item()
	if(!wrapped)
		return .

	// Draw the held item as a mini-image in the gripper itself
	var/mutable_appearance/item_display = new(wrapped)
	item_display.SetTransform(0.75, offset_y = -8)
	item_display.pixel_x = 0
	item_display.pixel_y = 0
	item_display.plane = plane
	item_display.layer = layer + 0.01
	. += item_display

//HELPER PROCS
///Use this to get what the current pocket is. Returns NULL if no
/obj/item/gripper/proc/get_wrapped_item() //done as a proc so snowflake code can be found later down the line and consolidated.
	return held_item

/// Consolidates material stacks by searching our pockets to see if we currently have any stacks. Done in /obj/item/stack/attackby
/obj/item/gripper/proc/consolidate_stacks(obj/item/stack/stack_to_consolidate)
	if(!stack_to_consolidate || !istype(stack_to_consolidate, /obj/item/stack))
		return

	var/obj/item/current_item = get_wrapped_item()
	if(current_item?.type == stack_to_consolidate.type)
		return

	for(var/obj/item/storage/internal/gripper/pocket in pockets)
		if(!LAZYLEN(pocket.contents))
			continue
		for(var/obj/item/stack/stack in contents_of(pocket))
			if(istype(stack_to_consolidate, stack.type))
				stack_to_consolidate.transfer_to(stack)
				return

// ---- the gripper as a provider (code/engine/parts/provider.dm) ----

/// The cyborg's selected gripper carries its held item and provides the hands that handle it.
/mob/living/silicon/robot/held_carrier()
	var/obj/item/gripper/G = module_active
	return istype(G) ? G : null

/// With a gripper selected, the cyborg's ops see what the gripper carries (nothing, when it is empty) as the held item.
/mob/living/silicon/robot/held_for_ops()
	var/obj/item/gripper/G = module_active
	if(istype(G))
		return G.get_wrapped_item()
	return ..()

/// Can the gripper take `thing` into a pocket now: not busy, a free pocket, and its CONSTRAINT_HOLD allows it.
/obj/item/gripper/can_carry(obj/item/thing, mob/actor)
	if(is_in_use(actor, FALSE) || !find_empty_pocket())
		return FALSE
	return !dq_constraint_refusal(src, CONSTRAINT_HOLD, thing, actor)

/// Takes `thing` into a free pocket and holds it out.
/obj/item/gripper/carry(obj/item/thing, mob/actor)
	var/obj/item/storage/internal/gripper/P = find_empty_pocket()
	if(!P)
		return FALSE
	thing.add_fingerprint(actor)
	thing.forceMove(P)
	thing.update_icon()
	rel_set(src, nameof(current_pocket), P)
	update_ref(thing)
	return TRUE

/// What the gripper held out left its pockets for good (an op put it into a machine): it lets go, and the next pocket is selected.
/obj/item/storage/internal/gripper/Exited(atom/movable/AM, atom/new_loc)
	. = ..()
	var/obj/item/gripper/G = loc
	if(istype(G) && G.get_wrapped_item() == AM && G.item_left_gripper(AM))
		G.clear_and_select_pocket()
