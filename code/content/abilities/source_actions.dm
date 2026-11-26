// Abilities of the sources that used to have a button bar of their own (the ability and spell masters of the HUD): a power that calls a verb
// (a changeling's stings, a lleill's glamour), a technomancer's spell button, and a /datum/spell. Each is an entry of the mob's ability list
// (action.dm), added when the mob gains the power and removed when it loses it.

/// The picture all of these use for a state that names none of its own.
#define ABILITY_SPELL_ICON 'icons/mob/screen_spells.dmi'

/// An ability that calls a verb or proc of an object when used: a changeling power, a lleill ability. `button_icon_state` is the power's own picture.
/datum/action/verb_ability
	ability_category = ABILITY_CATEGORY_SPECIES
	check_flags = NONE
	button_icon = ABILITY_SPELL_ICON
	/// The object whose proc is called: a relation view (the ability goes with it).
	var/datum/verb_object
	/// The proc called: a verb or proc path.
	var/verb_to_call
	/// What the proc is called with, a list passed as its one argument.
	var/list/verb_arguments

CAPABILITIES(/datum/action/verb_ability)
	ref_one(nameof(verb_object), /datum, on_other_deleted = OTHER_DELETE_ME)

/datum/action/verb_ability/ability_id()
	return "[ability_category]/verb/[verb_to_call]"

/datum/action/verb_ability/Trigger(trigger_flags)
	if(!..())
		return FALSE
	var/datum/target = verb_object
	if(!target || !verb_to_call)
		return FALSE
	LAZYINITLIST(verb_arguments)
	call(target, verb_to_call)(verb_arguments)
	return TRUE

/// Gives `owner` the ability to call `verb_ref` on `object` under `ability_name`, shown with `icon_state` of the ability icons. One verb is one ability.
/proc/grant_verb_ability(mob/owner, datum/object, verb_ref, ability_name, icon_state, category = ABILITY_CATEGORY_SPECIES, list/arguments = null)
	if(!owner || !object || !verb_ref)
		return null
	for(var/datum/action/verb_ability/existing in owner.actions)
		if(existing.verb_to_call == verb_ref)
			return existing
	var/datum/action/verb_ability/entry = new
	rel_set(entry, nameof(entry.verb_object), object)
	entry.verb_to_call = verb_ref
	entry.name = ability_name
	entry.button_icon_state = icon_state
	entry.ability_category = category
	entry.verb_arguments = arguments
	entry.Grant(owner)
	return entry

/// Takes away the verb ability that calls `verb_ref`, if the mob has it.
/proc/revoke_verb_ability(mob/owner, verb_ref)
	for(var/datum/action/verb_ability/existing in owner?.actions?.Copy())
		if(existing.verb_to_call == verb_ref)
			existing.Remove(owner)
			spent(existing)

/// A technomancer's spell button (the spell in the core): using it puts the spell in the hand.
/datum/action/technomancer_spell
	ability_category = ABILITY_CATEGORY_SPELLS
	check_flags = NONE
	button_icon = ABILITY_SPELL_ICON

/// The button this ability is the use of.
/datum/action/technomancer_spell/proc/button() as /obj/spellbutton
	return action_target()

/datum/action/technomancer_spell/ability_id()
	var/obj/spellbutton/button = button()
	return "[ability_category]/technomancer/[button?.spellpath]"

/datum/action/technomancer_spell/Trigger(trigger_flags)
	if(!..())
		return FALSE
	var/obj/spellbutton/button = button()
	var/mob/user = action_owner()
	if(!button || !user)
		return FALSE
	if(button.type == /obj/spellbutton)
		button.create_spell_with_actor(user)
	else
		button.Click()
	return TRUE

/// Gives `owner` the ability of the technomancer spell button `button`.
/proc/grant_technomancer_ability(mob/owner, obj/spellbutton/button)
	if(!owner || !button)
		return null
	var/datum/action/technomancer_spell/entry = new(button)
	entry.name = button.name
	entry.button_icon_state = button.ability_icon_state
	entry.Grant(owner)
	return entry

/// Takes away the ability of `button` from `owner`.
/proc/revoke_technomancer_ability(mob/owner, obj/spellbutton/button)
	for(var/datum/action/technomancer_spell/existing in owner?.actions?.Copy())
		if(existing.button() == button)
			existing.Remove(owner)
			spent(existing)

/// A /datum/spell the mob has (its spell_list): using it casts it. It shows the recharge as a cooldown and the charges left as its cost.
/datum/action/spell_ability
	ability_category = ABILITY_CATEGORY_SPELLS
	check_flags = NONE
	button_icon = ABILITY_SPELL_ICON

/// The spell this ability casts.
/datum/action/spell_ability/proc/spell() as /datum/spell
	return action_target()

/datum/action/spell_ability/ability_id()
	var/datum/spell/spell = spell()
	return "[ability_category]/spell/[spell?.type]"

/datum/action/spell_ability/ability_desc()
	var/datum/spell/spell = spell()
	return (spell?.desc) || name

/datum/action/spell_ability/ability_cost()
	var/datum/spell/spell = spell()
	if(spell?.charge_type == Sp_CHARGES)
		return "[spell.charge_counter]/[spell.charge_max] charges"
	return null

/datum/action/spell_ability/ability_cooldown_left()
	var/datum/spell/spell = spell()
	if(spell?.charge_type == Sp_RECHARGE)
		return max(0, spell.charge_max - spell.charge_counter)
	return 0

/datum/action/spell_ability/ability_refusal()
	var/datum/spell/spell = spell()
	if(!spell)
		return "the spell is gone"
	if(spell.silenced)
		return "silenced"
	if(spell.charge_type == Sp_CHARGES && !spell.charge_counter)
		return "no charges left"
	return ..()

/datum/action/spell_ability/Trigger(trigger_flags)
	if(!..())
		return FALSE
	var/datum/spell/spell = spell()
	var/mob/user = action_owner()
	if(!spell || !user)
		return FALSE
	spell.perform(user)
	ability_changed()
	return TRUE

/// The icon state of a spell's ability: its own picture when it has one, else the ready button of its school.
/proc/spell_ability_icon_state(datum/spell/spell)
	if(length(spell.hud_state))
		return spell.hud_state
	var/base = spell.override_base
	if(!base)
		base = (spell.spell_flags & CONSTRUCT_CHECK) ? "const" : "wiz"
	return "[base]_spell_ready"

/// Gives `owner` the ability of casting `spell`.
/proc/grant_spell_ability(mob/owner, datum/spell/spell)
	if(!owner || !spell || (spell.spell_flags & NO_BUTTON))
		return null
	for(var/datum/action/spell_ability/existing in owner.actions)
		if(existing.spell() == spell)
			return existing
	var/datum/action/spell_ability/entry = new(spell)
	entry.name = spell.name
	entry.button_icon_state = spell_ability_icon_state(spell)
	entry.Grant(owner)
	return entry

/// Takes away the ability of casting `spell` from `owner`.
/proc/revoke_spell_ability(mob/owner, datum/spell/spell)
	for(var/datum/action/spell_ability/existing in owner?.actions?.Copy())
		if(existing.spell() == spell)
			existing.Remove(owner)
			spent(existing)
