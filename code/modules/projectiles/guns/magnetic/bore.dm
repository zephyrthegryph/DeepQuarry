/obj/item/gun/magnetic/matfed
	power_cost = 750
	load_type = list(/obj/item/stack/material, /obj/item/ore)
	var/mat_storage = 0			// How much material is stored inside? Input in multiples of 2000 as per auto/protolathe.
	var/max_mat_storage = 8000	// How much material can be stored inside?
	var/mat_cost = 500			// How much material is used per-shot?
	var/ammo_material
	var/obj/item/stock_parts/manipulator/manipulator    // Installed manipulator. Mostly for Phoron Bore, higher rating == less mats consumed upon firing. Set to a path to spawn with one of that type.
	var/rating_modifier = 0 // rating of installed capacitor + manipulator
	var/loading = FALSE

TRACKED(/obj/item/gun/magnetic/matfed, mat_storage)

CAPABILITIES(/obj/item/gun/magnetic/matfed)
	owns_one(nameof(manipulator), /obj/item/stock_parts/manipulator, starts = nameof(manipulator))
	op("matfed_interaction_hand", hand(), then(PROC_REF(matfed_interaction_hand)))

/obj/item/gun/magnetic/matfed/proc/update_rating_mod()
	if(capacitor && manipulator)
		rating_modifier = capacitor.get_rating() + manipulator.get_rating()
	else
		rating_modifier = FALSE

/obj/item/gun/magnetic/matfed/Initialize(mapload)
	. = ..()
	if(manipulator)
		mat_cost = initial(mat_cost) / (2*manipulator.rating)
	update_rating_mod()


/obj/item/gun/magnetic/matfed/examine(mob/user)
	. = ..()
	if(manipulator)
		. += span_notice("The installed [manipulator.name] consumes [mat_cost] units of [ammo_material] per shot.")
	else
		. += span_notice("The \"manipulator missing\" indicator is lit. [src] consumes [mat_cost] units of [ammo_material] per shot.")

/// The parts and charge indicators are the magnetic gun's; a matfed one is loaded by its stored material.
/obj/item/gun/magnetic/matfed/draw(datum/look/look)
	..()
	look.overlay("[initial(icon_state)]_loaded", when = mat_storage)

/// Old attack_hand.
/obj/item/gun/magnetic/matfed/proc/matfed_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src)
		var/obj/item/removing

		if(cell && removable_components)
			removing = cell
			rel_take(src, nameof(cell))

		if(removing)
			user.put_in_hands(removing)
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " removes %I% from %T%."), item = removing)
			play_sfx(src, SFX_MACHINES_CLICK, 0.2)
			return TRUE
	return OP_DECLINE

/obj/item/gun/magnetic/matfed/check_ammo()
	if(mat_storage - mat_cost >= 0)
		return TRUE
	return FALSE

/obj/item/gun/magnetic/matfed/use_ammo()
	set_mat_storage(mat_storage - mat_cost)

/obj/item/gun/magnetic/matfed/show_ammo()
	if(mat_storage)
		return span_notice("It has [mat_storage] out of [max_mat_storage] units of [ammo_material] loaded.")
	else
		return span_warning("It\'s out of [ammo_material]!")

/obj/item/gun/magnetic/matfed/crowbar_act(mob/user, obj/item/tool)
	update_rating_mod()
	if(!removable_components)
		return NONE
	if(!manipulator)
		to_chat(user, span_warning("\The [src] has no manipulator installed."))
		return ITEM_INTERACT_SUCCESS
	user.put_in_hands(manipulator)
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " levers \the [manipulator] from %T%."))
	playsound(src, tool.usesound, 50, 1)
	mat_cost = initial(mat_cost)
	rel_take(src, nameof(manipulator))
	update_rating_mod()
	return ITEM_INTERACT_SUCCESS

/// Loading sheets from a stack, one every 1.5 seconds, until full or the stack runs out.
/datum/task/timed/load_sheets
	steps = list(/obj/item/gun/magnetic/matfed/proc/sheet_loaded = 1.5 SECONDS)
	complete_proc = /obj/item/gun/magnetic/matfed/proc/sheets_done
	cancel_proc = /obj/item/gun/magnetic/matfed/proc/sheets_done
	var/obj/item/stack/material/sheets
	var/loaded_any = FALSE

/obj/item/gun/magnetic/matfed/proc/can_load_sheet(obj/item/stack/material/M)
	return mat_storage + SHEET_MATERIAL_AMOUNT <= max_mat_storage && M?.get_amount()

/obj/item/gun/magnetic/matfed/proc/sheet_loaded(datum/task/timed/load_sheets/task)
	if(!can_load_sheet(task.sheets))
		return STEP_DONE
	set_mat_storage(mat_storage + SHEET_MATERIAL_AMOUNT)
	play_sfx(src, SFX_EFFECTS_PHASEIN, 0.15)
	task.loaded_any = TRUE
	task.sheets.use(1)
	return can_load_sheet(task.sheets) ? STEP_REPEAT(1.5 SECONDS) : STEP_DONE

/obj/item/gun/magnetic/matfed/proc/sheets_done(datum/task/timed/load_sheets/task)
	loading = FALSE
	var/mob/user = task.actor
	if(task.loaded_any && user)
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " loads %T% with \the [task.sheets]."))
		play_sfx(src, SFX_WEAPONS_FLIPBLADE)

/// Old attackby: the parent's first, then its own.
/obj/item/gun/magnetic/matfed/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/thing = A.held
	. = ..()
	update_rating_mod()
	if(removable_components)
		if(istype(thing, /obj/item/stock_parts/manipulator))
			if(manipulator)
				to_chat(user, span_warning("\The [src] already has \a [manipulator] installed."))
				return
			if(!move_into(src, nameof(src.manipulator), thing, user))
				return
			play_sfx(src, SFX_MACHINES_CLICK, 0.2)
			mat_cost = initial(mat_cost) / (2*manipulator.rating)
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " slots %I% into %T%."), item = manipulator)
			update_rating_mod()
			return

	if(is_type_in_list(thing, load_type))
		var/obj/item/stack/material/M = thing
		var/success = FALSE
		if(istype(M)) //stack
			if(!M.material || M.material.name != ammo_material || loading)
				return

			if(mat_storage + SHEET_MATERIAL_AMOUNT > max_mat_storage)
				to_chat(user, span_warning("\The [src] cannot hold more [ammo_material]."))
				return
			loading = TRUE
			if(!can_load_sheet(M) || istext(task_start(/datum/task/timed/load_sheets, user, src, receiver = src, sheets = M)))
				loading = FALSE
			return

		else //ore
			if(M.material != ammo_material)
				return

			if(mat_storage + (SHEET_MATERIAL_AMOUNT/2*0.8) > max_mat_storage)
				to_chat(user, span_warning("\The [src] cannot hold more [ammo_material]."))
				return

			consume(M, user)
			set_mat_storage(mat_storage + (SHEET_MATERIAL_AMOUNT/2*0.8)) //two plasma ores needed per sheet, some inefficiency for not using refined product
			success = TRUE
		if(success)
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " loads %T% with %I%."), item = M)
			play_sfx(src, SFX_WEAPONS_FLIPBLADE)
		return

#define GEN_STARTING -1
#define GEN_OFF 0
#define GEN_IDLE 1
#define GEN_ACTIVE 2

/obj/item/gun/magnetic/matfed/phoronbore/get_mechanics_info(list/additional_information)
	return ..(list("The projectile travels six tiles before dissipating, excavating mineral walls as it does so. \
	It is reloaded with phoron sheets or ore, and has a togglable generator that can recharge the power cell using stored phoron.") + additional_information)

/obj/item/gun/magnetic/matfed/phoronbore
	name ="portable phoron bore"
	desc = "A large man-portable tunnel bore, using phorogenic plasma blasts. Point away from user."
	description_fluff = "An aging Grayson Manufactories mining tool used for rapidly digging through rock. Mass production was discontinued when many of the devices were stolen and used to break into a high security facility by Boiling Point drones."
	description_antag = "This device is exceptional at breaking down walls, though it is incredibly loud when doing so."

	icon_state = "bore"
	item_state = "bore"
	wielded_item_state = "bore-wielded"
	one_handed_penalty = 5

	projectile_type = /obj/item/projectile/bullet/magnetic/bore

	gun_unreliable = 0
	power_cost = 100
	ammo_material = MAT_PHORON

	actions_types = list(/datum/action/item_action/toggle_internal_generator)

	var/datum/looping_sound/small_motor/soundloop
	COOLDOWN_DECLARE(stop_lockout_cooldown) //to keep the soundloop from being "stopped" too soon and playing indefinitely

CAPABILITIES(/obj/item/gun/magnetic/matfed/phoronbore)
	owns_one(nameof(soundloop), /datum/looping_sound/small_motor)

/// Generator stage (GEN_OFF/STARTING/IDLE/ACTIVE).
/obj/item/gun/magnetic/matfed/phoronbore/var/generator_state = GEN_OFF
TRACKED(/obj/item/gun/magnetic/matfed/phoronbore, generator_state)

/obj/item/gun/magnetic/matfed/phoronbore/consume_next_projectile()
	if(!check_ammo() || !capacitor || capacitor.charge < power_cost)
		return

	use_ammo()
	capacitor.use(power_cost)

	return new projectile_type(src, rating_modifier)

/obj/item/gun/magnetic/matfed/phoronbore/examine(mob/user)
	. = ..()
	if(rating_modifier)
		. += span_notice("A display on the side slowly scrolls the text \"BLAST EFFICIENCY [rating_modifier]\".")
	else // rating_mod 0 = something's not right
		. += span_warning("A display on the side slowly scrolls the text \"ERR: MISSING COMPONENT - EFFICIENCY MODIFICATION INCOMPLETE\".")

/obj/item/gun/magnetic/matfed/phoronbore/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(soundloop), new /datum/looping_sound/small_motor(list(src), 0))


/obj/item/gun/magnetic/matfed/phoronbore/ui_action_click(mob/user, actiontype)
	toggle_generator(user)

/// The bore also steps while its
/// generator runs, whatever the capacitor is doing.
/obj/item/gun/magnetic/matfed/phoronbore/steps_now(datum/act/A)
	return generator_state > GEN_OFF || capacitor || cell

/obj/item/gun/magnetic/matfed/phoronbore/magnetic_step(datum/act/timer/A)
	if(generator_state && !mat_storage)
		audible_message(span_notice("\The [src] goes quiet."),span_notice("A motor noise cuts out."), runemessage = "goes quiet")
		soundloop.stop()
		set_generator_state(GEN_OFF)

	else if(generator_state > GEN_OFF)
		if(generator_state == GEN_IDLE && (cell?.percent() < 80 || (!cell && capacitor && capacitor.charge/capacitor.max_charge < 0.8)))
			set_generator_state(GEN_ACTIVE)
		else if(generator_state == GEN_ACTIVE && (!cell || cell.fully_charged()) && (!capacitor || capacitor.charge == capacitor.max_charge))
			set_generator_state(GEN_IDLE)
		soundloop.speed = generator_state
		generator_generate()

	if(capacitor)
		if(cell)
			if(capacitor.charge < capacitor.max_charge && cell.checked_use(power_per_tick))
				capacitor.charge(power_per_tick)
		else if(!generator_state)
			capacitor.use(capacitor.charge * 0.05)


/obj/item/gun/magnetic/matfed/phoronbore/proc/generator_generate()
	var/fuel_used = generator_state == GEN_IDLE ? 5 : 25
	var/power_made = fuel_used * 800 * CELLRATE //20kW when active, same power as a pacman on setting one, but less efficient because compact and portable
	if(cell)
		cell.give(power_made)
	else if(capacitor)
		capacitor.charge(power_made)
	set_mat_storage(max(mat_storage - fuel_used, 0))
	var/turf/T = get_turf(src)
	if(T)
		T.assume_gas(GAS_CO2, fuel_used * 0.01, T0C+200)

/obj/item/gun/magnetic/matfed/phoronbore/proc/toggle_generator(mob/living/user)
	if(!generator_state && !mat_storage)
		to_chat(user, span_notice("\The [src] has no fuel!"))
		return

	else if(!generator_state)
		set_generator_state(GEN_STARTING)
		pull_cord(user, (!cell || cell.charge < 100) ? rand(1,4) : 0)

	else if(generator_state > GEN_OFF && COOLDOWN_FINISHED(src, stop_lockout_cooldown))
		soundloop.stop()
		audible_message(span_notice("\The [src] goes quiet."),span_notice("A motor noise cuts out."), runemessage = "goes quiet")
		set_generator_state(GEN_OFF)

/// Pulls the cord (2 seconds a pull, a timed action each) until the motor starts.
/obj/item/gun/magnetic/matfed/phoronbore/proc/pull_cord(mob/living/user, pulls)
	if(pulls > 0)
		play_sfx(src, SFX_ITEMS_SMALL_MOTOR_MOTOR_PULL_ATTEMPT)
		task_timed(user, 2 SECONDS, src, src, PROC_REF(pull_cord), list(user, pulls - 1), on_fail = PROC_REF(pull_abandoned))
		return
	soundloop.start()
	COOLDOWN_START(src, stop_lockout_cooldown, 3 SECONDS)
	cell?.use(100)
	audible_message(span_notice("\The [src] starts chugging."),span_notice("A motor noise starts up."), runemessage = "whirr")
	set_generator_state(GEN_IDLE)

/obj/item/gun/magnetic/matfed/phoronbore/proc/pull_abandoned()
	set_generator_state(GEN_OFF)

/obj/item/gun/magnetic/matfed/phoronbore/loaded
	cell = /obj/item/cell/apc
	capacitor = /obj/item/stock_parts/capacitor

#undef GEN_STARTING
#undef GEN_OFF
#undef GEN_IDLE
#undef GEN_ACTIVE
