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
	/// The air of its tile is at or past ARTIFACT_HEAT_BREAK (gas_level()).
	var/overheated = FALSE
TRACKED(/obj/machinery/artifact, icon_num)
TRACKED(/obj/machinery/artifact, overheated)

/// Air too hot: it breaks. Its tile's air crossing ARTIFACT_HEAT_BREAK turns `overheated` (gas_level(), code/domains/atmos/gas_level.dm), and a
/// move re-points the level at the new tile's air.
CAPABILITIES(/obj/machinery/artifact)
	gas_level(into = nameof(overheated), reading = CH_GAS_TEMPERATURE, above = ARTIFACT_HEAT_BREAK, hysteresis = 50)
	on_change(nameof(overheated), ENTER, then(PROC_REF(burst_in_heat)))

/obj/machinery/artifact/proc/burst_in_heat(datum/act/A)
	SHOULD_NOT_SLEEP(TRUE)
	destroyed(src)

/obj/machinery/artifact/Moved(atom/old_loc)
	. = ..()
	if(isturf(loc) && !QDELETED(src))
		gas_level_rearm_all(src)


// ALLOW(init/INSTANCE_STATE): rolls its look and the trigger of its effect
/obj/machinery/artifact/Initialize(mapload)

	if(artifact_master_type)
		make_artifact_master(src, artifact_master_type)

	if(!istype(artifact_master))
		return

	var/datum/artifact_effect/my_effect = artifact_master.get_primary() //Gets the primary effect of the artifact.

	if(!isnull(predefined_icon_num))
		set_icon_num(predefined_icon_num)
	else
		set_icon_num(rand(0, 15))

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
/obj/machinery/artifact/proc/appearance_active()
	return LAZYLEN(artifact_master?.get_active_effects()) ? 1 : 0

/// The look (the draw sweep: from its template).
/obj/machinery/artifact/draw(datum/look/look)
	..()
	look.state("ano[icon_num][appearance_active()]")

/obj/machinery/artifact
	icon = 'icons/obj/xenoarchaeology.dmi'

