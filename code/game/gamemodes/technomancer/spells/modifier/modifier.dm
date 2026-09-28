/obj/item/spell/modifier
	name = "modifier template"
	desc = "Tell a coder if you can read this in-game."
	icon_state = "purify"
	cast_methods = CAST_MELEE
	var/modifier_type = null
	var/modifier_duration = null // Will last forever by default.  Final duration may differ due to 'spell power'
	var/spell_light_intensity = 2
	var/spell_light_range = 3

/obj/item/spell/modifier/Initialize(mapload)
	. = ..()
	set_light(spell_light_range, spell_light_intensity, l_color = light_color)

/obj/item/spell/modifier/on_melee_cast(atom/hit_atom, mob/user)
	if(isliving(hit_atom))
		return on_add_modifier(hit_atom)
	return FALSE

/obj/item/spell/modifier/on_ranged_cast(atom/hit_atom, mob/user)
	if(isliving(hit_atom))
		return on_add_modifier(hit_atom)
	return FALSE


/obj/item/spell/modifier/proc/on_add_modifier(mob/living/L)
	var/duration = modifier_duration
	if(duration)
		duration = round(duration * calculate_spell_power(1.0), 1)
	if(L.apply_body_effect(modifier_type, duration, owner_ref()) && ispath(modifier_type, /datum/body_effect/technomancer) && isnull(L.body_effect_state(modifier_type)))
		L.set_body_effect_state(modifier_type, calculate_spell_power(1))
	log_and_message_admins("has casted [src] on [L].")
	consume(src, L)
	return TRUE

// Technomancer specific subtype which keeps track of spell power and gets targeted specificially by Dispel.
/datum/body_effect/technomancer
	stacks = MODIFIER_STACK_FORBID
	// Per-application state: the spell power it was cast with (set by on_add_modifier).

/datum/body_effect/technomancer/proc/spell_power_of(mob/living/L)
	var/power = L.body_effect_state(type)
	return isnum(power) ? power : 1
