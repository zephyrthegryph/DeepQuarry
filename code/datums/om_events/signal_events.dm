// Events that replaced the DCS signals (object_model_core.md sec 10,
// signal_migration_map.md). One type per former COMSIG_*, payload vars named after
// the signal's documented arguments. Plain events are `sync`: delivered at once to
// the entity's behaviours, with numeric returns ORed
// into `result`, which om_emit() returns. before/ events are `accumulate`: the same,
// for events whose sender reads the result (the former COMPONENT_* return bits, or
// EVENT_VETO). Send with OM_EMIT(entity, /datum/definition_event/x, args...).
// Keep domain-specific events next to their domain when you touch them.

/// From /datum/affliction/proc/set_severity(), sent to the owning mob: (datum/affliction/affliction, old_severity)
/datum/definition_event/affliction_severity_changed
	sync = TRUE
	var/affliction
	var/old_severity

/datum/definition_event/affliction_severity_changed/New(affliction, old_severity)
	src.affliction = affliction
	src.old_severity = old_severity

/// From /obj/machinery/computer/arcade/prizevend(mob/user, prizes = 1)
/datum/definition_event/arcade_prizevend
	sync = TRUE
	var/user

/datum/definition_event/arcade_prizevend/New(user)
	src.user = user

/// /atom signals from SSatoms InitAtom - Only if the  atom was not deleted or failed initialization from SSatoms InitAtom - Only if the  atom was not deleted or failed initialization and has a loc
/datum/definition_event/atom_after_successful_initialized_on
	sync = TRUE
	var/created
	var/mapload

/datum/definition_event/atom_after_successful_initialized_on/New(created, mapload)
	src.created = created
	src.mapload = mapload

/// From base of atom/Bumped(): (/atom/movable) (the one that gets bumped)
/datum/definition_event/atom_bumped
	sync = TRUE
	var/bumped

/datum/definition_event/atom_bumped/New(bumped)
	src.bumped = bumped

/// From base of atom/setDir(): (old_dir, new_dir). Called before the direction changes.
/datum/definition_event/atom_dir_change
	sync = TRUE
	var/old_dir
	var/new_dir

/datum/definition_event/atom_dir_change/New(old_dir, new_dir)
	src.old_dir = old_dir
	src.new_dir = new_dir

/// From base of atom/emp_act(severity): (severity, protection)
/datum/definition_event/atom_emp_act
	sync = TRUE
	var/severity
	var/protection

/datum/definition_event/atom_emp_act/New(severity, protection)
	src.severity = severity
	src.protection = protection

/// From base of atom/Entered(): (atom/movable/arrived, atom/old_loc, list/atom/old_locs)
/datum/definition_event/atom_entered
	sync = TRUE
	var/arrived
	var/old_loc

/datum/definition_event/atom_entered/New(arrived, old_loc)
	src.arrived = arrived
	src.old_loc = old_loc

/// Sent from the atom that just Entered src. From base of atom/Entered(): (/atom/destination, atom/old_loc, list/atom/old_locs)
/datum/definition_event/atom_entering
	sync = TRUE
	var/destination
	var/old_loc

/datum/definition_event/atom_entering/New(destination, old_loc)
	src.destination = destination
	src.old_loc = old_loc

/// From base of atom/Exited(): `gone` left the atom for `new_loc`.
/datum/definition_event/atom_exited
	sync = TRUE
	var/gone
	var/new_loc

/datum/definition_event/atom_exited/New(gone, new_loc)
	src.gone = gone
	src.new_loc = new_loc

/// From base of atom/attack_basic_mob(): (/mob/user) from base of [/atom/proc/extinguish]
/datum/definition_event/before/atom_extinguish
	accumulate = TRUE

/// From base of atom/fire_act(): (exposed_temperature, exposed_volume)
/datum/definition_event/atom_fire_act
	sync = TRUE
	var/exposed_temperature
	var/exposed_volume

/datum/definition_event/atom_fire_act/New(exposed_temperature, exposed_volume)
	src.exposed_temperature = exposed_temperature
	src.exposed_volume = exposed_volume

/// From internal loop in /atom/proc/propagate_radiation_pulse: (atom/pulse_source)
/datum/definition_event/atom_propagate_rad_pulse
	sync = TRUE
	var/pulse_source

/datum/definition_event/atom_propagate_rad_pulse/New(pulse_source)
	src.pulse_source = pulse_source

/// From base of [/atom/proc/take_damage]: (damage_amount, damage_type, damage_flag, sound_effect, attack_dir, aurmor_penetration)
/datum/definition_event/before/atom_take_damage
	accumulate = TRUE
	var/damage_amount
	var/damage_type
	var/damage_flag
	var/sound_effect
	var/attack_dir
	var/aurmor_penetration

/datum/definition_event/before/atom_take_damage/New(damage_amount, damage_type, damage_flag, sound_effect, attack_dir, aurmor_penetration)
	src.damage_amount = damage_amount
	src.damage_type = damage_type
	src.damage_flag = damage_flag
	src.sound_effect = sound_effect
	src.attack_dir = attack_dir
	src.aurmor_penetration = aurmor_penetration

/// Called right after the atom changes the value of light_color to a different one, from base of [/atom/proc/set_light_color]: (old_color)
/datum/definition_event/atom_update_light_color
	sync = TRUE
	var/old_color

/datum/definition_event/atom_update_light_color/New(old_color)
	src.old_color = old_color

/// Called right after the atom changes the value of light_flags to a different one, from base of [/atom/proc/set_light_flags]: (old_flags)
/datum/definition_event/atom_update_light_flags
	sync = TRUE
	var/old_flags

/datum/definition_event/atom_update_light_flags/New(old_flags)
	src.old_flags = old_flags

/// Called right after the atom changes the value of light_on to a different one, from base of [/atom/proc/set_light_on]: (old_value)
/datum/definition_event/atom_update_light_on
	sync = TRUE
	var/old_value

/datum/definition_event/atom_update_light_on/New(old_value)
	src.old_value = old_value

/// Lighting: Called right after the atom changes the value of light_power to a different one, from base of [/atom/proc/set_light_power]: (old_power)
/datum/definition_event/atom_update_light_power
	sync = TRUE
	var/old_power

/datum/definition_event/atom_update_light_power/New(old_power)
	src.old_power = old_power

/// Called right after the atom changes the value of light_range to a different one, from base of [/atom/proc/set_light_range]: (old_range)
/datum/definition_event/atom_update_light_range
	sync = TRUE
	var/old_range

/datum/definition_event/atom_update_light_range/New(old_range)
	src.old_range = old_range

/// From base of atom/used_in_craft(): (atom/result)
/datum/definition_event/atom_used_in_craft
	sync = TRUE
	var/result_

/datum/definition_event/atom_used_in_craft/New(result_)
	src.result_ = result_

/// From /obj/belly/HandleBellyReagents() and /obj/belly/update_internal_overlay()
/datum/definition_event/before/belly_update_vore_fx
	accumulate = TRUE
	var/volume

/datum/definition_event/before/belly_update_vore_fx/New(volume)
	src.volume = volume

/// From /datum/body/add_affliction() and remove_affliction(): (datum/affliction/affliction, added)
/datum/definition_event/body_afflictions_changed
	sync = TRUE
	var/affliction
	var/added

/datum/definition_event/body_afflictions_changed/New(affliction, added)
	src.affliction = affliction
	src.added = added

/// From /datum/body/proc/adopt_subtree(), sent to the owning mob once per part that joined it: (obj/item/organ/part)
/datum/definition_event/body_part_attached
	sync = TRUE
	var/part

/datum/definition_event/body_part_attached/New(part)
	src.part = part

/// From /datum/body/proc/release_subtree(), sent to the owning mob once per part that left it: (obj/item/organ/part)
/datum/definition_event/body_part_detached
	sync = TRUE
	var/part

/datum/definition_event/body_part_detached/New(part)
	src.part = part

/// From base of atom/Click(): (atom/location, control, params, mob/user)
/datum/definition_event/click
	sync = TRUE
	var/location
	var/control
	var/params
	var/user

/datum/definition_event/click/New(location, control, params, user)
	src.location = location
	src.control = control
	src.params = params
	src.user = user

/// #define COMSIG_MOB_CANCEL_CLICKON (1<<0) //shared with other forms of click, this is so you're aware it exists here too. from base of atom/click_alt(): (/mob)
/datum/definition_event/before/click_alt
	accumulate = TRUE
	var/mob

/datum/definition_event/before/click_alt/New(mob)
	src.mob = mob

/// From base of client/Click(): (atom/target, atom/location, control, params, mob/user)
/datum/definition_event/client_click
	sync = TRUE
	var/target
	var/location
	var/control
	var/params
	var/user

/datum/definition_event/client_click/New(target, location, control, params, user)
	src.target = target
	src.location = location
	src.control = control
	src.params = params
	src.user = user

/// Called when a disposal connected object attempts to link to a trunk: (/obj/structure/disposalpipe/trunk)
/datum/definition_event/disposal_link
	sync = TRUE
	var/trunk

/datum/definition_event/disposal_link/New(trunk)
	src.trunk = trunk

/// Called when a disposal connected object recieves an object from it's connected trunk
/datum/definition_event/disposal_receive
	sync = TRUE
	var/items
	var/gas

/datum/definition_event/disposal_receive/New(items, gas)
	src.items = items
	src.gas = gas

/// Called when a disposal connected object should unlink from a trunk it's attached to.
/datum/definition_event/disposal_unlink
	sync = TRUE

/// Sent from /proc/do_after if someone starts a do_after action bar.
/datum/definition_event/do_after_began
	sync = TRUE

/// Sent from /proc/do_after once a do_after action completes, whether via the bar filling or via interruption.
/datum/definition_event/do_after_ended
	sync = TRUE

/// --------------------------------------------------------------------------- Signals emitted on the mob by the brain framework. Behaviors can subscribe to these via their eval_triggers list to re-evaluate only when relevant. ---------------------------------------------------------------------------
/datum/definition_event/dqai_damage_taken
	sync = TRUE
	var/amount
	var/injury_kind
	var/attacker

/datum/definition_event/dqai_damage_taken/New(amount, injury_kind, attacker)
	src.amount = amount
	src.injury_kind = injury_kind
	src.attacker = attacker

/datum/definition_event/dqai_target_changed
	sync = TRUE
	var/new_target
	var/old_target

/datum/definition_event/dqai_target_changed/New(new_target, old_target)
	src.new_target = new_target
	src.old_target = old_target

/datum/definition_event/dqai_target_lost
	sync = TRUE
	var/old_target

/datum/definition_event/dqai_target_lost/New(old_target)
	src.old_target = old_target

/// Signal that gets sent when a ghost query is completed
/datum/definition_event/ghost_query_complete
	sync = TRUE

/// Called after an explosion happened : (epicenter, devastation_range, heavy_impact_range, light_impact_range, took, orig_dev_range, orig_heavy_range, orig_light_range)
/datum/definition_event/world_explosion
	sync = TRUE
	var/epicenter
	var/devastation_range
	var/heavy_impact_range
	var/light_impact_range
	var/took

/datum/definition_event/world_explosion/New(epicenter, devastation_range, heavy_impact_range, light_impact_range, took)
	src.epicenter = epicenter
	src.devastation_range = devastation_range
	src.heavy_impact_range = heavy_impact_range
	src.light_impact_range = light_impact_range
	src.took = took

/// Called when a ghost or phaser is captured by a ghosttrap: (mob/passing_entity)
/datum/definition_event/world_ghost_captured
	sync = TRUE
	var/passing_entity

/datum/definition_event/world_ghost_captured/New(passing_entity)
	src.passing_entity = passing_entity

/// Called from base of /mob/Initialise : (mob)
/datum/definition_event/world_mob_created
	sync = TRUE
	var/mob

/datum/definition_event/world_mob_created/New(mob)
	src.mob = mob

/// Mob died somewhere : (mob/living, gibbed)
/datum/definition_event/world_mob_death
	sync = TRUE
	var/living
	var/gibbed

/datum/definition_event/world_mob_death/New(living, gibbed)
	src.living = living
	src.gibbed = gibbed

/// Payment account status changed /obj/machinery/account_database/tgui_act() : (datum/money_account/account)
/datum/definition_event/world_payment_account_status
	sync = TRUE
	var/account

/datum/definition_event/world_payment_account_status/New(account)
	src.account = account

/// Shuttle Comsigs Supply shuttle selling, before all items are sold, called by /datum/controller/subsystem/supply/proc/sell() : (/list/area/supply_shuttle_areas)
/datum/definition_event/world_supply_shuttle_depart
	sync = TRUE
	var/supply_shuttle_areas

/datum/definition_event/world_supply_shuttle_depart/New(supply_shuttle_areas)
	src.supply_shuttle_areas = supply_shuttle_areas

/// Called when a shadow wright passes by a ghosttrap: (obj/effect/shadow_wight)
/datum/definition_event/world_wight_captured
	sync = TRUE
	var/shadow_wight

/datum/definition_event/world_wight_captured/New(shadow_wight)
	src.shadow_wight = shadow_wight

/// Non TG signals.
/// Hose Connector Component
/datum/definition_event/hose_forcepump
	sync = TRUE

/// NON TG Signals When the mob's dna and species have been fully applied
/datum/definition_event/human_dna_finalized
	sync = TRUE

/// Sent to the instrument when a song stops playing
/datum/definition_event/instrument_end
	sync = TRUE
	var/finished

/datum/definition_event/instrument_end/New(finished)
	src.finished = finished

/// Sent to the instrument when a song starts playing: (datum/starting_song, atom/player)
/datum/definition_event/instrument_start
	sync = TRUE
	var/starting_song
	var/player

/datum/definition_event/instrument_start/New(starting_song, player)
	src.starting_song = starting_song
	src.player = player

/// From the radiation subsystem, called before a potential irradiation. This does not guarantee radiation can reach or will succeed, but merely that there's a radiation source within range. (datum/radiation_pulse_information/pulse_information, insulation_to_target)
/datum/definition_event/before/in_range_of_irradiation
	accumulate = TRUE
	var/pulse_information
	var/insulation_to_target

/datum/definition_event/before/in_range_of_irradiation/New(pulse_information, insulation_to_target)
	src.pulse_information = pulse_information
	src.insulation_to_target = insulation_to_target

/// From base of /obj/item/attack(): (mob/living, mob/living, list/modifiers, list/attack_modifiers)
/datum/definition_event/item_attack
	sync = TRUE
	var/target
	var/user
	var/target_zone

/datum/definition_event/item_attack/New(target, user, target_zone)
	src.target = target
	src.user = user
	src.target_zone = target_zone

/// From base of obj/item/dropped(): (mob/user)
/datum/definition_event/item_dropped
	sync = TRUE
	var/user

/datum/definition_event/item_dropped/New(user)
	src.user = user

/// From base of obj/item/equipped(): (mob/equipper, slot)
/datum/definition_event/item_equipped
	sync = TRUE
	var/equipper
	var/slot

/datum/definition_event/item_equipped/New(equipper, slot)
	src.equipper = equipper
	src.slot = slot

/// From base of obj/item/pickup(): (/mob/taker)
/datum/definition_event/item_pickup
	sync = TRUE
	var/taker

/datum/definition_event/item_pickup/New(taker)
	src.taker = taker

/// Sent from [atom/proc/item_interaction], when this atom is used as a tool and an event occurs
/datum/definition_event/item_tool_acted
	sync = TRUE
	var/target
	var/user
	var/tool_quality
	var/modifiers

/datum/definition_event/item_tool_acted/New(target, user, tool_quality, modifiers)
	src.target = target
	src.user = user
	src.tool_quality = tool_quality
	src.modifiers = modifiers

/// From end of revival_healing_action(): ()
/datum/definition_event/living_aheal
	sync = TRUE

/// From /mob/proc/death(), once per death, after EVERY death side effect (on_death(), HUD refresh, antag win check): (gibbed). Never sent on a repeated or replaced death. Hang end-of-death work (delete_on_death) here; death() itself never deletes the mob.
/datum/definition_event/living_death_final
	sync = TRUE
	var/gibbed

/datum/definition_event/living_death_final/New(gibbed)
	src.gibbed = gibbed

/// From base of /mob/living/proc/injure(), after the injury applied: (kind, applied, zone, atom/source, flags)
/datum/definition_event/living_injured
	sync = TRUE
	var/kind
	var/applied
	var/zone
	var/source
	var/flags

/datum/definition_event/living_injured/New(kind, applied, zone, source, flags)
	src.kind = kind
	src.applied = applied
	src.zone = zone
	src.source = source
	src.flags = flags

/// From /mob/living/proc/injure() once mitigation is done, when something listens or the injury trace is on: (incoming_kind, landed_kind, list/stages, zone, atom/source, flags). Each stage is list(INJURY_STAGE_*, amount_in, amount_out, detail).
/datum/definition_event/living_injury_explained
	sync = TRUE
	var/incoming_kind
	var/landed_kind
	var/stages
	var/zone
	var/source
	var/flags

/datum/definition_event/living_injury_explained/New(incoming_kind, landed_kind, stages, zone, source, flags)
	src.incoming_kind = incoming_kind
	src.landed_kind = landed_kind
	src.stages = stages
	src.zone = zone
	src.source = source
	src.flags = flags

/// From /mob/living/proc/return_from_death(), after the mob is alive again: (datum/source, reason)
/datum/definition_event/living_revived
	sync = TRUE
	var/source
	var/reason

/datum/definition_event/living_revived/New(source, reason)
	src.source = source
	src.reason = reason

/// From /mob/living/proc/injure(), mitigation stage 2 (energy shields), after armour: (kind, list/amount_ref, zone, atom/source, flags). Shields scale amount_ref[1].
/datum/definition_event/living_shield_injury
	sync = TRUE
	var/kind
	var/amount_ref
	var/zone
	var/source
	var/flags

/datum/definition_event/living_shield_injury/New(kind, amount_ref, zone, source, flags)
	src.kind = kind
	src.amount_ref = amount_ref
	src.zone = zone
	src.source = source
	src.flags = flags

/// Called when a living mob collides with a dense turf : /mob/living/proc/turf_collision(var/turf/T, var/speed)
/datum/definition_event/before/living_turf_collision
	accumulate = TRUE
	var/t
	var/speed

/datum/definition_event/before/living_turf_collision/New(t, speed)
	src.t = t
	src.speed = speed

/// From /obj/machinery/atom_break(damage_flag): (damage_flag)
/datum/definition_event/machinery_broken
	sync = TRUE
	var/damage_flag

/datum/definition_event/machinery_broken/New(damage_flag)
	src.damage_flag = damage_flag

/// From /obj/machinery/rnd/destructive_analyzer/proc/destroy_item(gain_research_points = FALSE): Runs when the destructive scanner scans a group of objects. (list/scanned_atoms)
/datum/definition_event/machinery_destructive_scan
	sync = TRUE
	var/scanned_atoms

/datum/definition_event/machinery_destructive_scan/New(scanned_atoms)
	src.scanned_atoms = scanned_atoms

/// From /obj/machinery/doppler_array/proc/sense_explosion(): Runs when an explosion is detected. (turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, seconds_taken)
/datum/definition_event/machinery_explosion_detected
	sync = TRUE
	var/epicenter
	var/devastation_range
	var/heavy_impact_range
	var/light_impact_range
	var/seconds_taken

/datum/definition_event/machinery_explosion_detected/New(epicenter, devastation_range, heavy_impact_range, light_impact_range, seconds_taken)
	src.epicenter = epicenter
	src.devastation_range = devastation_range
	src.heavy_impact_range = heavy_impact_range
	src.light_impact_range = light_impact_range
	src.seconds_taken = seconds_taken

/// From base power_change() when power is lost
/datum/definition_event/machinery_power_lost
	sync = TRUE

/// From base power_change() when power is restored
/datum/definition_event/machinery_power_restored
	sync = TRUE

/// Material Container Signals Called from datum/component/material_container/proc/insert_item() : (item, primary_mat, mats_consumed, material_amount, context)
/datum/definition_event/matcontainer_item_consumed
	sync = TRUE
	var/item
	var/primary_mat
	var/mats_consumed
	var/material_amount
	var/context

/datum/definition_event/matcontainer_item_consumed/New(item, primary_mat, mats_consumed, material_amount, context)
	src.item = item
	src.primary_mat = primary_mat
	src.mats_consumed = mats_consumed
	src.material_amount = material_amount
	src.context = context

/// Called from datum/component/material_container/proc/retrieve_stack() : (new_stack, context)
/datum/definition_event/matcontainer_stack_retrieved
	sync = TRUE
	var/new_stack
	var/context

/datum/definition_event/matcontainer_stack_retrieved/New(new_stack, context)
	src.new_stack = new_stack
	src.context = context

/datum/definition_event/material_surgery
	sync = TRUE
	var/patient
	var/zone
	var/success

/datum/definition_event/material_surgery/New(patient, zone, success)
	src.patient = patient
	src.zone = zone
	src.success = success

/// From base of /mob/living/proc/apply_damage(): (damage, damagetype, def_zone, blocked, wound_bonus, exposed_wound_bonus, sharpness, attack_direction, attacking_item)
/datum/definition_event/mob_apply_damage
	sync = TRUE
	var/damage
	var/damagetype
	var/def_zone
	var/blocked
	var/wound_bonus
	var/exposed_wound_bonus
	var/sharpness
	var/attack_direction
	var/attacking_item

/datum/definition_event/mob_apply_damage/New(damage, damagetype, def_zone, blocked, wound_bonus, exposed_wound_bonus, sharpness, attack_direction, attacking_item)
	src.damage = damage
	src.damagetype = damagetype
	src.def_zone = def_zone
	src.blocked = blocked
	src.wound_bonus = wound_bonus
	src.exposed_wound_bonus = exposed_wound_bonus
	src.sharpness = sharpness
	src.attack_direction = attack_direction
	src.attacking_item = attacking_item

/// Sent when a mob/login() finishes: (client)
/datum/definition_event/mob_client_login
	sync = TRUE
	var/client

/datum/definition_event/mob_client_login/New(client)
	src.client = client

/// From base of mob/death(): (gibbed)
/datum/definition_event/mob_death
	sync = TRUE
	var/gibbed

/datum/definition_event/mob_death/New(gibbed)
	src.gibbed = gibbed

/// From /proc/domutcheck(): ()
/datum/definition_event/mob_dna_mutation
	sync = TRUE

/// A mob has just equipped an item. Called on [/mob] from base of [/obj/item/equipped()]: (/obj/item/equipped_item, slot)
/datum/definition_event/mob_equipped_item
	sync = TRUE
	var/equipped_item
	var/slot

/datum/definition_event/mob_equipped_item/New(equipped_item, slot)
	src.equipped_item = equipped_item
	src.slot = slot

/// From /datum/action/Grant(): (datum/action)
/datum/definition_event/mob_granted_action
	sync = TRUE
	var/action

/datum/definition_event/mob_granted_action/New(action)
	src.action = action

/// From base of /mob/Login(): ()
/datum/definition_event/mob_login
	sync = TRUE

/// From base of /mob/Logout(): ()
/datum/definition_event/mob_logout
	sync = TRUE

/// A condition was attached, removed, or crossed a clinically meaningful threshold.
/datum/definition_event/mob_medical_issues_changed
	sync = TRUE

/// From mind/transfer_to. Sent to the receiving mob.
/datum/definition_event/mob_mind_transferred_into
	sync = TRUE
	var/old_character

/datum/definition_event/mob_mind_transferred_into/New(old_character)
	src.old_character = old_character

/// From mind/transfer_from. Sent to the mob the mind is being transferred out of.
/datum/definition_event/mob_mind_transferred_out_of
	sync = TRUE
	var/new_character

/datum/definition_event/mob_mind_transferred_out_of/New(new_character)
	src.new_character = new_character

/// From /datum/action/Remove(): (datum/action)
/datum/definition_event/mob_removed_action
	sync = TRUE
	var/action

/datum/definition_event/mob_removed_action/New(action)
	src.action = action

/// From base of /mob/proc/reset_perspective() : ()
/datum/definition_event/mob_reset_perspective
	sync = TRUE

/// From base of mob/set_stat(): (new_stat, old_stat)
/datum/definition_event/mob_statchange
	sync = TRUE
	var/new_stat
	var/old_stat

/datum/definition_event/mob_statchange/New(new_stat, old_stat)
	src.new_stat = new_stat
	src.old_stat = old_stat

/// A mob has just unequipped an item.
/datum/definition_event/mob_unequipped_item
	sync = TRUE
	var/item
	var/target

/datum/definition_event/mob_unequipped_item/New(item, target)
	src.item = item
	src.target = target

/// From base of atom/movable/Moved(): (/atom, newloc, direction)
/datum/definition_event/movable_attempted_move
	sync = TRUE
	var/old_loc
	var/new_loc

/datum/definition_event/movable_attempted_move/New(old_loc, new_loc)
	src.old_loc = old_loc
	src.new_loc = new_loc

/// From base of atom/movable/Bump(): (/atom)
/datum/definition_event/before/movable_bump
	accumulate = TRUE
	var/atom

/datum/definition_event/before/movable_bump/New(atom)
	src.atom = atom

/// From base of atom/movable/throw_impact() after confirming a hit: (/atom/hit_atom, /datum/thrownthing/throwingdatum)
/datum/definition_event/movable_impact
	sync = TRUE
	var/hit_atom
	var/throwingdatum

/datum/definition_event/movable_impact/New(hit_atom, throwingdatum)
	src.hit_atom = hit_atom
	src.throwingdatum = throwingdatum

/// From /datum/controller/subsystem/motion_tracker/notice() (source_atom,/turf/echo_turf_location)
/datum/definition_event/movable_motiontracker
	sync = TRUE
	/// The moving atom that made the echo.
	var/atom/source
	var/echo_turf_location

/datum/definition_event/movable_motiontracker/New(atom/source, echo_turf_location)
	src.source = source // ALLOW(ownership): a sync event payload that lives for one emit and is never destroyed
	src.echo_turf_location = echo_turf_location

/// From base of atom/movable/on_changed_z_level(): (turf/old_turf, turf/new_turf, same_z_layer)
/datum/definition_event/before/movable_z_changed
	accumulate = TRUE
	var/old_z
	var/new_z

/datum/definition_event/before/movable_z_changed/New(old_z, new_z)
	src.old_z = old_z
	src.new_z = new_z

/// /obj signals from base of obj/deconstruct(): (disassembled)
/datum/definition_event/obj_deconstruct
	sync = TRUE
	var/disassembled

/datum/definition_event/obj_deconstruct/New(disassembled)
	src.disassembled = disassembled

/datum/definition_event/observer_apc
	sync = TRUE

/datum/definition_event/observer_globalmoved
	sync = TRUE

/datum/definition_event/observer_shuttle_added
	sync = TRUE
	var/shuttle

/datum/definition_event/observer_shuttle_added/New(shuttle)
	src.shuttle = shuttle

/datum/definition_event/observer_shuttle_moved
	sync = TRUE
	var/old_location
	var/destination

/datum/definition_event/observer_shuttle_moved/New(old_location, destination)
	src.old_location = old_location
	src.destination = destination

/datum/definition_event/observer_shuttle_pre_move
	sync = TRUE
	var/old_location
	var/destination

/datum/definition_event/observer_shuttle_pre_move/New(old_location, destination)
	src.old_location = old_location
	src.destination = destination

/datum/definition_event/observer_turf_entered
	sync = TRUE
	var/atom/movable/arrived
	var/old_loc

/datum/definition_event/observer_turf_entered/New(atom/movable/arrived, old_loc)
	src.arrived = arrived // ALLOW(ownership): a sync event payload that lives for one emit and is never destroyed; a relation index entry on every mover would outlive it
	src.old_loc = old_loc

/// From /client/proc/handle_popup_close() : (window_id)
/datum/definition_event/popup_cleared
	sync = TRUE
	var/window_id

/datum/definition_event/popup_cleared/New(window_id)
	src.window_id = window_id

/// Just before a datum's Destroy() is called: (force), at this point none of the other components chose to interrupt qdel and Destroy will be called
/datum/definition_event/qdeleting
	sync = TRUE
	var/force

/datum/definition_event/qdeleting/New(force)
	src.force = force

/// Non TG signals: from base of /datum/reagents/proc/handle_reactions(): (list/datum/decl/chemical_reaction)
/datum/definition_event/reagents_holder_reacted
	sync = TRUE
	var/chemical_reaction

/datum/definition_event/reagents_holder_reacted/New(chemical_reaction)
	src.chemical_reaction = chemical_reaction

/// Sent to the obj from base of [/datum/reagent/proc/touch_obj]: (datum/reagent/reagent, amount)
/datum/definition_event/reagent_expose_obj
	sync = TRUE
	/// The /datum/reagent touching the obj.
	var/reagent
	var/amount

/datum/definition_event/reagent_expose_obj/New(reagent, amount)
	src.reagent = reagent
	src.amount = amount

/// /datum/remote_view event that can be sent from the mob remote viewing, the viewed mob, or object being used to view to forcibly end all related remote viewing components
/datum/definition_event/remote_view_clear
	sync = TRUE

/// From the robot belly overlay provider: (belly_class, list/fullness_ref) Handlers may adjust fullness_ref[1].
/datum/definition_event/robot_belly_fullness
	sync = TRUE
	var/belly_class
	var/fullness_ref

/datum/definition_event/robot_belly_fullness/New(belly_class, fullness_ref)
	src.belly_class = belly_class
	src.fullness_ref = fullness_ref

/// From /mob/living/silicon/robot/proc/after_equip(): (obj/item/equipped_or_null)
/datum/definition_event/robot_equipment_changed
	sync = TRUE
	var/item

/datum/definition_event/robot_equipment_changed/New(item)
	src.item = item

/// Non TG signals: from the base of /mob/living/silicon/robot/ClickOn(): (var/atom/A, var/params)
/datum/definition_event/before/robot_item_attack
	accumulate = TRUE
	var/item
	var/user
	var/params

/datum/definition_event/before/robot_item_attack/New(item, user, params)
	src.item = item
	src.user = user
	src.params = params

/// From /mob/living/silicon/proc/laws_changed(): ()
/datum/definition_event/silicon_laws_changed
	sync = TRUE

/// From the ledger after a thing entered one of the holder's slots: (atom/movable/thing, slot_id)
/datum/definition_event/slot_inserted
	sync = TRUE
	var/thing
	var/slot_id

/datum/definition_event/slot_inserted/New(thing, slot_id)
	src.thing = thing
	src.slot_id = slot_id

/// From the ledger after a thing left one of the holder's slots: (atom/movable/thing, slot_id)
/datum/definition_event/slot_removed
	sync = TRUE
	var/thing
	var/slot_id

/datum/definition_event/slot_removed/New(thing, slot_id)
	src.thing = thing
	src.slot_id = slot_id

/// Called when a techweb design is researched (datum/design/researched_design, custom)
/datum/definition_event/techweb_add_design
	sync = TRUE
	var/researched_design
	var/custom

/datum/definition_event/techweb_add_design/New(researched_design, custom)
	src.researched_design = researched_design
	src.custom = custom

/// Called when a techweb design is removed (datum/design/removed_design, custom)
/datum/definition_event/techweb_remove_design
	sync = TRUE
	var/removed_design
	var/custom

/datum/definition_event/techweb_remove_design/New(removed_design, custom)
	src.removed_design = removed_design
	src.custom = custom

/// From /obj/machinery/computer/telescience/proc/doteleport(mob/user): (list/atom/movable/teleported_things, turf/target_turf, sending )
/datum/definition_event/telesci_teleport
	sync = TRUE
	var/teleported_things
	var/target_turf
	var/sending

/datum/definition_event/telesci_teleport/New(teleported_things, target_turf, sending)
	src.teleported_things = teleported_things
	src.target_turf = target_turf
	src.sending = sending

/// Window is fully visible and we can make fragile calls
/datum/definition_event/tgui_window_visible
	sync = TRUE
	var/client

/datum/definition_event/tgui_window_visible/New(client)
	src.client = client

/// From base of turf/ChangeTurf(): (path, list/new_baseturfs, flags, list/post_change_callbacks). `post_change_callbacks` is a list that handlers append rows list(owner, PROC_REF, with) to; each runs as after(owner, 0, PROC_REF, with = with + the new turf) after the turf has changed.
/datum/definition_event/turf_change
	sync = TRUE
	var/path
	var/new_baseturfs
	var/flags
	var/post_change_callbacks

/datum/definition_event/turf_change/New(path, new_baseturfs, flags, post_change_callbacks)
	src.path = path
	src.new_baseturfs = new_baseturfs
	src.flags = flags
	src.post_change_callbacks = post_change_callbacks

/// From /datum/scheduled_behaviour/footstep/prepare_step(): (list/steps)
/datum/definition_event/before/turf_prepare_step_sound
	accumulate = TRUE
	var/steps

/datum/definition_event/before/turf_prepare_step_sound/New(steps)
	src.steps = steps

/// From datum ui_act (usr, action)
/datum/definition_event/ui_act
	sync = TRUE
	var/usr_
	var/action

/datum/definition_event/ui_act/New(usr_, action)
	src.usr_ = usr_
	src.action = action

/datum/definition_event/unittest_data
	sync = TRUE
	var/data

/datum/definition_event/unittest_data/New(data)
	src.data = data

// ---------------------------------------------------------------- computed-name signals

/// Was SIGNAL_ADDTRAIT(trait): `trait` was gained (its first source added). Hook it and
/// test event.trait (hooks key on the event type, not the trait).
/datum/definition_event/trait_gained
	sync = TRUE
	var/trait

/datum/definition_event/trait_gained/New(trait)
	src.trait = trait

/// Was SIGNAL_REMOVETRAIT(trait): `trait` was lost (its last source removed).
/datum/definition_event/trait_lost
	sync = TRUE
	var/trait

/datum/definition_event/trait_lost/New(trait)
	src.trait = trait

/// Was COMSIG_TOOL_ATOM_ACTED_PRIMARY(quality) / _SECONDARY(quality), sent on the tool
/// after it acted on `target`.
/datum/definition_event/tool_atom_acted
	sync = TRUE
	var/tool_quality
	var/secondary
	var/target
	var/user
	var/modifiers

/datum/definition_event/tool_atom_acted/New(tool_quality, secondary, target, user, modifiers)
	src.tool_quality = tool_quality
	src.secondary = secondary
	src.target = target
	src.user = user
	src.modifiers = modifiers
