MATERIAL_MIX(/obj/item/laser_pointer, list(MAT_GLASS = 500, MAT_STEEL = 500))
/obj/item/laser_pointer
	name = "laser pointer"
	desc = "Don't shine it in your eyes!"
	icon = 'icons/obj/device.dmi'
	icon_state = "pointer"
	item_state = "pen"
	var/pointer_icon_state
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL //Increased to 2, because diodes are w_class 2. Conservation of matter.
	var/turf/pointer_loc
	var/energy = 8
	var/max_energy = 8
	var/effectchance = 20
	var/cooldown = 10
	EXPIRY_DECLARE(last_used_time)
	var/recharge_locked = 0
	var/obj/item/stock_parts/micro_laser/diode //used for upgrading!
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE


/obj/item/laser_pointer/red
	pointer_icon_state = "red_laser"
/obj/item/laser_pointer/green
	pointer_icon_state = "green_laser"
/obj/item/laser_pointer/blue
	pointer_icon_state = "blue_laser"
/obj/item/laser_pointer/purple
	pointer_icon_state = "purple_laser"

TYPE_TABLE_DECLARE(/obj/item/laser_pointer, pointer_forced_diode, null)

/// The diode type a pointer is made with (its constructor param), or the type's forced one.
/obj/item/laser_pointer/var/diode_path

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/item/laser_pointer/proc/fit_diode(laser_path)
	var/forced_diode = TYPE_TABLE_GET(src, pointer_forced_diode)
	if(forced_diode)
		laser_path = forced_diode
	if(ispath(laser_path))
		rel_set(src, nameof(diode), new laser_path(src))
	else
		rel_set(src, nameof(diode), new /obj/item/stock_parts/micro_laser(src))

TYPE_TABLE(/obj/item/laser_pointer/upgraded, pointer_forced_diode, /obj/item/stock_parts/micro_laser)

TYPE_TABLE(/obj/item/laser_pointer/ultimate, pointer_forced_diode, /obj/item/stock_parts/micro_laser)

/obj/item/laser_pointer/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	laser_act(M, user)
	return ITEM_INTERACT_SUCCESS

CAPABILITIES(/obj/item/laser_pointer)
	op("item", item(/obj/item/stock_parts/micro_laser), label("Install"), then(PROC_REF(interaction_item)))
	// The battery trickles back while recharging.
	every(2 SECONDS, then(PROC_REF(laser_pointer_step)), when = nameof(recharging))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))
	param(nameof(diode_path), pos = 1, apply = PROC_REF(fit_diode))
	rolls(nameof(pointer_icon_state), pick_one(list("red_laser", "green_laser", "blue_laser", "purple_laser")), when = cond_not(nameof(pointer_icon_state)))

/obj/item/laser_pointer/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!diode)
		if(!move_into(src, nameof(src.diode), W, user))
			return TRUE
		to_chat(user, span_notice("You install a [diode.name] in [src]."))
	else
		to_chat(user, span_notice("[src] already has a diode."))
	return TRUE

/obj/item/laser_pointer/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!diode)
		return OP_OK
	to_chat(user, span_notice("You remove the [diode.name] from the [src]."))
	diode.forceMove(get_turf(loc))
	rel_take(src, nameof(diode))
	return OP_OK

/obj/item/laser_pointer/afterattack(atom/target, mob/living/user, flag, params)
	if(flag)	//we're placing the object on a table or in backpack
		return
	laser_act(target, user)

/obj/item/laser_pointer/proc/laser_act(atom/target, mob/living/user)
	if(!(user in (viewers(world.view,target))))
		return
	if(!(target in view(user, world.view)))
		return
	if(!(ELAPSED(src, last_used_time, CLOCK_WORLD) >= cooldown))
		return
	if (!diode)
		to_chat(user, span_notice("You point [src] at [target], but nothing happens!"))
		return
	if (!user.IsAdvancedToolUser())
		to_chat(user, span_warning("You don't have the dexterity to do this!"))
		return

	add_fingerprint(user)

	//nothing happens if the battery is drained
	if(recharge_locked)
		to_chat(user, span_notice("You point [src] at [target], but it's still charging."))
		return

	var/outmsg
	var/turf/targloc = get_turf(target)

	//human/alien mobs
	if(ishuman(target))
		if(user.zone_sel.selecting == "eyes")
			var/mob/living/carbon/human/H = target

			//20% chance to actually hit the eyes

			if(prob(effectchance * diode.rating))
				add_attack_logs(user, H, "Tried blinding using [src]")

				//eye target check, will return -2 to 2
				var/eye_prot = H.eyecheck()
				if(!H.has_vision() || eye_prot >= FLASH_PROTECTION_MAJOR)
					eye_prot = 100 //Immune
				var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
				if(!E || eye_prot == 100)
					outmsg = span_notice("You shine [src] at [H] with no response.")
				else
					outmsg = span_notice("You shine [src] into [H]'s eyes.")
					//Comment to explain the below math because reading it makes my eyes glaze over:
					// Rand 0-1 + diode.rating(1 to 5) minus eye protection. (This can be anywhere between 0 and 8, depending on protection and thermals)
					// We then multiply by flash_mod (usually 1, 1.5, or 2) and then clamp it. Min 0, max 16 now.
					// We then round it (whole numbers, let's not deal 5.281 damage to someone's eyes) and clamp it in case of any weirdness so we don't get negatives.
					var/severity = CLAMP(round((rand(0, 1) + diode.rating - eye_prot) * H.species.flash_mod), 0, 100) //If you get a severity above 100 I'm impressed.
					//Handle the visual flash effect first
					if(severity >= 4)
						flick("e_flash", H.flash_eyes())
					else if(severity >= 2)
						flick("flash", H.flash_eyes())

					//Handle the weakness effect afterwards
					if(severity >= 3)
						if(prob(severity * diode.rating))
							H.status_at_least(STAT_WEAKENED, max(H.status_units(STAT_WEAKENED), severity - 2))
						H.injure(INJURY_BURN, severity - 2, E, src, flags = INJURE_SILENT)

					var/eye_message = span_info("A small, bright dot appears in your vision.")
					switch(severity)
						if(1)
							eye_message = span_notice("Something bright flashes in the corner of your vision.")
						if(2)
							eye_message = span_danger("A bright light shines across your eyes!")
						if(3)
							eye_message = span_danger("A bright light briefly blinds you!")
						if(4)
							eye_message = span_danger("A blinding light burns your eyes!")
					if(severity > 4)
						eye_message = span_bolddanger("It feels like the sun is being beamed directly into your eyes!") //Bolddanger because you are taking MASSIVE eye damage.
					to_chat(H, eye_message)
			else
				outmsg = span_notice("You shine the [src] at [H], but miss their eyes.")

	//robots and AI
	else if(issilicon(target))
		var/mob/living/silicon/S = target
		//20% chance to actually hit the sensors
		if(prob(effectchance * diode.rating))
			flick("flash", S.flash_eyes(affect_silicon = TRUE))
			if (prob(3 * diode.rating))
				S.status_at_least(STAT_WEAKENED, 1)
			to_chat(S, span_warning("Your sensors were blinded by a laser!"))
			outmsg = span_notice("You blind [S] by shining [src] at their sensors.")
			add_attack_logs(user,S,"Tried disabling using [src]")
		else
			outmsg = span_notice("You shine the [src] at [S], but miss their sensors.")

	//cameras
	else if(istype(target, /obj/machinery/camera))
		var/obj/machinery/camera/C = target
		if(prob(effectchance * diode.rating))
			C.camera_disrupt(CLAMP(4 - diode.rating, 1, 4))
			outmsg = span_notice("You shine the [src] into the lens of [C].")
			add_attack_logs(user,C,"Disabled using [src]")
		else
			outmsg = span_info("You missed the lens of [C] with [src].")
			add_attack_logs(user,C,"Tried disabling using [src]")

	//cats!
	for(var/mob/living/simple_mob/animal/passive/cat/C in viewers(1,targloc))
		if (!(C.stat || C?.buckled_to()))
			if(prob(50) && !(C.client))
				act_message(C, null, MSG_SELF(span_warning("You pounce on the light!")), MSG_OTHERS(span_warning("%U% pounces on the light!")))
				step_towards(C, targloc)
				C.lay_down()
				after(C, 1 SECOND, "lay_down")
			else
				C.set_dir(get_dir(C,targloc))
				act_message(C, null, MSG_SELF(span_notice("Your attention is drawn to the mysterious glowing dot.")), MSG_OTHERS(span_notice("%U% watches the light.")))


	//laser pointer image
	icon_state = "[initial(icon_state)]_[pointer_icon_state]"
	var/list/showto = list()
	for(var/mob/M in viewers(world.view,targloc))
		if(M.client)
			showto.Add(M.client)
	var/image/I = image('icons/obj/projectiles.dmi',targloc,pointer_icon_state,cooldown)
	I.plane = PLANE_LIGHTING_ABOVE
	I.pixel_x = target.pixel_x + rand(-5,5)
	I.pixel_y = target.pixel_y + rand(-5,5)

	if(outmsg)
		act_message(user, src, MSG_SELF(outmsg), MSG_OTHERS(span_info("%U% points %T% at [target].")))
	else
		act_message(user, src, MSG_SELF(span_info("You point %T% at [target].")), MSG_OTHERS(span_info("%U% points %T% at [target].")))

	EXPIRY_STAMP(src, last_used_time, CLOCK_WORLD)
	energy -= 1
	if(energy <= max_energy)
		set_recharging(TRUE)
		if(energy <= 0)
			to_chat(user, span_warning("You've overused the battery of [src], now it needs time to recharge!"))
			recharge_locked = TRUE

	flick_overlay(I, showto, cooldown)
	after(src, cooldown, PROC_REF(reset_laser_icon))

/obj/item/laser_pointer/proc/reset_laser_icon()
	icon_state = initial(icon_state)

/obj/item/laser_pointer/proc/laser_pointer_step(datum/act/timer/A)
	if(prob(20 - recharge_locked*5))
		energy++
		if(energy >= max_energy)
			energy = max_energy
			set_recharging(FALSE)
			recharge_locked = FALSE

/obj/item/laser_pointer/ownership()
	. = ..()
	. += owns(nameof(diode), policy = OWN_CONTAINED)

/obj/item/laser_pointer/var/recharging = 0
TRACKED(/obj/item/laser_pointer, recharging)

/// Relation view: pointer loc (reads null once it is gone).
/obj/item/laser_pointer/proc/pointer_loc() as /turf
	return pointer_loc
