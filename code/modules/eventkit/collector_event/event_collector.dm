
/obj/structure/event_collector //set anchored, solid, etc to taste.
	name = "event collector"
	desc = "you really should set this up properly :("

	icon = 'icons/obj/general_collector.dmi'

	var/blocker_channel = "collector" //used for list management - blockers that have the same key will add themselves as a disabler to every collector with the same key

	var/recipe_size = 3 //how many ingredients do we pick out from the ingredients list for a "recipe"?

	var/blocker_insertion_impedement_threshold = -1 //if we have more blockers than this, we can't place item in :(
	var/show_blocker_in_examine = TRUE


	var/no_dupes_in_recipe = FALSE //do we care about repeats? if so, set to true
	var/need_recipe_in_order = FALSE //start from the first one! or ignore it and do whatever, man...
	var/item_theft_mode = TRUE //if true, we store it in our contents for later use, otherwise, we just delete it.

	var/completion_time = 60  //how long to "complete" a recipe before starting the next one - this is in processing calls, 2 seconds if no time dialation

	var/step_insertion_time = 2 SECONDS //how long it takes to put an object into us!
	var/static/list/step_insertion_verbs = list("inserts") //X inserts Item into [Src], picks from the list! Tosses, inserts, throws, etc
	var/static/list/step_initiation_verbs = list("insert") //when we start it. X starts to insert Item into [src]. picks from list. put, insert, shove, etc

	var/automatic_recipe_restart = TRUE //do we start a new recipe as soon as the active one's done? if not, admin only!

	var/noisy_recipe_completion = TRUE //if true, alerts admins when a recipe is completed
	var/noisy_step_completion = TRUE //if true, tells admins when a step is completed

	var/step_in_examine = TRUE //if true, simply tells the user what type of item they need next. note that we use typeof here, so a gold screwdriver counts as a screwdriver, but it'll just ask for a screwdriver

	var/animate_on_recipe_complete = TRUE //jiggle on complete?
	var/animate_on_recipe_process = TRUE //jiggle with less intensity when working?

	var/sound_for_recipe_complete

	var/wait_between_items = 0 //How long must you wait before adding another item
	EXPIRY_DECLARE(next_item_added) //world time when the next item can be added

	var/type_to_spawn_on_complete

	var/static/recipe_process_sounds = SFX_EFFECTS_SMOKE_MIX
	var/recipe_process_sound_chance = 50 //prob(50) per active process tick

	//internal stuff, don't touch this with subtypes.
	var/calls_remaining
	var/list/disabling_sources //what things are disabling us?
	var/list/active_recipe //volatile, when given an item it removes it
	var/current_step = 0 //current step for icon states
TRACKED(/obj/structure/event_collector, current_step)

/// Are we waiting for the timer to get negatives? periodic_step() works the recipe while set (its every()).
/obj/structure/event_collector/var/awaiting_next_recipe = FALSE
TRACKED(/obj/structure/event_collector, awaiting_next_recipe)
CAPABILITIES(/obj/structure/event_collector)
	every(2 SECONDS, then(PROC_REF(event_collector_step)), when = nameof(awaiting_next_recipe))
	op("item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_item)))
	// Putting the item in (interaction_item() checks it and starts this): the user keeps the item and stays for step_insertion_time.
	op("insert", ai(), takes("stored_index"), wait(PROC_REF(insert_time)), on_interrupt(PROC_REF(insert_gave_up)), then(PROC_REF(insert_done)))

//list of items that can make up a recipe.
TYPE_TABLE_DECLARE(/obj/structure/event_collector, event_collector_ingredients, list( \
	/obj/item/trash, \
	/obj/item/toy/plushie/ipc, \
	/obj/item/toy/tennis \
))

REGISTRY_MEMBERSHIP(/obj/structure/event_collector, REGISTRY_EVENT_COLLECTORS)

/obj/structure/event_collector/proc/get_blockers()
	. = 0
	// Blockers join REGISTRY_EVENT_COLLECTOR_BLOCKERS; ours share our channel.
	for(var/obj/structure/event_collector_blocker/blocker as anything in REGISTRY_MEMBERS(REGISTRY_EVENT_COLLECTOR_BLOCKERS))
		if(blocker.blocker_channel == blocker_channel)
			. += blocker.block_amount

/obj/structure/event_collector/proc/jiggle_animation(intensity = 1)
	var/matrix/secondary_effect = matrix()
	var/matrix/effect = matrix()
	effect.Turn(-5*intensity)
	effect.Scale(1,1-intensity)
	secondary_effect.Turn(5*intensity)
	secondary_effect.Scale(1,1+intensity)
	animate(src, transform = effect, time = 2)
	animate(transform = secondary_effect, time = 2)
	animate(transform = null, time = 2)

/obj/structure/event_collector/proc/recipe_completed()
	if(animate_on_recipe_complete)
		jiggle_animation(0.2)

	if(automatic_recipe_restart)
		pick_new_recipe()

	if(noisy_recipe_completion)
		message_admins("\[EVENT\]: Event Collection object [src] has completed a recipe!")

	if(sound_for_recipe_complete)
		playsound(src,sound_for_recipe_complete,75,1)

	if(type_to_spawn_on_complete)
		new type_to_spawn_on_complete(get_turf(loc))

	set_current_step(0)



/obj/structure/event_collector/proc/recipe_failed() //called when reset by an admin assuming they want it to be
	return

/obj/structure/event_collector/proc/pick_new_recipe()
	active_recipe = list() //clear it out
	if(no_dupes_in_recipe)
		var/list/destructive_clone = TYPE_TABLE_COPY(src, event_collector_ingredients)
		for(var/i in 1 to recipe_size)
			var/temp = pick(destructive_clone)
			active_recipe += temp
			destructive_clone -= temp

	else
		for(var/i in 1 to recipe_size)
			active_recipe += pick(TYPE_TABLE_GET(src, event_collector_ingredients))

	if(noisy_step_completion)
		var/next_item = "Nothing! The sequence is done!"
		next_item = active_recipe[1]
		message_admins("\[EVENT\] Event Collection object [src] has started a recipe! If it's in sequence, the next one is [next_item] ")

/// Works on its recipe every 2 s while one is running (start_recipe_process()); otherwise it sleeps.
/obj/structure/event_collector/proc/event_collector_step(datum/act/timer/A)
	var/blockers = get_blockers()
	if(blockers < 10)
		if( recipe_process_sounds && prob(recipe_process_sound_chance) )
			playsound(src,recipe_process_sounds,25,TRUE)

		calls_remaining -= max(0, 10-blockers) //10's a multiplier in case we want to scale it based on how many blockers
		if(calls_remaining <= 0)
			set_awaiting_next_recipe(FALSE)
			recipe_completed()
		if(animate_on_recipe_process)
			jiggle_animation(0.1)

/obj/structure/event_collector/examine(mob/user)
	. = ..()
	if(!active_recipe) return

	var/blocker_count = get_blockers()

	if(step_in_examine == TRUE)
		if(active_recipe.len == 0)
			. += span_notice("It doesn't seem to need anything at the moment!")

		else
			if(need_recipe_in_order)
				if(active_recipe.len > 0)
					var/atom/firstitem = active_recipe[1]
					. += span_notice("The next object in the sequence is a... [initial(firstitem.name)]")
				else
					. += span_notice("it doesn't seem to need anything at the moment!")
			else
				var/message = "It seems to need a "
				for(var/i in 1 to active_recipe.len)
					var/atom/x = active_recipe[i]
					.+= span_notice(message + initial(x.name))
					message = pick("and a ", "a ", "with a ")

	if(show_blocker_in_examine)
		if(blocker_count > 10)
			. += span_danger("It's nonfunctional!")
		else
			if(blocker_count > 0)
				. += span_warning("It's impeded!")

			//following's for debug, comment out if ur happy with it
		//. += "There are uhhhh this many things blocking: [blocker_count]."

/// Requirement: TRUE, or why the collector won't take an item now.
/obj/structure/event_collector/proc/can_take_item(mob/user, atom/target, obj/item/held)
	if(blocker_insertion_impedement_threshold > 0 && (get_blockers() > blocker_insertion_impedement_threshold))
		return "it's fucked, fix it first"
	if(!COOLDOWN_FINISHED(src, next_item_added))
		return "it's not ready to take another item yet"
	return TRUE

/// Requirement: the collector takes an item now.
/obj/structure/event_collector/proc/can_take_item_holds(datum/act/op/A)
	var/answer = can_take_item(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Old attackby.
/obj/structure/event_collector/proc/interaction_item(datum/act/op/A)
	var/refusal = can_take_item(A.actor, src, A.held)
	if(refusal != TRUE)
		if(istext(refusal))
			to_chat(A.actor, span_warning(refusal))
		return OP_DECLINE
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(active_recipe.len > 0) //do we have something active at all
		var/stored_index = -1 //shortcut
		if(need_recipe_in_order) //can we put this in?
			if(!(istype(O,active_recipe[1]))) //if we need the recipe in order, check the first thing in the list
				to_chat(user,span_warning("That's not the next object in the recipe!"))
				return OP_PASS
			else
				stored_index = 1
		else
			var/found = FALSE
			for(var/ind in 1 to active_recipe.len) //isType != if(O.type in list) unfortunately
				if(istype(O, active_recipe[ind]))
					found = TRUE
					stored_index = ind
					break;
			if(!found)
				return OP_DECLINE

		//put it in
		act_message(user, src, others = "%U% begins to [pick(step_initiation_verbs)] %I% into %T%", item = O)
		//wait a second or two
		perform_op(user, src, "insert", O, ORIGIN_SYSTEM, with = list("stored_index" = stored_index))
	return OP_PASS

/obj/structure/event_collector/proc/insert_time(datum/act/op/A)
	return step_insertion_time

/obj/structure/event_collector/proc/insert_gave_up(datum/act/op/A)
	act_message(A.actor, null, others = "%U% gives up!") //shitty, change later

/obj/structure/event_collector/proc/insert_done(datum/act/op/A)
	var/obj/item/O = A.held
	var/mob/user = A.actor
	var/stored_index = A.arg("stored_index")
	if(stored_index > length(active_recipe))
		return
	act_message(user, src, others = "%U% [pick(step_insertion_verbs)] %I% into %T%!", item = O)
	if(ishuman(user)) //should always be?
		var/mob/living/carbon/human/h = user
		h.drop_item() //drop held item. this is also what plays the item sound via association
		if(noisy_step_completion)
			var/next_item = "Nothing! The sequence is done!"
			if(active_recipe.len > 1)
				next_item = active_recipe[2]
			message_admins("\[EVENT\] Event Collection object [src] has completed a step in its recipe with [O]! if it's in sequence, the next one is [next_item] ")
		active_recipe -= active_recipe[stored_index]
		if(item_theft_mode)
			O.forceMove(src) //note that this does NOT delete anything! ever! or release it manually! entirely so admins can manually collect or do stuff later via moving/ejecting.
		else
			consume(O, user)

		jiggle_animation(0.1)
		if(active_recipe.len == 0)
			start_recipe_process()
		set_current_step(current_step + 1)
		post_recipe_complete(user)
		EXPIRY_SET(src, next_item_added, wait_between_items, CLOCK_WORLD)

/obj/structure/event_collector/proc/start_recipe_process()
	calls_remaining = completion_time * 10
	set_awaiting_next_recipe(TRUE)
	message_admins("\[EVENT\] Event Collection object [src] has started processing its current recipe! ETA: [(calls_remaining/10) / 2] ish seconds.")

/obj/structure/event_collector/proc/empty_items() //manual call only atm
	for(var/atom/movable/to_move in contents)
		to_move.forceMove(get_turf(src))

/obj/structure/event_collector/proc/post_object_insert(mob/user)
	return

/obj/structure/event_collector/proc/post_recipe_complete()
	return
