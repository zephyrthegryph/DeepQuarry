
/* Trait state that handles species effects for mobs/species when they are afflicted with radiation.
 * Allows for glowing, healing, contamination, and immunity.
 */
/datum/trait_state/radiation_effects
	unique_type = /datum/trait_state/radiation_effects

	///If we show the user the radiation panel.
	var/show_panel = TRUE

	///Below this value, no glow occurs.
	var/radiation_glow_threshold = 50

	///If we spread radiation or not.
	var/contamination = FALSE

	///Strength of our contamination, if we contaminate. Each 1 strength is 100% of the rads we're dissipating.
	var/contamination_strength = 0.1

	///What level our radiation has to be above to begin to contaminate our surroundings.
	var/contamination_threshold = 600

	///If we can control if we glow or not
	var/glow_toggle = TRUE

	///If we glow or not.
	var/glows = TRUE

	///What color we glow.
	var/radiation_color = "#c3f314"

	///Intensity modifier of our glow
	var/intensity_mod = 1

	///Range modifier of our glow
	var/range_mod = 1

	///How much we divide our radiation by to determine how far our glow is.
	var/range_coefficient = 100

	///How much we divide our radiation by to determine how intense our glow is.
	var/intensity_coefficient = 150

	///If we are immune to radiation damage or not.
	var/radiation_immunity = FALSE

	///If we heal from radiation or not
	var/radiation_healing = FALSE

	///If we dissipate radiation or keep it.
	var/radiation_dissipation = TRUE

	//Radiation Nutrition vars
	///If we gain nutrition from radiation.
	var/radiation_nutrition = FALSE

	///If we can toggle gaining nutrition from radiation.
	var/nutrition_toggle = FALSE

	///What is the max nutrition we can gain from radiation.
	var/radiation_nutrition_cap = 1000

	//Radiation Damage vars
	///If we do custom damage handling from radiation.
	var/custom_damage = FALSE

	///What type of damage we take from radiation.
	var/injury_kind = INJURY_TOXIN

	///How much the damage we take from rads is multiplied by.
	var/damage_multiplier = 1.0

	///If we use a toony glow instead of a more emmissive one.
	var/toony = FALSE

/datum/trait_state/radiation_effects/setup(glows, radiation_glow_minor_threshold, contamination, contamination_strength, radiation_color, intensity_mod, range_mod, radiation_immunity, radiation_healing, radiation_dissipation, radiation_nutrition, radiation_nutrition_cap, glow_toggle, nutrition_toggle, toony)

	if(!isliving(owner))
		return FALSE
	if(glows)
		src.glows = glows
	if(glow_toggle)
		src.glow_toggle = glow_toggle
	if(radiation_glow_threshold)
		src.radiation_glow_threshold = radiation_glow_threshold
	if(contamination)
		src.contamination = contamination
	if(contamination_strength)
		src.contamination_strength = contamination_strength
	if(radiation_color)
		src.radiation_color = radiation_color
	if(intensity_mod)
		src.intensity_mod = intensity_mod
	if(range_mod)
		src.range_mod = range_mod
	if(radiation_immunity)
		src.radiation_immunity = radiation_immunity
	if(radiation_nutrition)
		src.radiation_nutrition = radiation_nutrition
	if(nutrition_toggle)
		src.nutrition_toggle = nutrition_toggle
	if(radiation_nutrition_cap)
		src.radiation_nutrition_cap = radiation_nutrition_cap
	if(radiation_healing)
		src.radiation_healing = radiation_healing
	if(radiation_dissipation)
		src.radiation_dissipation = radiation_dissipation
	if(custom_damage)
		src.custom_damage = custom_damage
	if(injury_kind)
		src.injury_kind = injury_kind
	if(damage_multiplier)
		src.damage_multiplier = damage_multiplier

	if(show_panel)
		grant(owner, granted_verb(/mob/living/proc/radiation_control_panel), src)

	if(toony)
		src.toony = toony
	return TRUE

/datum/trait_state/radiation_effects/attach()
	..()
	observe(owner, /datum/act/live_radiation, src, instead(then(PROC_REF(on_handle_radiation))))
	observe(owner, /datum/act/irradiate, src, instead(then(PROC_REF(on_irradiate_effect))))
	observe(owner, /datum/act/geiger_scan, src, instead(then(PROC_REF(on_geiger_counter_scan))))

/// Removes the control-panel verb and the radiation glow filter.
/datum/trait_state/radiation_effects/detach()
	var/atom/movable/parent_movable = owner
	if(show_panel)
		revoke(owner, granted_verb(/mob/living/proc/radiation_control_panel), src)

	if(istype(parent_movable))//For the toony glow.
		var/filter = parent_movable.get_filter("rad_glow")
		if(filter)
			parent_movable.remove_filter("rad_glow")
	..()

/datum/trait_state/radiation_effects/life_tick()
	process_glow()

/datum/trait_state/radiation_effects/proc/process_glow()
	var/mob/living/living_guy = owner
	if(!glows)
		if(living_guy.glow_override) //Toggled glow off while we were still actively glowing.
			living_guy.set_glow_override(FALSE)
			living_guy.set_light(0)
			living_guy.remove_filter("rad_glow")
		return
	if(living_guy.radiation < radiation_glow_threshold)
		living_guy.set_glow_override(FALSE)
		living_guy.set_light(0)
		living_guy.remove_filter("rad_glow")
		return

	if(glows)
		var/light_range = CLAMP((living_guy.radiation/range_coefficient) * range_mod, 1, 7) //Min 1, max 7
		var/light_power = CLAMP(living_guy.radiation/intensity_coefficient * intensity_mod, 1, 10)

		living_guy.set_light(l_range = light_range, l_power = light_power, l_color = radiation_color, l_on = TRUE)
		living_guy.set_glow_override(TRUE)
		if(toony)
			var/filter = living_guy.get_filter("rad_glow")
			if(!filter)
				create_toony_glow()

/datum/trait_state/radiation_effects/proc/on_handle_radiation(datum/act/live_radiation/tick)
	SHOULD_NOT_SLEEP(TRUE)
	return process_component() ? TRUE : HOOK_DECLINE

///Handles the radiation removal, immunity, and healing effects.
/datum/trait_state/radiation_effects/proc/process_component()
	var/mob/living/living_guy = owner
	if(QDELETED(owner))
		return

	//Radiation calculation, done here since contamination uses it
	var/rad_removal_mod = 1
	var/rads = living_guy.radiation * 0.04
	if(!rads)
		return

	if(ishuman(living_guy))
		var/mob/living/carbon/human/human_guy = owner
		rad_removal_mod = human_guy.species.rad_removal_mod
	//End of the calculation.

	if(contamination && living_guy.radiation > contamination_threshold)
		radiation_pulse(
			living_guy,
			max_range = 2,
			threshold = RAD_MEDIUM_INSULATION,
			chance = CLAMP(rads * contamination_strength, 0, 25),
			minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
			strength = rads * contamination_strength
		)

	///Used for radiation nutrition and healing.
	var/rads_to_utilize

	if(radiation_nutrition)
		if(living_guy.nutrition < radiation_nutrition_cap)
			rads_to_utilize = rads * rad_removal_mod
			living_guy.adjust_nutrition(rads_to_utilize)

	if(radiation_immunity || radiation_healing)
		//We have to remove radiation here since we're blocking radiation altogether.
		if(!rads_to_utilize) //In case we did it above. Save some CPU.
			rads_to_utilize = rads * rad_removal_mod

		//If we heal from radiation, we will dissipate (use up) the amount we heal.
		if(radiation_healing)
			living_guy.purge_radiation(rads_to_utilize)
			rads_to_utilize = CLAMP(rads_to_utilize, 1, 10) //Only heal up to 10 rads.
			living_guy.mend(TREAT_TISSUE_REPAIR, rads_to_utilize)
			living_guy.mend(TREAT_PLATING_REPAIR, rads_to_utilize)
			living_guy.mend(TREAT_BURN_CARE, rads_to_utilize)
			living_guy.mend(TREAT_WIRING_REPAIR, rads_to_utilize)
			living_guy.mend(TREAT_OXYGENATION, rads_to_utilize)
			living_guy.mend(TREAT_ANTITOXIN, rads_to_utilize)

		else if(radiation_dissipation)
			living_guy.purge_radiation(rads_to_utilize)

		return COMPONENT_BLOCK_LIVING_RADIATION

	if(custom_damage)
		if(!rads_to_utilize) //In case we did it above. Save some CPU.
			rads_to_utilize = rads * rad_removal_mod

		//Special handling for pain to prevent unfun permastuns. Only lets your pain go to 90% of your endurance, crippling but not KOing you.
		if(injury_kind == INJURY_PAIN && (living_guy.current_pain() + (rads_to_utilize * damage_multiplier)) >= living_guy.get_endurance() * 0.90)
			return COMPONENT_BLOCK_LIVING_RADIATION

		living_guy.injure(injury_kind, rads_to_utilize * damage_multiplier, flags = INJURE_SILENT)

		return COMPONENT_BLOCK_LIVING_RADIATION

/datum/trait_state/radiation_effects/proc/on_irradiate_effect(datum/act/irradiate/dose)
	SHOULD_NOT_SLEEP(TRUE)
	return handle_irradiate_effect(dose.target, dose.effect, IRRADIATE, dose.blocked, dose.check_protection, dose.rad_protection) ? TRUE : HOOK_DECLINE

/datum/trait_state/radiation_effects/proc/handle_irradiate_effect(mob/living/living_guy, effect, effecttype, blocked, check_protection, rad_protection)
	///If we're not contaminating, don't worry about this. Proceed like normal.
	if(!contamination || (contamination && living_guy.radiation < contamination_threshold))
		return

	var/rad_removal_mod = 1
	if(ishuman(living_guy))
		var/mob/living/carbon/human/human_guy = owner
		rad_removal_mod = human_guy.species.rad_removal_mod

	var/radiation_offput = ((living_guy.radiation * 0.04) * contamination_strength * rad_removal_mod)
	var/radiation_to_apply = (effect - radiation_offput)
	if(radiation_to_apply > 0)

		//This stops MOST of the radiation we're offputting from hitting us.
		//If we linger in one place for a prolonged period, the area around us will become irradiated and give us a small bit of radiation back. (only got ~1 rad per tick when we were offputting 60 rads for example)
		//However, we'll lose our rads faster than we accumulate.
		living_guy.add_radiation(radiation_to_apply * rad_protection)
		return COMPONENT_BLOCK_IRRADIATION

///TGUI below here
CAPABILITIES(/datum/trait_state/radiation_effects)
	interface("RadiationConfig", title = "Radiation Config")
	op("toggle_color", ui_act("toggle_color"), then(PROC_REF(ui_act_toggle_color)))
	op("toggle_glow", ui_act("toggle_glow"), then(PROC_REF(ui_act_toggle_glow)))
	op("toggle_nutrition", ui_act("toggle_nutrition"), then(PROC_REF(ui_act_toggle_nutrition)))

/mob/living/proc/radiation_control_panel()
	set name = "Radiation Control Panel"
	set desc = "Allows you to adjust the settings of various radioactive settings!"
	set category = VERB_CAT_ABILITIES_RADIATION

	var/datum/trait_state/radiation_effects/rad = get_radiation_state()
	if(!rad)
		to_chat(src, span_warning("You don't have the radiation trait! This is a bug! Please report this to a maintainer."))
		return FALSE

	rad.tgui_interact(src)

/// /datum/trait_state/radiation_effects's window data.
/datum/trait_state/radiation_effects/ui_data(datum/act/eval/A)
	var/mob/living/living_guy = owner
	var/data = list(
		"glowing" = glows,
		"radiation_color" = radiation_color,
		"glowtoggle" = glow_toggle,
		"radiation_nutrition" = radiation_nutrition,
		"nutrition_toggle" = nutrition_toggle,
		"radiation_nutrition_cap" = radiation_nutrition_cap,
		"current_nutrition" = living_guy.nutrition
	)

	return data

/datum/trait_state/radiation_effects/proc/radiation_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/ask = A.answer
	if(ask.value)
		radiation_color = ask.value
	SStgui.update_uis(src)

/datum/trait_state/radiation_effects/proc/ui_act_toggle_color(datum/act/op/A)
	var/mob/user = A.actor
	open_request(src, /datum/prompt/color, PROC_REF(radiation_color_picked), answerer = user, question = "Select a color you wish your radioactive glow to be!", default = radiation_color, title = "Color Selector", timeout = 0)
	return FALSE

/datum/trait_state/radiation_effects/proc/ui_act_toggle_glow(datum/act/op/A)
	glows = !glows
	to_chat(owner, span_info("You are [glows ? "now" : "no longer"] glowing."))
	return FALSE

/datum/trait_state/radiation_effects/proc/ui_act_toggle_nutrition(datum/act/op/A)
	radiation_nutrition = !radiation_nutrition
	to_chat(owner, span_info("You are [radiation_nutrition ? "now" : "no longer"] gaining nutrition from radiation."))
	return FALSE

/datum/trait_state/radiation_effects/proc/create_toony_glow()
	var/atom/movable/parent_movable = owner
	if (!istype(parent_movable))
		return

	parent_movable.add_filter("rad_glow", 2, list("type" = "outline", "color" = "#39ff1430", "size" = 2))
	after(src, rand(0.1 SECONDS, 1.9 SECONDS), PROC_REF(toony_glow_loop), with = list(parent_movable)) // Things should look uneven

/datum/trait_state/radiation_effects/proc/toony_glow_loop(atom/movable/parent_movable)
	var/filter = parent_movable.get_filter("rad_glow")
	if (!filter)
		return

	animate(filter, alpha = 110, time = 1.5 SECONDS, loop = -1)
	animate(alpha = 40, time = 2.5 SECONDS)

/datum/trait_state/radiation_effects/proc/on_geiger_counter_scan(datum/act/geiger_scan/scan)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/living_source = scan.target
	var/mob/user = scan.user
	var/obj/item/geiger/geiger_counter = scan.counter
	if(living_source.radiation > 0)
		if(contamination && living_source.radiation > contamination_threshold) //Are we spreading radiation?
			to_chat(user, span_bolddanger("[icon2html(geiger_counter, user)] Subject is irradiated and offputting radiation."))
		else
			to_chat(user, span_bolddanger("[icon2html(geiger_counter, user)] Subject is irradiated."))
		return TRUE
	return HOOK_DECLINE

/mob/living/proc/get_radiation_state()
	RETURN_TYPE(/datum/trait_state/radiation_effects)
	return get_trait_state(/datum/trait_state/radiation_effects)

//Subtypes

// Promethean
/datum/trait_state/radiation_effects/promethean
	radiation_immunity = TRUE
	radiation_nutrition = TRUE

// Shadekin
/datum/trait_state/radiation_effects/shadekin
	glows = FALSE
	glow_toggle = FALSE

	nutrition_toggle = TRUE
	radiation_immunity = TRUE
	radiation_nutrition = TRUE

// Black Eyed Shadekin
/datum/trait_state/radiation_effects/besk
	show_panel = FALSE
	glows = FALSE
	glow_toggle = FALSE
	custom_damage = TRUE
	injury_kind = INJURY_PAIN
	damage_multiplier = 0.25

// Diona
/datum/trait_state/radiation_effects/diona
	glows = FALSE
	glow_toggle = FALSE

	nutrition_toggle = TRUE
	radiation_healing = TRUE
	radiation_nutrition = TRUE

/datum/trait_state/radiation_effects/radiation_immune
	show_panel = FALSE
	glows = FALSE
	glow_toggle = FALSE
	radiation_immunity = TRUE

/// Trait system: radiation glow.
/// One Life step per cycle while attached (doc/rewrite/om_retirement.md L1).
/datum/trait_state/radiation_effects/life_steps()
	return list(seq_step(PROC_REF(life_tick), after = list(LIFE_INPUT, "life_type_pre"), key = "life_trait_radiation_glow"))
