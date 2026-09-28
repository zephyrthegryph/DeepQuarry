// It is a gizmo that flashes a small area
/obj/machinery/flasher
	name = "Mounted flash"
	desc = "A wall-mounted flashbulb device."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "mflash1"
	layer = ABOVE_WINDOW_LAYER
	flags = WALL_ITEM
	var/id = null
	var/range = 2 //this is roughly the size of brig cell
	var/disable = 0
	COOLDOWN_DECLARE(flash_cooldown) //Don't want it getting spammed like regular flashes
	var/strength = 10 //How weakened targets are when flashed.
	var/base_state = "mflash"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2

/obj/machinery/flasher/portable //Portable version of the flasher. Only flashes when anchored
	name = "portable flasher"
	desc = "A portable flashing device. Wrench to activate and deactivate. Cannot detect slow movements."
	icon_state = "pflash1"
	strength = 8
	anchored = FALSE
	base_state = "pflash"
	density = TRUE

/obj/machinery/flasher/portable/Initialize(mapload)
	..()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/flasher/portable/LateInitialize()
	// Map start flashers enable proximity sensing
	if(anchored)
		add_overlay("[base_state]-s")
		sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))

/obj/machinery/flasher/power_change()
	..()
	if(!(stat & NOPOWER))
		icon_state = "[base_state]1"
	else
		icon_state = "[base_state]1-p"

//Don't want to render prison breaks impossible
/obj/machinery/flasher/wirecutter_act(mob/user, obj/item/tool)
	add_fingerprint(user)
	disable = !disable
	user.visible_message(span_warning("[user] has [disable ? "disconnected" : "connected"] [src]'s flashbulb!"), span_warning("You [disable ? "disconnect" : "connect"] [src]'s flashbulb!"))
	return ITEM_INTERACT_SUCCESS

//Let the AI trigger them directly.
EXTEND_INTERACTIONS(/obj/machinery/flasher, INTERACT_SILICON("Flash", PROC_REF(flasher_silicon_trigger)))

/// Old attack_ai: the AI triggers it directly while it is anchored.
/obj/machinery/flasher/proc/flasher_silicon_trigger(mob/user, obj/item/held, datum/interaction/interaction)
	if(anchored)
		flash()
	return TRUE

/obj/machinery/flasher/proc/flash()
	if(!(powered()))
		return

	if((disable) || !COOLDOWN_FINISHED(src, flash_cooldown))
		return

	play_sfx(src, SFX_WEAPONS_FLASH)
	flick("[base_state]_flash", src)
	COOLDOWN_START(src, flash_cooldown, 15 SECONDS)
	use_power(1500)

	for (var/mob/O in viewers(src, null))
		if(get_dist(src, O) > range)
			continue

		var/flash_time = strength
		if(ishuman(O))
			var/mob/living/carbon/human/H = O
			if(H.nif && H.nif.flag_check(NIF_V_FLASHPROT,NIF_FLAGS_VISION))
				H.nif.notify("High intensity light detected, and blocked!",TRUE)
				continue
			if(H.has_mutation(FLASHPROOF))
				continue
			if(H.eyecheck() > 0)
				continue
			flash_time *= H.species.flash_mod
			var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
			if(!E)
				return
			if(E.is_bruised() && prob(E.damage + 50))
				H.flash_eyes()
				H.injure(INJURY_BURN, rand(1, 5), E, src, flags = INJURE_SILENT)
		else
			if(!O.blinded && isliving(O))
				var/mob/living/L = O
				L.flash_eyes()
		O.status_at_least(EFFECT_WEAKENED, flash_time)

/obj/machinery/flasher/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF || stat & (BROKEN|NOPOWER))
		return
	if(prob(75/severity))
		flash()

/obj/machinery/flasher/portable/HasProximity(turf/T, WF, oldloc)
	if(isnull(WF))
		return

	var/atom/movable/AM = om_resolve(WF)
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
		return
	if(disable || !anchored || !COOLDOWN_FINISHED(src, flash_cooldown))
		return

	if(iscarbon(AM))
		var/mob/living/carbon/M = AM
		if(M.m_intent != I_WALK)
			flash()

/obj/machinery/flasher/portable/wrench_act(mob/user, obj/item/tool)
	add_fingerprint(user)
	anchored = !anchored
	if(!anchored)
		user.show_message(span_warning("[src] can now be moved."))
		cut_overlays()
		unsense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))
	else
		user.show_message(span_warning("[src] is now secured."))
		add_overlay("[base_state]-s")
		sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/button/flasher
	name = "flasher button"
	desc = "A remote control switch for a mounted flasher."

/obj/machinery/button/flasher/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/flasher_button_trigger,
	)
	..()

/// Old attack_hand: trigger the linked flashers.
/datum/interaction/machine_hand/flasher_button_trigger
	id = "flasher_button_trigger"
	name = "Press"
	effect = /obj/machinery/button/flasher/proc/interaction_trigger

/obj/machinery/button/flasher/proc/interaction_trigger(mob/user, obj/item/held, datum/interaction/interaction)
	use_power(5)

	if(active)
		return TRUE

	active = TRUE
	icon_state = "launcheract"

	for(var/obj/machinery/flasher/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			M.flash()

	om_after_unique(src, 5 SECONDS, PROC_REF(finish_trigger))
	return TRUE

/obj/machinery/button/flasher/proc/finish_trigger()
	PRIVATE_PROC(TRUE)
	icon_state = "launcherbtt"
	active = FALSE
