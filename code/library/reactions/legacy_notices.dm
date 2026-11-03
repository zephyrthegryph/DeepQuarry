// Notices that replaced the OM events (doc/rewrite/reactions.md section 3). Written by hand now: the generator
// (tools/dx/gen_om_notices.py) went with the events. Each is published with PUBLISH_LEGACY(E, /datum/notice/x, fields...)
// in fill() order until its own ACTION() declaration replaces it.

/// From /datum/affliction/proc/set_severity(), sent to the owning mob: (datum/affliction/affliction, old_severity)
/datum/notice/affliction_severity_changed
	var/affliction
	var/old_severity

/datum/notice/affliction_severity_changed/fill(affliction, old_severity)
	src.affliction = affliction
	src.old_severity = old_severity

/// From /obj/machinery/computer/arcade/prizevend(mob/user, prizes = 1)
/datum/notice/arcade_prizevend
	var/user

/datum/notice/arcade_prizevend/fill(user)
	src.user = user

/// From SSatoms InitAtom, only when the atom was not deleted, did not fail initialization and has a loc: (created, mapload)
/datum/notice/atom_after_successful_initialized_on
	var/created
	var/mapload

/datum/notice/atom_after_successful_initialized_on/fill(created, mapload)
	src.created = created
	src.mapload = mapload

/// A plain one-payload notice (was the old atom/Bumped() echo; walk-ins are /datum/notice/bumped now). The e4 twin-delivery test drives it.
/datum/notice/atom_bumped
	var/bumped

/datum/notice/atom_bumped/fill(bumped)
	src.bumped = bumped

/// From base of atom/setDir(): (old_dir, new_dir). Called before the direction changes.
/datum/notice/atom_dir_change
	var/old_dir
	var/new_dir

/datum/notice/atom_dir_change/fill(old_dir, new_dir)
	src.old_dir = old_dir
	src.new_dir = new_dir

/// From base of atom/emp_act(severity): (severity, protection)
/datum/notice/atom_emp_act
	var/severity
	var/protection

/datum/notice/atom_emp_act/fill(severity, protection)
	src.severity = severity
	src.protection = protection

/// From base of atom/Entered(): (atom/movable/arrived, atom/old_loc, list/atom/old_locs)
/datum/notice/atom_entered
	var/arrived
	var/old_loc

/datum/notice/atom_entered/fill(arrived, old_loc)
	src.arrived = arrived
	src.old_loc = old_loc

/// Sent from the atom that just Entered src. From base of atom/Entered(): (/atom/destination, atom/old_loc, list/atom/old_locs)
/datum/notice/atom_entering
	var/destination
	var/old_loc

/datum/notice/atom_entering/fill(destination, old_loc)
	src.destination = destination
	src.old_loc = old_loc

/// From base of atom/Exited(): `gone` left the atom for `new_loc`.
/datum/notice/atom_exited
	var/gone
	var/new_loc

/datum/notice/atom_exited/fill(gone, new_loc)
	src.gone = gone
	src.new_loc = new_loc

/// From base of atom/fire_act(): (exposed_temperature, exposed_volume)
/datum/notice/atom_fire_act
	var/exposed_temperature
	var/exposed_volume

/datum/notice/atom_fire_act/fill(exposed_temperature, exposed_volume)
	src.exposed_temperature = exposed_temperature
	src.exposed_volume = exposed_volume

/// From internal loop in /atom/proc/propagate_radiation_pulse: (atom/pulse_source)
/datum/notice/atom_propagate_rad_pulse
	var/pulse_source

/datum/notice/atom_propagate_rad_pulse/fill(pulse_source)
	src.pulse_source = pulse_source

/// Called right after the atom changes the value of light_color to a different one, from base of [/atom/proc/set_light_color]: (old_color)
/datum/notice/atom_update_light_color
	var/old_color

/datum/notice/atom_update_light_color/fill(old_color)
	src.old_color = old_color

/// Called right after the atom changes the value of light_flags to a different one, from base of [/atom/proc/set_light_flags]: (old_flags)
/datum/notice/atom_update_light_flags
	var/old_flags

/datum/notice/atom_update_light_flags/fill(old_flags)
	src.old_flags = old_flags

/// Called right after the atom changes the value of light_on to a different one, from base of [/atom/proc/set_light_on]: (old_value)
/datum/notice/atom_update_light_on
	var/old_value

/datum/notice/atom_update_light_on/fill(old_value)
	src.old_value = old_value

/// Lighting: Called right after the atom changes the value of light_power to a different one, from base of [/atom/proc/set_light_power]: (old_power)
/datum/notice/atom_update_light_power
	var/old_power

/datum/notice/atom_update_light_power/fill(old_power)
	src.old_power = old_power

/// Called right after the atom changes the value of light_range to a different one, from base of [/atom/proc/set_light_range]: (old_range)
/datum/notice/atom_update_light_range
	var/old_range

/datum/notice/atom_update_light_range/fill(old_range)
	src.old_range = old_range

/// From base of atom/used_in_craft(): (atom/result)
/datum/notice/atom_used_in_craft
	var/result_

/datum/notice/atom_used_in_craft/fill(result_)
	src.result_ = result_

/// From base of [/atom/proc/extinguish]: the atom's fire was put out (a burning mob's fire_stacks status hears it on its owner).
/datum/notice/atom_extinguish

/// From base of [/atom/proc/take_damage], once the damage landed (after armour): (damage_amount, damage_type, damage_flag, sound_effect, attack_dir, aurmor_penetration)
/datum/notice/atom_take_damage
	var/damage_amount
	var/damage_type
	var/damage_flag
	var/sound_effect
	var/attack_dir
	var/aurmor_penetration

/datum/notice/atom_take_damage/fill(damage_amount, damage_type, damage_flag, sound_effect, attack_dir, aurmor_penetration)
	src.damage_amount = damage_amount
	src.damage_type = damage_type
	src.damage_flag = damage_flag
	src.sound_effect = sound_effect
	src.attack_dir = attack_dir
	src.aurmor_penetration = aurmor_penetration

/// From /obj/belly/HandleBellyReagents() and /obj/belly/update_internal_overlay()
/datum/notice/belly_update_vore_fx
	var/volume

/datum/notice/belly_update_vore_fx/fill(volume)
	src.volume = volume

/// From /mob/proc/base_click_alt(): `mob` alt-clicked the atom. A listener handles the click: when one listens, the atom's own click_alt() and the loot panel do not run.
/datum/notice/click_alt
	var/mob

/datum/notice/click_alt/fill(mob)
	src.mob = mob

/// From the radiation subsystem, called before a potential irradiation. This does not guarantee radiation can reach or will succeed, but merely that there's a radiation source within range. (datum/radiation_pulse_information/pulse_information, insulation_to_target)
/datum/notice/in_range_of_irradiation
	var/pulse_information
	var/insulation_to_target

/datum/notice/in_range_of_irradiation/fill(pulse_information, insulation_to_target)
	src.pulse_information = pulse_information
	src.insulation_to_target = insulation_to_target

/// From /datum/body/add_affliction() and remove_affliction(): (datum/affliction/affliction, added)
/datum/notice/body_afflictions_changed
	var/affliction
	var/added

/datum/notice/body_afflictions_changed/fill(affliction, added)
	src.affliction = affliction
	src.added = added

/// From /datum/body/proc/adopt_subtree(), sent to the owning mob once per part that joined it: (obj/item/organ/part)
/datum/notice/body_part_attached
	var/part

/datum/notice/body_part_attached/fill(part)
	src.part = part

/// From /datum/body/proc/release_subtree(), sent to the owning mob once per part that left it: (obj/item/organ/part)
/datum/notice/body_part_detached
	var/part

/datum/notice/body_part_detached/fill(part)
	src.part = part

/// The `carbon_slip` occurrence (it was an om event).
/datum/notice/carbon_slip
	var/slipped_on
	var/stun_duration

/datum/notice/carbon_slip/fill(slipped_on, stun_duration)
	src.slipped_on = slipped_on
	src.stun_duration = stun_duration

/// From base of atom/Click(): (atom/location, control, params, mob/user)
/datum/notice/click
	var/location
	var/control
	var/params
	var/user

/datum/notice/click/fill(location, control, params, user)
	src.location = location
	src.control = control
	src.params = params
	src.user = user

/// From base of client/Click(): (atom/target, atom/location, control, params, mob/user)
/datum/notice/client_click
	var/target_
	var/location
	var/control
	var/params
	var/user

/datum/notice/client_click/fill(target_, location, control, params, user)
	src.target_ = target_
	src.location = location
	src.control = control
	src.params = params
	src.user = user

/// The `closet_closed` occurrence (it was an om event).
/datum/notice/closet_closed

/// Called when a disposal connected object attempts to link to a trunk: (/obj/structure/disposalpipe/trunk)
/datum/notice/disposal_link
	var/trunk

/datum/notice/disposal_link/fill(trunk)
	src.trunk = trunk

/// Called when a disposal connected object recieves an object from it's connected trunk
/datum/notice/disposal_receive
	var/items
	var/gas

/datum/notice/disposal_receive/fill(items, gas)
	src.items = items
	src.gas = gas

/// Called when a disposal connected object should unlink from a trunk it's attached to.
/datum/notice/disposal_unlink

/// Sent from /proc/do_after once a do_after action completes, whether via the bar filling or via interruption.
/// --------------------------------------------------------------------------- Signals emitted on the mob by the brain framework. Behaviors can subscribe to these via their eval_triggers list to re-evaluate only when relevant. ---------------------------------------------------------------------------
/datum/notice/dqai_damage_taken
	var/amount
	var/injury_kind
	var/attacker

/datum/notice/dqai_damage_taken/fill(amount, injury_kind, attacker)
	src.amount = amount
	src.injury_kind = injury_kind
	src.attacker = attacker

/// Notification: `user` examined the atom. Handlers
/// append lines to `texts`, the examine output list.
/datum/notice/examine
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)
	var/user
	var/texts

/datum/notice/examine/fill(user, texts)
	src.user = user
	src.texts = texts

/// Signal that gets sent when a ghost query is completed
/datum/notice/ghost_query_complete

/// Notification: the atom was hit by thrown `source`.
/datum/notice/hitby
	var/source_
	var/throwingdatum

/datum/notice/hitby/fill(source_, throwingdatum)
	src.source_ = source_
	src.throwingdatum = throwingdatum

/// Non TG signals.
/// Hose Connector Component
/datum/notice/hose_forcepump

/// NON TG Signals When the mob's dna and species have been fully applied
/datum/notice/human_dna_finalized

/// Sent to the instrument when a song stops playing
/datum/notice/instrument_end
	var/finished

/datum/notice/instrument_end/fill(finished)
	src.finished = finished

/// Sent to the instrument when a song starts playing: (datum/starting_song, atom/player)
/datum/notice/instrument_start
	var/starting_song
	var/player

/datum/notice/instrument_start/fill(starting_song, player)
	src.starting_song = starting_song
	src.player = player

/// From base of /obj/item/attack(): (mob/living, mob/living, list/modifiers, list/attack_modifiers)
/datum/notice/item_attack
	var/target_
	var/user
	var/target_zone

/datum/notice/item_attack/fill(target_, user, target_zone)
	src.target_ = target_
	src.user = user
	src.target_zone = target_zone

/// From base of obj/item/dropped(): (mob/user)
/datum/notice/item_dropped
	var/user

/datum/notice/item_dropped/fill(user)
	src.user = user

/// From base of obj/item/equipped(): (mob/equipper, slot)
/datum/notice/item_equipped
	var/equipper
	var/slot

/datum/notice/item_equipped/fill(equipper, slot)
	src.equipper = equipper
	src.slot = slot

/// From base of obj/item/pickup(): (/mob/taker)
/datum/notice/item_pickup
	var/taker

/datum/notice/item_pickup/fill(taker)
	src.taker = taker

/// Sent from [atom/proc/item_interaction], when this atom is used as a tool and an event occurs
/datum/notice/item_tool_acted
	var/target_
	var/user
	var/tool_quality
	var/modifiers

/datum/notice/item_tool_acted/fill(target_, user, tool_quality, modifiers)
	src.target_ = target_
	src.user = user
	src.tool_quality = tool_quality
	src.modifiers = modifiers

/// From end of revival_healing_action(): ()
/datum/notice/living_aheal

/// From /mob/proc/death(), once per death, after EVERY death side effect (on_death(), HUD refresh, antag win check): (gibbed). Never sent on a repeated or replaced death. Hang end-of-death work (delete_on_death) here; death() itself never deletes the mob.
/datum/notice/living_death_final
	var/gibbed

/datum/notice/living_death_final/fill(gibbed)
	src.gibbed = gibbed

/// From base of /mob/living/proc/injure(), after the injury applied: (kind, applied, zone, atom/source, flags)
/datum/notice/living_injured
	var/kind
	var/applied
	var/zone
	var/source_
	var/flags

/datum/notice/living_injured/fill(kind, applied, zone, source_, flags)
	src.kind = kind
	src.applied = applied
	src.zone = zone
	src.source_ = source_
	src.flags = flags

/// From /mob/living/proc/injure() once mitigation is done, when something listens or the injury trace is on: (incoming_kind, landed_kind, list/stages, zone, atom/source, flags). Each stage is list(INJURY_STAGE_*, amount_in, amount_out, detail).
/datum/notice/living_injury_explained
	var/incoming_kind
	var/landed_kind
	var/stages
	var/zone
	var/source_
	var/flags

/datum/notice/living_injury_explained/fill(incoming_kind, landed_kind, stages, zone, source_, flags)
	src.incoming_kind = incoming_kind
	src.landed_kind = landed_kind
	src.stages = stages
	src.zone = zone
	src.source_ = source_
	src.flags = flags

/// From /mob/living/proc/return_from_death(), after the mob is alive again: (datum/source, reason)
/datum/notice/living_revived
	var/source_
	var/reason

/datum/notice/living_revived/fill(source_, reason)
	src.source_ = source_
	src.reason = reason

/// From /mob/living/proc/injure(), mitigation stage 2 (energy shields), after armour: (kind, list/amount_ref, zone, atom/source, flags). Shields scale amount_ref[1].
/datum/notice/living_shield_injury
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)
	var/kind
	var/amount_ref
	var/zone
	var/source_
	var/flags

/datum/notice/living_shield_injury/fill(kind, amount_ref, zone, source_, flags)
	src.kind = kind
	src.amount_ref = amount_ref
	src.zone = zone
	src.source_ = source_
	src.flags = flags

/// From /atom/atom_break(damage_flag): the atom crossed its integrity_failure threshold. (damage_flag)
/datum/notice/atom_broken
	var/damage_flag

/datum/notice/atom_broken/fill(damage_flag)
	src.damage_flag = damage_flag

/// From /obj/machinery/atom_break(damage_flag): (damage_flag)
/datum/notice/machinery_broken
	var/damage_flag

/datum/notice/machinery_broken/fill(damage_flag)
	src.damage_flag = damage_flag

/// From /obj/machinery/rnd/destructive_analyzer/proc/destroy_item(gain_research_points = FALSE): Runs when the destructive scanner scans a group of objects. (list/scanned_atoms)
/datum/notice/machinery_destructive_scan
	var/scanned_atoms

/datum/notice/machinery_destructive_scan/fill(scanned_atoms)
	src.scanned_atoms = scanned_atoms

/// From /obj/machinery/doppler_array/proc/sense_explosion(): Runs when an explosion is detected. (turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, seconds_taken)
/datum/notice/machinery_explosion_detected
	var/epicenter
	var/devastation_range
	var/heavy_impact_range
	var/light_impact_range
	var/seconds_taken

/datum/notice/machinery_explosion_detected/fill(epicenter, devastation_range, heavy_impact_range, light_impact_range, seconds_taken)
	src.epicenter = epicenter
	src.devastation_range = devastation_range
	src.heavy_impact_range = heavy_impact_range
	src.light_impact_range = light_impact_range
	src.seconds_taken = seconds_taken

/// From base power_change() when power is lost
/datum/notice/machinery_power_lost

/// From base power_change() when power is restored
/datum/notice/machinery_power_restored

/// Material Container Signals Called from datum/component/material_container/proc/insert_item() : (item, primary_mat, mats_consumed, material_amount, context)
/datum/notice/matcontainer_item_consumed
	var/item
	var/primary_mat
	var/mats_consumed
	var/material_amount
	var/context

/datum/notice/matcontainer_item_consumed/fill(item, primary_mat, mats_consumed, material_amount, context)
	src.item = item
	src.primary_mat = primary_mat
	src.mats_consumed = mats_consumed
	src.material_amount = material_amount
	src.context = context

/// Called from datum/component/material_container/proc/retrieve_stack() : (new_stack, context)
/datum/notice/matcontainer_stack_retrieved
	var/new_stack
	var/context

/datum/notice/matcontainer_stack_retrieved/fill(new_stack, context)
	src.new_stack = new_stack
	src.context = context

/// Notification: the movable changed loc.
/datum/notice/moved
	var/old_loc
	var/direction
	var/forced

/datum/notice/moved/fill(old_loc, direction, forced)
	src.old_loc = old_loc
	src.direction = direction
	src.forced = forced

/// Just before a datum's Destroy() is called: (force), at this point none of the other components chose to interrupt qdel and Destroy will be called
/// Sent to the obj from base of [/datum/reagent/proc/touch_obj]: (datum/reagent/reagent, amount)
/datum/notice/reagent_expose_obj
	var/datum/reagent/reagent
	var/amount

/datum/notice/reagent_expose_obj/fill(reagent, amount)
	src.reagent = reagent
	src.amount = amount

/// Non TG signals: from base of /datum/reagents/proc/handle_reactions(): (list/datum/xform)
/datum/notice/reagents_holder_reacted
	/// The /datum/xform rules that fired in the settle, in the order they first did.
	var/rules

/datum/notice/reagents_holder_reacted/fill(rules)
	src.rules = rules

