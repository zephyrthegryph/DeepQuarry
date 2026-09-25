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

	var/mob_overlay_state = null		// Icon_state for an overlay to apply to a (human) mob while this exists.  This is actually implemented.
	var/client_color = null				// If set, the client will have the world be shown in this color, from their perspective.
	var/wire_colors_replace = null		// If set, the client will have wires replaced by the given replacement list. For colorblindness.
	var/list/filter_parameters = null	// If set, will add a filter to the holder with the parameters in this var. Must be a list.
	var/filter_priority = 1				// Used to make filters be applied in a specific order, if that is important.
	var/filter_instance = null			// Instance of a filter created with the `filter_parameters` list. This exists to make `animate()` calls easier. Don't set manually.

	// Every numeric effect (slowdown, accuracy, incoming injury, metabolism,
	// armour, ...) is a body factor: declare them in `factors` (see
	// code/modules/body/factors.dm), e.g. factors = alist(BF_SLOWDOWN = 1).
	// Percentages are multipliers (+25% damage is 1.25).

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
	LAZYREMOVE(holder.modifiers, src)
	// A persistent trait leaves the character only when deliberately removed
	// from a living body, not when the body dies or is deleted.
	if((flags & MODIFIER_GENETIC) && !QDELETED(holder) && holder.stat != DEAD)
		holder.record_genetic_modifier(type, FALSE)
	if(factors)
		holder.invalidate_factors()
	if(mob_overlay_state) // We do this after removing ourselves from the list so that the overlay won't remain.
		holder.update_modifier_visuals()
	if(changes_icon_scale()) // Correct the scaling.
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
	var/list/modifiers // A list of modifier datums, which can adjust certain mob numbers. Lazy: LAZYADD/LAZYREMOVE/LAZYLEN.

// Called by Life().
/datum/om/stage/life/modifiers
	order = LIFE_PHASE_INPUT + 50
	name = "modifiers"
	run_if = LIFE_RUN_IF_PLACED
	life_sets = LIFE_SET_LIVING | LIFE_SET_ROBOT
	woken_by = "add_modifier()"

/// Continuous while the mob has any modifier (they expire and tick); asleep otherwise.
/datum/om/stage/life/modifiers/idle(mob/living/self)
	return !length(self.modifiers)

/// Modifier expiry and ticks. Runs even in nullspace.
/datum/om/stage/life/modifiers/perform(mob/living/self, datum/om/frame/life/ctx)
	if(!LAZYLEN(self.modifiers)) // No work to do.
		return
	// Get rid of anything we shouldn't have.
	for(var/datum/modifier/M in self.modifiers)
		M.check_if_valid()
	// Remaining modifiers will now receive a tick().  This is in a second loop for safety in order to not tick() an expired modifier.
	for(var/datum/modifier/M in self.modifiers)
		M.tick()

// Call this to add a modifier to a mob. First argument is the modifier type you want, second is how long it should last, in ticks.
// Third argument is the 'source' of the modifier, if it's from someone else.  If null, it will default to the mob being applied to.
// The SECONDS/MINUTES macro is very helpful for this.  E.g. M.add_modifier(/datum/modifier/example, 5 MINUTES)
// The fourth argument is a boolean to suppress failure messages, set it to true if the modifier is repeatedly applied (as chem-based modifiers are) to prevent chat-spam
/mob/living/proc/add_modifier(modifier_type, expire_at = null, mob/living/origin = null, suppress_failure = FALSE)
	// First, check if the mob already has this modifier.
	for(var/datum/modifier/M in modifiers)
		if(ispath(modifier_type, M.type))
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
	LAZYADD(modifiers, mod)
	om_changed(src, CHANGE_MOB_CONDITIONS)
	if(mod.flags & MODIFIER_GENETIC)
		record_genetic_modifier(mod.type, TRUE)
	if(mod.factors)
		invalidate_factors()
	mod.on_applied()
	if(mod.mob_overlay_state)
		update_modifier_visuals()
	if(mod.changes_icon_scale())
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

/// Does this modifier scale the holder's sprite?
/datum/modifier/proc/changes_icon_scale()
	return factors && (!isnull(factors[BF_ICON_SCALE_X]) || !isnull(factors[BF_ICON_SCALE_Y]))

// This displays the actual 'numbers' that a modifier is doing.  Should only be shown in OOC contexts.
/datum/modifier/proc/describe_modifier_effects()
	return jointext(body_factor_describe(factors), "<br>")


// === merged from modifiers_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/modifier
	var/effect_color					// Allows for coloring of modifiers.
	var/coloration_applied = 0			// Tells the game is coloration has been applied already or not.
	var/icon_override = 0				// Tells the game if it should use modifer_effects_vr.dmi or not.

/datum/modifier/underwater_stealth
	name = "underwater stealth"
	desc = "You are currently underwater, rendering it more difficult to see you and enabling you to move quicker, thanks to your aquatic nature."

	on_created_text = span_warning("You sink under the water.")
	on_expired_text = span_notice("You come out from the water.")

	stacks = MODIFIER_STACK_FORBID

	// A bit faster when actually submerged fully in water, as you're not waddling through it. // nerf this a lil
	// You are, however, underwater. Getting shocked will hurt.
	// You are swinging a sword under water...Good luck.
	// You're underwater. Good luck shooting a gun. (Makes shots as if you were 3.33 tiles further.)
	// You're underwater and a bit harder to hit.
	factors = alist(BF_SLOWDOWN = -1.0, BF_ACCURACY = -50, BF_EVASION = 30, BF_MELEE_DAMAGE = 0.75, BF_SIEMENS = 1.5)


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
		if(water_floor.depth > 1)
			holder.alpha = 50
		else
			holder.alpha = 65
	else
		expire(silent = FALSE)

// Personal shield projections. Their numeric effects (siemens, stun
// resistance, evasion...) are ordinary body factors; the one thing that is
// not a simple multiplier is the charge-dependent damage resistance, which
// also drains the generator's cell for what it absorbs. That runs as stage 2
// of injure()'s mitigation (COMSIG_LIVING_SHIELD_INJURY) while the shield is up.
/datum/modifier/shield_projection
	name = "Shield Projection"
	desc = "You are currently protected by a shield, rendering nigh impossible to hit you through conventional means."

	on_created_text = span_notice("Your shield generator buzzes on.")
	on_expired_text = span_warning("Your shield generator buzzes off.")
	stacks = MODIFIER_STACK_FORBID //No stacking shields. If you put one one your belt and backpack it won't work.

	icon_override = 1
	mob_overlay_state = "deflect"
	// Stun weapons drain 100% charge per point of damage. They're good at blocking lasers and bullets but not good at blocking stun beams!
	factors = alist(BF_SIEMENS = 2)

	/// Cell charge used per point of injury the shield absorbs. Set from the generator.
	var/damage_cost = 50
	/// The generator's cell.
	var/obj/item/cell/energy_source
	/// The shield generator you're wearing.
	var/obj/item/personal_shield_generator/shield_generator
	/// Injury multipliers at FULL charge: INJURY_CATEGORY_* -> multiplier
	/// (SHIELD_RESIST_ALL for every injury). 0 = immune, 1 = full injury.
	var/alist/resist_full
	/// Injury multipliers at EMPTY charge; the shield slides between the two.
	/// Missing categories are 1 (no protection) when empty.
	var/alist/resist_empty

/// Key in resist_full / resist_empty that applies to every injury category.
#define SHIELD_RESIST_ALL 0

/datum/modifier/shield_projection/on_applied()
	RegisterSignal(holder, COMSIG_LIVING_SHIELD_INJURY, PROC_REF(on_holder_injure))

/datum/modifier/shield_projection/on_expire()
	UnregisterSignal(holder, COMSIG_LIVING_SHIELD_INJURY)

/datum/modifier/shield_projection/Destroy(force)
	shield_generator = null
	energy_source = null
	return ..()

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

/// Injury multiplier for `category` at the cell's current charge, or null
/// when the shield doesn't touch that category.
/datum/modifier/shield_projection/proc/resistance(category)
	var/efficiency = energy_source?.maxcharge ? energy_source.charge / energy_source.maxcharge : 0
	. = null
	for(var/key in list(SHIELD_RESIST_ALL, category))
		if(isnull(resist_full?[key]))
			continue
		var/empty = isnull(resist_empty?[key]) ? 1 : resist_empty[key]
		var/mult = empty + (resist_full[key] - empty) * efficiency
		. = isnull(.) ? mult : . * mult

/datum/modifier/shield_projection/proc/on_holder_injure(mob/living/source, kind, list/amount_ref, zone, atom/injury_source, flags)
	SIGNAL_HANDLER
	var/mult = resistance(injury_category(kind))
	if(isnull(mult))
		return NONE
	energy_source?.use(damage_cost * amount_ref[1])
	amount_ref[1] *= mult
	return NONE

//Shield variants.

//Simple. Goes from 100% resistance to 0% resistance depending on charge. This is mostly an example of a shield variant.
/datum/modifier/shield_projection/bruteburn
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0, INJURY_CATEGORY_THERMAL = 0)

/datum/modifier/shield_projection/bruteburn/weak
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.5, INJURY_CATEGORY_THERMAL = 0.5)

//SECURITY VARIANTS
/datum/modifier/shield_projection/security // Security backpack. 50% resistance at full charge. 10% resistance for the last shot taken.
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.5, INJURY_CATEGORY_THERMAL = 0.5, INJURY_CATEGORY_PAIN = 0.5)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.9, INJURY_CATEGORY_THERMAL = 0.9, INJURY_CATEGORY_PAIN = 0.9)
	factors = alist(BF_DISABLE_DURATION = 0.75, BF_SIEMENS = 2)

/datum/modifier/shield_projection/security/weak // Security belt.
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.75, INJURY_CATEGORY_THERMAL = 0.75, INJURY_CATEGORY_PAIN = 0.75)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.95, INJURY_CATEGORY_THERMAL = 0.95, INJURY_CATEGORY_PAIN = 0.95)

/datum/modifier/shield_projection/security/strong // Dunno. Upgraded variant of security backpack?
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.25, INJURY_CATEGORY_THERMAL = 0.25, INJURY_CATEGORY_PAIN = 0.25)
	// Not as weak as normal, but still weak.
	factors = alist(BF_DISABLE_DURATION = 0.5, BF_SIEMENS = 1.5)

//MINING VARIANTS
/datum/modifier/shield_projection/mining //Base mining belt. 30% resistance that fades to 15% resistance
	// No mobs should be shooting you with halloss. If this happens, it means you're using it wrong!!!
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.7, INJURY_CATEGORY_THERMAL = 0.7, INJURY_CATEGORY_PAIN = 1.5)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.85, INJURY_CATEGORY_THERMAL = 0.85, INJURY_CATEGORY_PAIN = 1.5)
	// Miners often come into contact with things that can stun them.
	factors = alist(BF_DISABLE_DURATION = 0.75, BF_SIEMENS = 2)

/datum/modifier/shield_projection/mining/strong // Mining belt, but upgraded. Even weaker to halloss!
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.55, INJURY_CATEGORY_THERMAL = 0.55, INJURY_CATEGORY_PAIN = 2)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.75, INJURY_CATEGORY_THERMAL = 0.75, INJURY_CATEGORY_PAIN = 2)
	factors = alist(BF_DISABLE_DURATION = 0.5, BF_SIEMENS = 2)

//MISC VARIANTS

/datum/modifier/shield_projection/biohazard //The odd-ball damage types. Provides near-complete immunity while it's up.
	resist_full = alist(INJURY_CATEGORY_TOXIC = 0, INJURY_CATEGORY_GENETIC = 0)
	resist_empty = alist(INJURY_CATEGORY_TOXIC = 0.25, INJURY_CATEGORY_GENETIC = 0.25)

/datum/modifier/shield_projection/admin // Adminbus.
	on_created_text = span_notice("Your shield generator activates and you feel the power of the tesla buzzing around you.")
	on_expired_text = span_warning("Your shield generator deactivates, leaving you feeling weak and vulnerable.")
	factors = alist(BF_DISABLE_DURATION = 0, BF_SIEMENS = 0)
	resist_full = alist(SHIELD_RESIST_ALL = 0)
	resist_empty = alist(SHIELD_RESIST_ALL = 0)

/datum/modifier/shield_projection/broken //For broken variants. Good if possible randomization is included for packs spawned on PoIs.
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 2, INJURY_CATEGORY_THERMAL = 2)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 2, INJURY_CATEGORY_THERMAL = 2)

/datum/modifier/shield_projection/inverted //Becomes stronger the weaker the cell is. Means the last shot taken will be the weakest. Example just to show it can be done.
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 1, INJURY_CATEGORY_THERMAL = 1)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0, INJURY_CATEGORY_THERMAL = 0)

/datum/modifier/shield_projection/parry //Intended for 'parry' shields, which only last for a single second before running out of charge
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0, INJURY_CATEGORY_THERMAL = 0, INJURY_CATEGORY_PAIN = 0)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0, INJURY_CATEGORY_THERMAL = 0, INJURY_CATEGORY_PAIN = 0)

/datum/modifier/shield_projection/melee_focus
	//You are expected to be taking a LOT more hits while this is up.
	damage_cost = 5
	// 50% resistance at a full charge, 35% when about to empty. 500% damage
	// taken from halloss: anti PVP, this is meant to be a PvE weapon.
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.5, INJURY_CATEGORY_THERMAL = 0.5, INJURY_CATEGORY_PAIN = 5)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.65, INJURY_CATEGORY_THERMAL = 0.65, INJURY_CATEGORY_PAIN = 5)
	// Stuns are half as long; much harder to shoot; somewhat faster; can't
	// shoot; attacks faster and harder; bleeds slightly slower.
	factors = alist(BF_BLEEDING = 0.75, BF_SLOWDOWN = -0.5, BF_ACCURACY = -1000, BF_EVASION = 35, BF_ATTACK_SPEED = 0.8, BF_MELEE_DAMAGE = 1.25, BF_DISABLE_DURATION = 0.5, BF_SIEMENS = 2)

/// Exploration boss loot: a generator belt that pulls ore towards you.
/datum/modifier/shield_projection/magnet
	name = "Magnet Pull"
	mob_overlay_state = null
	factors = null

/datum/modifier/shield_projection/magnet/tick()
	..()
	for(var/obj/item/ore/O in orange(4, holder))
		step_towards(O, get_turf(holder))

/datum/modifier/shield_projection/magnet/defense
	resist_full = alist(INJURY_CATEGORY_PHYSICAL = 0.3, INJURY_CATEGORY_THERMAL = 0.3)
	resist_empty = alist(INJURY_CATEGORY_PHYSICAL = 0.8, INJURY_CATEGORY_THERMAL = 0.8)

#undef SHIELD_RESIST_ALL
