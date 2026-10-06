//Xenoarch machinery spawning code!
//These are colloquially refered to 'large' artifacts.
//The below dictates the icon, description, and the activation requirement.
//Additionally, it updates the icon based on if it's active or not.
//What the artifact does itself is dictated by effect.dm.

/obj/machinery/artifact
	name = "alien artifact"
	desc = "A large alien device."
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "ano00"
	var/icon_num = 0
	density = TRUE
	//Note: If you adminspawn this, it will NOT have an assosciated artifact_id. You have to manually set it!

	var/predefined_icon_num

	/// The artifact master type created at Initialize (the instance lives in /atom/var/artifact_master).
	var/artifact_master_type = /datum/artifact_master

/// Air too hot: it breaks. Otherwise it sleeps on a watch of its tile's air crossing
/// ARTIFACT_HEAT_BREAK (and re-arms when moved).
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/artifact)
	started_work(step = PROC_REF(work_step))

/obj/machinery/artifact/proc/work_step(datum/act/timer/A)
	var/turf/T = get_turf(src)
	var/datum/gas_mixture/env = T?.return_air()
	if(env && env.return_temperature() > ARTIFACT_HEAT_BREAK)
		destroyed(src)
		return PROCESS_KILL
	var/datum/om_watch/W = om_watch_arm_bands(src, "heat", env?.arena_id(), list(new /datum/om_watch_band("temperature", TRUE, ARTIFACT_HEAT_BREAK)), null, om_callable(src, PROC_REF(heat_wake)))
	if(W)
		LAZYSET(W.last_side, "temperature:[TRUE]:[ARTIFACT_HEAT_BREAK]", FALSE) // below it now: the first reading above fires
	return PROCESS_KILL

/obj/machinery/artifact/proc/heat_wake()
	work_start(src)

/obj/machinery/artifact/Moved(atom/old_loc)
	. = ..()
	if(isturf(loc) && !QDELETED(src))
		work_start(src)


// ALLOW(init/INSTANCE_STATE): rolls its look and the trigger of its effect
/obj/machinery/artifact/Initialize(mapload)

	if(artifact_master_type)
		make_artifact_master(src, artifact_master_type)

	if(!istype(artifact_master))
		return

	var/datum/artifact_effect/my_effect = artifact_master.get_primary() //Gets the primary effect of the artifact.

	if(!isnull(predefined_icon_num))
		icon_num = predefined_icon_num
	else
		icon_num = rand(0, 15)

	icon_state = "ano[icon_num]0"
	if(icon_num == 7 || icon_num == 8 || icon_num == 15)
		name = "large crystal"
		desc = pick("It shines faintly as it catches the light.",
		"It appears to have a faint inner glow.",
		"It seems to draw you inward as you look it at.",
		"Something twinkles faintly as you look at it.",
		"It's mesmerizing to behold.")
		my_effect.trigger = pick(TRIGGER_ENERGY, TRIGGER_TOUCH)
	else if(icon_num == 9 || icon_num == 17 || icon_num == 19)
		name = "alien computer"
		desc = "It is covered in strange markings."
		my_effect.trigger = TRIGGER_TOUCH
	else if(icon_num == 10)
		desc = "A large alien device, there appear to be some kind of vents in the side."
		my_effect.trigger = pick(TRIGGER_ENERGY, TRIGGER_HEAT, TRIGGER_COLD)
	else if(icon_num == 11)
		name = "sealed alien pod"
		desc = "A strange alien device."
		my_effect.trigger = pick(TRIGGER_WATER, TRIGGER_ACID, TRIGGER_VOLATILE, TRIGGER_TOXIN)
	else if(icon_num == 12 || icon_num == 14)
		name = "intricately carved statue"
		desc = "A strange statue."
		my_effect.trigger = pick(TRIGGER_TOUCH, TRIGGER_HEAT, TRIGGER_COLD)
	artifact_master.do_large_randomization()
	. = ..()
	update_icon()
/obj/machinery/artifact/proc/appearance_active()
	return LAZYLEN(artifact_master?.get_active_effects()) ? 1 : 0

APPEARANCE_TEMPLATE(/obj/machinery/artifact, "ano{icon_num}{appearance_active}")

/obj/machinery/artifact
	icon = 'icons/obj/xenoarchaeology.dmi'

