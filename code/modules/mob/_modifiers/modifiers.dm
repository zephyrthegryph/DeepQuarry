// This is a datum that tells the mob that something is affecting them.
// The advantage of using this datum verses just setting a variable on the mob directly, is that there is no risk of two different procs overwriting
// each other, or other weirdness.  An excellent example is adjusting max health.

/datum/modifier
	var/name = null						// Mostly used to organize, might show up on the UI in the Future(tm)
	var/desc = null						// Ditto.
	var/icon_state = null				// See above.
	var/mob/living/holder = null		// The mob that this datum is affecting.
	var/datum/weakref/origin = null		// A weak reference to whatever caused the modifier to appear.  THIS NEEDS TO BE A MOB/LIVING.  It's a weakref to not interfere with qdel().
	var/expire_at = null				// world.time when holder's Life() will remove the datum.  If null, it lasts forever or until it gets deleted by something else.
	var/on_created_text = null			// Text to show to holder upon being created.
	var/on_expired_text = null			// Text to show to holder when it expires.
	var/hidden = FALSE					// If true, it will not show up on the HUD in the Future(tm)
	var/stacks = MODIFIER_STACK_FORBID	// If true, attempts to add a second instance of this type will refresh expire_at instead.
	var/flags = NONE						// Flags for the modifier, see mobs.dm defines for more details.

	var/light_color = null				// If set, the mob possessing the modifier will glow in this color.  Not implemented yet.
	var/light_range = null				// How far the light for the above var goes. Not implemented yet.
	var/light_intensity = null			// Ditto. Not implemented yet.
	var/mob_overlay_state = null		// Icon_state for an overlay to apply to a (human) mob while this exists.  This is actually implemented.
	var/client_color = null				// If set, the client will have the world be shown in this color, from their perspective.
	var/wire_colors_replace = null		// If set, the client will have wires replaced by the given replacement list. For colorblindness.
	var/list/filter_parameters = null	// If set, will add a filter to the holder with the parameters in this var. Must be a list.
	var/filter_priority = 1				// Used to make filters be applied in a specific order, if that is important.
	var/filter_instance = null			// Instance of a filter created with the `filter_parameters` list. This exists to make `animate()` calls easier. Don't set manually.

	// Now for all the different effects.
	// Percentage modifiers are expressed as a multipler. (e.g. +25% damage should be written as 1.25)
	var/max_health_flat					// Adjusts max health by a flat (e.g. +20) amount.  Note this is added to base health.
	var/max_health_percent				// Adjusts max health by a percentage (e.g. -30%).
	var/disable_duration_percent		// Adjusts duration of 'disables' (stun, weaken, paralyze, confusion, sleep, halloss, etc)  Setting to 0 will grant immunity.
	var/incoming_damage_percent			// Adjusts all incoming damage.
	var/incoming_brute_damage_percent	// Only affects bruteloss.
	var/incoming_fire_damage_percent	// Only affects fireloss.
	var/incoming_tox_damage_percent		// Only affects toxloss.
	var/incoming_oxy_damage_percent		// Only affects oxyloss.
	var/incoming_clone_damage_percent	// Only affects cloneloss.
	var/incoming_hal_damage_percent		// Only affects halloss.
	var/incoming_healing_percent		// Adjusts amount of healing received.
	var/outgoing_melee_damage_percent	// Adjusts melee damage inflicted by holder by a percentage.  Affects attacks by melee weapons and hand-to-hand.
	var/slowdown						// Negative numbers speed up, positive numbers slow down movement.
	var/haste							// If set to 1, the mob will be 'hasted', which makes it ignore slowdown and go really fast.
	var/evasion							// Positive numbers reduce the odds of being hit. Negative numbers increase the odds.
	var/bleeding_rate_percent			// Adjusts amount of blood lost when bleeding.
	var/accuracy						// Positive numbers makes hitting things with guns easier, negatives make it harder.
	var/accuracy_dispersion				// Positive numbers make gun firing cover a wider tile range, and therefore more inaccurate.  Negatives help negate dispersion penalties.
	var/metabolism_percent				// Adjusts the mob's metabolic rate, which affects reagent processing.  Won't affect mobs without reagent processing.
	var/icon_scale_x_percent			// Makes the holder's icon get scaled wider or thinner.
	var/icon_scale_y_percent			// Makes the holder's icon get scaled taller or shorter.
	var/attack_speed_percent			// Makes the holder's 'attack speed' (click delay) shorter or longer.
	var/pain_immunity					// Makes the holder not care about pain while this is on. Only really useful to human mobs.
	var/pulse_modifier					// Modifier for pulse, will be rounded on application, then added to the normal 'pulse' multiplier which ranges between 0 and 5 normally. Only applied if they're living.
	var/pulse_set_level					// Positive number. If this is non-null, it will hard-set the pulse level to this. Pulse ranges from 0 to 5 normally.
	var/emp_modifier					// Added to the EMP strength, which is an inverse scale from 1 to 4, with 1 being the strongest EMP. 5 is a nullification.
	var/explosion_modifier				// Added to the bomb strength, which is an inverse scale from 1 to 3, with 1 being gibstrength. 4 is a nullification.

	// Note that these are combined with the mob's real armor values additatively. You can also omit specific armor types.
	var/list/armor_percent = null		// List of armor values to add to the holder when doing armor calculations. This is for percentage based armor. E.g. 50 = half damage.
	// Unlike armor, this is multiplicative. Two 50% protection modifiers will be combined into 75% protection (assuming no base protection on the mob).
	var/heat_protection = null			// Modifies how 'heat' protection is calculated, like wearing a firesuit. 1 = full protection.
	var/cold_protection = null			// Ditto, but for cold, like wearing a winter coat.
	var/siemens_coefficient = null		// Similar to above two vars but 0 = full protection, to be consistant with siemens numbers everywhere else.

	var/vision_flags					// Vision flags to add to the mob. SEE_MOB, SEE_OBJ, etc.

/datum/modifier/New(new_holder, new_origin)
	holder = new_holder
	if(new_origin)
		origin = WEAKREF(new_origin)
	else // We assume the holder caused the modifier if not told otherwise.
		origin = WEAKREF(holder)
	..()

/datum/modifier/Destroy(force)
	. = ..()
	origin = null

// Checks if the modifier should be allowed to be applied to the mob before attaching it.
// Override for special criteria, e.g. forbidding robots from receiving it.
/datum/modifier/proc/can_apply(mob/living/L, suppress_output = FALSE)
	return TRUE

// Checks to see if this datum should continue existing.
/datum/modifier/proc/check_if_valid()
	if(expire_at && expire_at < world.time) // Is our time up?
		src.expire()

/datum/modifier/proc/expire(silent = FALSE)
	if(on_expired_text && !silent)
		to_chat(holder, on_expired_text)
	on_expire()
	holder.modifiers.Remove(src)
	if(mob_overlay_state) // We do this after removing ourselves from the list so that the overlay won't remain.
		holder.update_modifier_visuals()
	if(icon_scale_x_percent || icon_scale_y_percent) // Correct the scaling.
		holder.update_transform()
	if(client_color)
		holder.update_client_color()
	if(LAZYLEN(filter_parameters))
		holder.remove_filter(REF(src))
	qdel(src)

// Override this for special effects when it gets added to the mob.
/datum/modifier/proc/on_applied()
	return

// Override this for special effects when it gets removed.
/datum/modifier/proc/on_expire()
	return

// Called every Life() tick.  Override for special behaviour.
/datum/modifier/proc/tick()
	return

/mob/living
	var/list/modifiers = list() // A list of modifier datums, which can adjust certain mob numbers.

// Called by Life().
/mob/living/proc/handle_modifiers()
	if(!modifiers.len) // No work to do.
		return
	// Get rid of anything we shouldn't have.
	for(var/datum/modifier/M in modifiers)
		M.check_if_valid()
	// Remaining modifiers will now receive a tick().  This is in a second loop for safety in order to not tick() an expired modifier.
	for(var/datum/modifier/M in modifiers)
		M.tick()

// Call this to add a modifier to a mob. First argument is the modifier type you want, second is how long it should last, in ticks.
// Third argument is the 'source' of the modifier, if it's from someone else.  If null, it will default to the mob being applied to.
// The SECONDS/MINUTES macro is very helpful for this.  E.g. M.add_modifier(/datum/modifier/example, 5 MINUTES)
// The fourth argument is a boolean to suppress failure messages, set it to true if the modifier is repeatedly applied (as chem-based modifiers are) to prevent chat-spam
/mob/living/proc/add_modifier(modifier_type, expire_at = null, mob/living/origin = null, suppress_failure = FALSE)
	// First, check if the mob already has this modifier.
	for(var/datum/modifier/M in modifiers)
		if(ispath(modifier_type, M))
			switch(M.stacks)
				if(MODIFIER_STACK_FORBID)
					return // Stop here.
				if(MODIFIER_STACK_ALLOWED)
					break // No point checking anymore.
				if(MODIFIER_STACK_EXTEND)
					// Not allow to add a second instance, but we can try to prolong the first instance.
					if(expire_at && world.time + expire_at > M.expire_at)
						M.expire_at = world.time + expire_at
					return

	// If we're at this point, the mob doesn't already have it, or it does but stacking is allowed.
	var/datum/modifier/mod = new modifier_type(src, origin)
	if(!mod.can_apply(src, suppress_failure))
		qdel(mod)
		return
	if(expire_at)
		mod.expire_at = world.time + expire_at
	if(mod.on_created_text)
		to_chat(src, mod.on_created_text)
	modifiers.Add(mod)
	mod.on_applied()
	if(mod.mob_overlay_state)
		update_modifier_visuals()
	if(mod.icon_scale_x_percent || mod.icon_scale_y_percent)
		update_transform()
	if(mod.client_color)
		update_client_color()
	if(LAZYLEN(mod.filter_parameters))
		add_filter(REF(mod), mod.filter_priority, mod.filter_parameters)
		mod.filter_instance = get_filter(REF(mod))

	return mod

// Removes a specific instance of modifier
/mob/living/proc/remove_specific_modifier(datum/modifier/M, silent = FALSE)
	M.expire(silent)

// Removes one modifier of a type
/mob/living/proc/remove_a_modifier_of_type(modifier_type, silent = FALSE)
	for(var/datum/modifier/M in modifiers)
		if(ispath(M.type, modifier_type))
			M.expire(silent)
			break

// Removes all modifiers of a type
/mob/living/proc/remove_modifiers_of_type(modifier_type, silent = FALSE)
	for(var/datum/modifier/M in modifiers)
		if(ispath(M.type, modifier_type))
			M.expire(silent)

// Removes all modifiers, useful if the mob's being deleted
/mob/living/proc/remove_all_modifiers(silent = FALSE)
	for(var/datum/modifier/M in modifiers)
		M.expire(silent)

// Checks if the mob has a modifier type.
/mob/living/proc/has_modifier_of_type(modifier_type)
	return get_modifier_of_type(modifier_type) ? TRUE : FALSE

// Gets the first instance of a specific modifier type or subtype.
/mob/living/proc/get_modifier_of_type(modifier_type)
	for(var/datum/modifier/M in modifiers)
		if(istype(M, modifier_type))
			return M
	return null

// This displays the actual 'numbers' that a modifier is doing.  Should only be shown in OOC contexts.
// When adding new effects, be sure to update this as well.
/datum/modifier/proc/describe_modifier_effects()
	var/list/effects = list()
	if(!isnull(max_health_flat))
		effects += "You [max_health_flat > 0 ? "gain" : "lose"] [abs(max_health_flat)] maximum health."
	if(!isnull(max_health_percent))
		effects += "You [max_health_percent > 1.0 ? "gain" : "lose"] [multipler_to_percentage(max_health_percent, TRUE)] maximum health."

	if(!isnull(disable_duration_percent))
		effects += "Disabling effects on you last [multipler_to_percentage(disable_duration_percent, TRUE)] [disable_duration_percent > 1.0 ? "longer" : "shorter"]"

	if(!isnull(incoming_damage_percent))
		effects += "You take [multipler_to_percentage(incoming_damage_percent, TRUE)] [incoming_damage_percent > 1.0 ? "more" : "less"] damage."
	if(!isnull(incoming_brute_damage_percent))
		effects += "You take [multipler_to_percentage(incoming_brute_damage_percent, TRUE)] [incoming_brute_damage_percent > 1.0 ? "more" : "less"] brute damage."
	if(!isnull(incoming_fire_damage_percent))
		effects += "You take [multipler_to_percentage(incoming_fire_damage_percent, TRUE)] [incoming_fire_damage_percent > 1.0 ? "more" : "less"] fire damage."
	if(!isnull(incoming_tox_damage_percent))
		effects += "You take [multipler_to_percentage(incoming_tox_damage_percent, TRUE)] [incoming_tox_damage_percent > 1.0 ? "more" : "less"] toxin damage."
	if(!isnull(incoming_oxy_damage_percent))
		effects += "You take [multipler_to_percentage(incoming_oxy_damage_percent, TRUE)] [incoming_oxy_damage_percent > 1.0 ? "more" : "less"] oxy damage."
	if(!isnull(incoming_clone_damage_percent))
		effects += "You take [multipler_to_percentage(incoming_clone_damage_percent, TRUE)] [incoming_clone_damage_percent > 1.0 ? "more" : "less"] clone damage."
	if(!isnull(incoming_hal_damage_percent))
		effects += "You take [multipler_to_percentage(incoming_hal_damage_percent, TRUE)] [incoming_hal_damage_percent > 1.0 ? "more" : "less"] agony damage."

	if(!isnull(incoming_healing_percent))
		effects += "Healing applied to you is [multipler_to_percentage(incoming_healing_percent, TRUE)] [incoming_healing_percent > 1.0 ? "stronger" : "weaker"]."

	if(!isnull(outgoing_melee_damage_percent))
		effects += "Damage you do with melee weapons and unarmed combat is [multipler_to_percentage(outgoing_melee_damage_percent, TRUE)] \
		[outgoing_melee_damage_percent > 1.0 ? "higher" : "lower"]."

	if(!isnull(slowdown))
		effects += "[slowdown > 0 ? "lose" : "gain"] [slowdown] slowdown."

	if(!isnull(haste))
		effects += "You move at maximum speed, and cannot be slowed by any means."

	if(!isnull(evasion))
		effects += "You are [abs(evasion)]% [evasion > 0 ? "harder" : "easier"] to hit with weapons."

	if(!isnull(bleeding_rate_percent))
		effects += "You bleed [multipler_to_percentage(bleeding_rate_percent, TRUE)] [bleeding_rate_percent > 1.0 ? "faster" : "slower"]."

	if(!isnull(accuracy))
		effects += "It is [abs(accuracy)]% [accuracy > 0 ? "easier" : "harder"] for you to hit someone with a ranged weapon."

	if(!isnull(accuracy_dispersion))
		effects += "Projectiles you fire are [accuracy_dispersion > 0 ? "more" : "less"] likely to stray from your intended target."

	if(!isnull(metabolism_percent))
		effects += "Your metabolism is [metabolism_percent > 1.0 ? "faster" : "slower"], \
		causing reagents in your body to process, and hunger to occur [multipler_to_percentage(metabolism_percent, TRUE)] [metabolism_percent > 1.0 ? "faster" : "slower"]."

	if(!isnull(icon_scale_x_percent))
		effects += "Your appearance is [multipler_to_percentage(icon_scale_x_percent, TRUE)] [icon_scale_x_percent > 1 ? "wider" : "thinner"]."

	if(!isnull(icon_scale_y_percent))
		effects += "Your appearance is [multipler_to_percentage(icon_scale_y_percent, TRUE)] [icon_scale_y_percent > 1 ? "taller" : "shorter"]."

	if(!isnull(attack_speed_percent))
		effects += "The delay between attacking is [multipler_to_percentage(attack_speed_percent, TRUE)] [disable_duration_percent > 1.0 ? "longer" : "shorter"]."

	return jointext(effects, "<br>")



// Helper to format multiplers (e.g. 1.4) to percentages (like '40%')
/proc/multipler_to_percentage(multi, abs = FALSE)
	if(abs)
		return "[abs( ((multi - 1) * 100) )]%"
	return "[((multi - 1) * 100)]%"


// === merged from modifiers_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/modifier
	var/effect_color					// Allows for coloring of modifiers.
	var/coloration_applied = 0			// Tells the game is coloration has been applied already or not.
	var/icon_override = 0				// Tells the game if it should use modifer_effects_vr.dmi or not.
	// ENERGY CODE. Variables to allow for energy based modifiers.
	var/energy_based					// Sees if the modifier is based on something electronic based.
	var/energy_cost						// How much the modifier uses per action/special effect blocked. For base values.
	var/damage_cost						// How much energy is used when numbers are involed. For values, such as taking damage. Ex: (Damage*damage_cost)
	var/obj/item/cell/energy_source = null	// The source of the above.

	// RESISTANCES CODE. Variable to enable external damage resistance modifiers. This is not unlike armor.
	// 0 = immune || < 0 = heals || 1 = full damage || >1 = increased damage.
	// It should never be below zero as it is not intended to do such, but you are free to experiment!
	// Ex: Max_brute_resistance = 0. Min_brute resistance = 1. When started, provides 100% resistance to brute. When cell is dying, goes down to 0% resistance.
	// Max is the MAXIMUM % multiplier that will be taken at a MAX charge. Min is the MINIMUM % multiplier that will be taken at a MINIMUM charge.
	// Think of it like this: Minimum = what happens at minimum charge. Max = what happens at maximum charge.
	// Why do I mention this so much? Because even /I/ got confused, and I wrote this thing!
	var/min_damage_resistance
	var/max_damage_resistance
	var/effective_damage_resistance

	var/min_brute_resistance
	var/max_brute_resistance
	var/effective_brute_resistance

	var/min_fire_resistance
	var/max_fire_resistance
	var/effective_fire_resistance

	var/min_tox_resistance
	var/max_tox_resistance
	var/effective_tox_resistance

	var/min_oxy_resistance
	var/max_oxy_resistance
	var/effective_oxy_resistance

	var/min_clone_resistance
	var/max_clone_resistance
	var/effective_clone_resistance

	var/min_hal_resistance
	var/max_hal_resistance
	var/effective_hal_resistance
	// Resistances end



/datum/modifier/underwater_stealth
	name = "underwater stealth"
	desc = "You are currently underwater, rendering it more difficult to see you and enabling you to move quicker, thanks to your aquatic nature."

	on_created_text = span_warning("You sink under the water.")
	on_expired_text = span_notice("You come out from the water.")

	stacks = MODIFIER_STACK_FORBID

	slowdown = -1.0							//A bit faster when actually submerged fully in water, as you're not waddling through it. //ChompEDIT - nerf this a lil
	siemens_coefficient = 1.5 				//You are, however, underwater. Getting shocked will hurt.

	outgoing_melee_damage_percent = 0.75 	//You are swinging a sword under water...Good luck.
	accuracy = -50							//You're underwater. Good luck shooting a gun. (Makes shots as if you were 3.33 tiles further.)
	evasion = 30							//You're underwater and a bit harder to hit.

/datum/modifier/underwater_stealth/on_applied()
	holder.alpha = 50
	return

/datum/modifier/underwater_stealth/on_expire()
	holder.alpha = 255
	return

/datum/modifier/underwater_stealth/tick()
	if(holder.stat == DEAD)
		expire(silent = TRUE) //If you're dead you float to the top.
	if(istype(holder.loc, /turf/simulated/floor/water))
		var/turf/simulated/floor/water/water_floor = holder.loc
		if(water_floor.depth < 1) //You're not in deep enough water anymore.
			expire(silent = FALSE)
		if(water_floor.depth > 1) //CHOMPAdd Start
			holder.alpha = 50
		else
			holder.alpha = 65 //CHOMPAdd End
	else
		expire(silent = FALSE)

/datum/modifier/shield_projection
	name = "Shield Projection"
	desc = "You are currently protected by a shield, rendering nigh impossible to hit you through conventional means."

	on_created_text = span_notice("Your shield generator buzzes on.")
	on_expired_text = span_warning("Your shield generator buzzes off.")
	stacks = MODIFIER_STACK_FORBID //No stacking shields. If you put one one your belt and backpack it won't work.

	icon_override = 1
	mob_overlay_state = "deflect"
	siemens_coefficient = 2 //Stun weapons drain 100% charge per point of damage. They're good at blocking lasers and bullets but not good at blocking stun beams!
	energy_based = 1
	energy_cost = 99999 //This is changed to the shield_generator's energy_cost.
	damage_cost = 50 //This is how much battery is used per damage unit absorbed. Higher damage means higher charge use per damage absorbed. Changed below!

	//Not actually in use until effective resistances are set. Just here so it doesn't have to be placed down for all the variants. Less lines.
	max_damage_resistance = 1
	max_brute_resistance = 1
	max_fire_resistance = 1
	max_tox_resistance = 1
	max_oxy_resistance = 1
	max_clone_resistance = 1
	max_hal_resistance = 1
	min_damage_resistance = 1
	min_brute_resistance = 1
	min_fire_resistance = 1
	min_tox_resistance = 1
	min_oxy_resistance = 1
	min_clone_resistance = 1
	min_hal_resistance = 1

/* 	// These are not set, but left here as an example. All three (min,max,effective) must be set or BAD THINGS will happen.
	min_brute_resistance = 1 // Min = WHAT HAPPENS AT MINIMUM CHARGE
	max_brute_resistance = 0 // MAX = WHAT HAPPENS AT MAXIMUM CHARGE
	effective_brute_resistance = 1 //Just tells the game that it has vars. Done to use less checks.

	min_fire_resistance = 1
	max_fire_resistance = 0
	effective_fire_resistance = 1
	disable_duration_percent = 1 //THIS CAN ALSO BE USED! Don't be too afraid to use this one, but use it sparingly!
*/
	var/obj/item/personal_shield_generator/shield_generator //This is the shield generator you're wearing!


/datum/modifier/shield_projection/on_applied()
	return

/datum/modifier/shield_projection/on_expire() //Don't need to modify this!
	return

/datum/modifier/shield_projection/check_if_valid() //Let's check to make sure you got the stuff and set the vars. Don't need to modify this for any subtypes!
	if(ishuman(holder)) //Only humans can use this! Other things later down the line might use the same stuff this does, but the shield generator is human only!
		var/mob/living/carbon/human/H = holder
		if(istype(H.get_equipped_item(slot_back), /obj/item/personal_shield_generator))
			shield_generator = H.get_equipped_item(slot_back) //Sets the var on the modifier that the shield gen is their back shield gen.
		else if(istype(H.get_equipped_item(slot_belt), /obj/item/personal_shield_generator))
			shield_generator = H.get_equipped_item(slot_belt) //No need for other checks. If they got hit by this, they just turned it on.
		else if(istype(H.get_equipped_item(slot_s_store), /obj/item/personal_shield_generator) ) //Rigsuits.
			shield_generator = H.get_equipped_item(slot_s_store)
		else
			expire(silent = TRUE)
		if(shield_generator) //Sanity.
			energy_source = shield_generator.bcell
			energy_cost = shield_generator.generator_hit_cost
			damage_cost = shield_generator.damage_cost
			effect_color = shield_generator.effect_color
		if(!coloration_applied) //Does a check if colors have been applied. If not, updates the color.
			H.update_modifier_visuals() //This can only happen on the next tick, unfortunately, not the same tick the modifier is applied. Thus, must be done here.
			coloration_applied = 1
	else
		expire(silent = TRUE)


/datum/modifier/shield_projection/tick() //When the shield generator runs out of charge, it'll remove this naturally.
	if(holder.stat == DEAD)
		expire(silent = TRUE) //If you're dead the generator stops protecting you but keeps running.
	if(!shield_generator || !shield_generator.slot_check()) //No shield to begin with/shield is not on them any longer.
		expire(silent = FALSE)

	var/shield_efficiency = (energy_source.charge/energy_source.maxcharge) //1 = complete resistance. 0 = no resistance. Must be adjusted for subtypes!
	if(!isnull(effective_damage_resistance))
		effective_damage_resistance = min_damage_resistance + (max_damage_resistance - min_damage_resistance) * shield_efficiency

	if(!isnull(effective_brute_resistance))
		effective_brute_resistance = min_brute_resistance + (max_brute_resistance - min_brute_resistance) * shield_efficiency

	if(!isnull(effective_fire_resistance))
		effective_fire_resistance = min_fire_resistance + (max_fire_resistance - min_fire_resistance) * shield_efficiency

	if(!isnull(effective_tox_resistance))
		effective_tox_resistance = min_tox_resistance + (max_tox_resistance - min_tox_resistance) * shield_efficiency

	if(!isnull(effective_oxy_resistance))
		effective_oxy_resistance = min_oxy_resistance + (max_oxy_resistance - min_oxy_resistance) * shield_efficiency

	if(!isnull(effective_clone_resistance))
		effective_clone_resistance = min_clone_resistance + (max_clone_resistance - min_clone_resistance) * shield_efficiency

	if(!isnull(effective_hal_resistance))
		effective_hal_resistance = min_hal_resistance + (max_hal_resistance - min_hal_resistance) * shield_efficiency

//Shield variants.

//Simple. Goes from 100% resistance to 0% resistance depending on charge. This is mostly an example of a shield variant.
/datum/modifier/shield_projection/bruteburn
	max_brute_resistance = 0
	effective_brute_resistance = 1

	max_fire_resistance = 0
	effective_fire_resistance = 1

/datum/modifier/shield_projection/bruteburn/weak
	max_brute_resistance = 0.5
	max_fire_resistance = 0.5

//SECURITY VARIANTS
/datum/modifier/shield_projection/security // Security backpack. 50% resistance at full charge. 10% resistance for the last shot taken.
	max_brute_resistance = 0.50
	min_brute_resistance = 0.9
	effective_brute_resistance = 1

	max_fire_resistance = 0.5
	min_fire_resistance = 0.9
	effective_fire_resistance = 1

	max_hal_resistance = 0.5
	min_hal_resistance = 0.9
	effective_hal_resistance = 1

	disable_duration_percent = 0.75

/datum/modifier/shield_projection/security/weak // Security belt.
	max_brute_resistance = 0.75
	min_brute_resistance = 0.95
	max_fire_resistance = 0.75
	min_fire_resistance = 0.95
	max_hal_resistance = 0.75
	min_hal_resistance = 0.95

/datum/modifier/shield_projection/security/strong // Dunno. Upgraded variant of security backpack?
	max_brute_resistance = 0.25
	max_fire_resistance = 0.25
	max_hal_resistance = 0.25
	siemens_coefficient = 1.5 //Not as weak as normal, but still weak.
	disable_duration_percent = 0.5


//MINING VARIANTS
/datum/modifier/shield_projection/mining //Base mining belt. 30% resistance that fades to 15% resistance
	max_brute_resistance = 0.70
	min_brute_resistance = 0.85
	effective_brute_resistance = 1

	max_fire_resistance = 0.70
	min_fire_resistance = 0.85
	effective_fire_resistance = 1

	max_hal_resistance = 1.5 // No mobs should be shooting you with halloss. If this happens, it means you're using it wrong!!!
	min_hal_resistance = 1.5
	effective_hal_resistance = 1

	disable_duration_percent = 0.75 //Miners often come into contact with things that can stun them.

/datum/modifier/shield_projection/mining/strong // Mining belt, but upgraded. Even weaker to halloss!
	max_brute_resistance = 0.55
	min_brute_resistance = 0.75
	max_fire_resistance = 0.55
	min_fire_resistance = 0.75
	disable_duration_percent = 0.5

	max_hal_resistance = 2
	min_hal_resistance = 2

//MISC VARIANTS

/datum/modifier/shield_projection/biohazard //The odd-ball damage types. Provides near-complete immunity while it's up.
	min_tox_resistance = 0.25
	max_tox_resistance = 0
	effective_tox_resistance = 1

	min_oxy_resistance = 0.25
	max_oxy_resistance = 0
	effective_oxy_resistance = 1

	min_clone_resistance = 0.25
	max_clone_resistance = 0
	effective_clone_resistance = 1

/datum/modifier/shield_projection/admin // Adminbus.
	on_created_text = span_notice("Your shield generator activates and you feel the power of the tesla buzzing around you.")
	on_expired_text = span_warning("Your shield generator deactivates, leaving you feeling weak and vulnerable.")
	siemens_coefficient = 0
	disable_duration_percent = 0
	min_damage_resistance = 0
	max_damage_resistance = 0
	effective_damage_resistance = 0
	min_brute_resistance = 0
	max_brute_resistance = 0
	effective_brute_resistance = 0
	min_fire_resistance = 0
	max_fire_resistance = 0
	effective_fire_resistance = 0
	min_tox_resistance = 0
	max_tox_resistance = 0
	effective_tox_resistance = 0
	min_oxy_resistance = 0
	max_oxy_resistance = 0
	effective_oxy_resistance = 0
	min_clone_resistance = 0
	max_clone_resistance = 0
	effective_clone_resistance = 0
	min_hal_resistance = 0
	max_hal_resistance = 0
	effective_hal_resistance = 0

/datum/modifier/shield_projection/broken //For broken variants. Good if possible randomization is included for packs spawned on PoIs.
	max_brute_resistance = 2
	min_brute_resistance = 2
	effective_brute_resistance = 1

	max_fire_resistance = 2
	min_fire_resistance = 2
	effective_fire_resistance = 1

/datum/modifier/shield_projection/inverted //Becomes stronger the weaker the cell is. Means the last shot taken will be the weakest. Example just to show it can be done.
	max_brute_resistance = 1
	min_brute_resistance = 0
	effective_brute_resistance = 1

	max_fire_resistance = 1
	min_fire_resistance = 0
	effective_fire_resistance = 1

/datum/modifier/shield_projection/parry //Intended for 'parry' shields, which only last for a single second before running out of charge
	max_brute_resistance = 0
	min_brute_resistance = 0
	effective_brute_resistance = 1

	max_fire_resistance = 0
	min_fire_resistance = 0
	effective_fire_resistance = 1

	max_hal_resistance = 0
	min_hal_resistance = 0
	effective_hal_resistance = 1

/datum/modifier/shield_projection/melee_focus

	//You are expected to be taking a LOT more hits while this is up.
	damage_cost = 5

	//.50% resistance at a full charge, 35% resistance at when we're about to empty.
	max_brute_resistance = 0.5
	min_brute_resistance = 0.65
	effective_brute_resistance = 1

	//.50% resistance at a full charge, 35% resistance at when we're about to empty.
	max_fire_resistance = 0.5
	min_fire_resistance = 0.65
	effective_fire_resistance = 1

	//500% damage taken from halloss. Anti PVP. This is meant to be a PvE weapon.
	//This also means that mobs that deal halloss will wreck users of this...Those are (extremely) rare as far as I know.
	min_hal_resistance = 5
	max_hal_resistance = 5
	effective_hal_resistance = 1

	//Stuns are HALF as long. Get stunned for 4 seconds? Only stunned for 2, now.
	disable_duration_percent = 0.5

	//You are QUITE harder to shoot.
	evasion = 35

	//You move SOMEWHAT faster.
	slowdown = -0.5

	//You can't shoot, though. This isn't actually used as this modifier is checked in gun.dm, but it's here anyways.
	accuracy = -1000

	//You attack SOMEWHAT faster
	attack_speed_percent = 0.8

	//You hit SOMEWHAT harder
	outgoing_melee_damage_percent = 1.25

	//You bleed SLIGHTLY slower, since you are taking more hits.
	bleeding_rate_percent = 0.75
