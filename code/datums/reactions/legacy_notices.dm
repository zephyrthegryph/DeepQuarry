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

/// From base of atom/Bumped(): (/atom/movable) (the one that gets bumped)
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

/// From base of atom/movable/Bump(): (/atom)
/datum/notice/movable_bump
	var/atom

/datum/notice/movable_bump/fill(atom)
	src.atom = atom

/// From base of atom/movable/on_changed_z_level(): (turf/old_turf, turf/new_turf, same_z_layer)
/datum/notice/movable_z_changed
	var/old_z
	var/new_z

/datum/notice/movable_z_changed/fill(old_z, new_z)
	src.old_z = old_z
	src.new_z = new_z

/// Non TG signals: from the base of /mob/living/silicon/robot/ClickOn(): (var/atom/A, var/params)
/datum/notice/robot_item_attack
	var/item
	var/user
	var/params

/datum/notice/robot_item_attack/fill(item, user, params)
	src.item = item
	src.user = user
	src.params = params

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

/// The `material_facts_changed` occurrence (it was an om event).
/datum/notice/material_facts_changed

/// The `material_surgery` occurrence (it was an om event).
/datum/notice/material_surgery
	var/patient
	var/zone
	var/success

/datum/notice/material_surgery/fill(patient, zone, success)
	src.patient = patient
	src.zone = zone
	src.success = success

/// Sent when a mob/login() finishes: (client)
/datum/notice/mob_client_login
	var/client

/datum/notice/mob_client_login/fill(client)
	src.client = client

/// From base of mob/death(): (gibbed)
/datum/notice/mob_death
	var/gibbed

/datum/notice/mob_death/fill(gibbed)
	src.gibbed = gibbed

/// From /proc/domutcheck(): ()
/datum/notice/mob_dna_mutation

/// A mob has just equipped an item. Called on [/mob] from base of [/obj/item/equipped()]: (/obj/item/equipped_item, slot)
/datum/notice/mob_equipped_item
	var/equipped_item
	var/slot

/datum/notice/mob_equipped_item/fill(equipped_item, slot)
	src.equipped_item = equipped_item
	src.slot = slot

/// From /datum/action/Grant(): (datum/action)
/datum/notice/mob_granted_action
	var/action

/datum/notice/mob_granted_action/fill(action)
	src.action = action

/// From base of /mob/Login(): ()
/datum/notice/mob_login

/// From base of /mob/Logout(): ()
/datum/notice/mob_logout

/// A condition was attached, removed, or crossed a clinically meaningful threshold.
/datum/notice/mob_medical_issues_changed

/// From mind/transfer_to. Sent to the receiving mob.
/datum/notice/mob_mind_transferred_into
	var/old_character

/datum/notice/mob_mind_transferred_into/fill(old_character)
	src.old_character = old_character

/// From mind/transfer_from. Sent to the mob the mind is being transferred out of.
/datum/notice/mob_mind_transferred_out_of
	var/new_character

/datum/notice/mob_mind_transferred_out_of/fill(new_character)
	src.new_character = new_character

/// From /datum/action/Remove(): (datum/action)
/datum/notice/mob_removed_action
	var/action

/datum/notice/mob_removed_action/fill(action)
	src.action = action

/// From base of /mob/proc/reset_perspective() : ()
/datum/notice/mob_reset_perspective

/// From base of mob/set_stat(): (new_stat, old_stat)
/datum/notice/mob_statchange
	var/new_stat
	var/old_stat

/datum/notice/mob_statchange/fill(new_stat, old_stat)
	src.new_stat = new_stat
	src.old_stat = old_stat

/// A mob has just unequipped an item.
/datum/notice/mob_unequipped_item
	var/item
	var/target_

/datum/notice/mob_unequipped_item/fill(item, target_)
	src.item = item
	src.target_ = target_

/// From base of atom/movable/Moved(): (/atom, newloc, direction)
/datum/notice/movable_attempted_move
	var/old_loc
	var/new_loc

/datum/notice/movable_attempted_move/fill(old_loc, new_loc)
	src.old_loc = old_loc
	src.new_loc = new_loc

/// From base of atom/movable/throw_impact() after confirming a hit: (/atom/hit_atom, /datum/thrownthing/throwingdatum)
/datum/notice/movable_impact
	var/hit_atom
	var/throwingdatum

/datum/notice/movable_impact/fill(hit_atom, throwingdatum)
	src.hit_atom = hit_atom
	src.throwingdatum = throwingdatum

/// From /datum/controller/subsystem/motion_tracker/notice() (source_atom,/turf/echo_turf_location)
/datum/notice/movable_motiontracker
	var/source_
	var/echo_turf_location

/datum/notice/movable_motiontracker/fill(source_, echo_turf_location)
	src.source_ = source_
	src.echo_turf_location = echo_turf_location

/// Notification: the movable changed loc.
/datum/notice/moved
	var/old_loc
	var/direction
	var/forced

/datum/notice/moved/fill(old_loc, direction, forced)
	src.old_loc = old_loc
	src.direction = direction
	src.forced = forced

/// The `moved_down_stairs` occurrence (it was an om event).
/datum/notice/moved_down_stairs
	var/old_loc

/datum/notice/moved_down_stairs/fill(old_loc)
	src.old_loc = old_loc

/// /obj signals from base of obj/deconstruct(): (disassembled)
/datum/notice/obj_deconstruct
	var/disassembled

/datum/notice/obj_deconstruct/fill(disassembled)
	src.disassembled = disassembled

/// The `observer_apc` occurrence (it was an om event).
/datum/notice/observer_apc

/// The `observer_globalmoved` occurrence (it was an om event).
/datum/notice/observer_globalmoved

/// The `observer_shuttle_added` occurrence (it was an om event).
/datum/notice/observer_shuttle_added
	var/shuttle

/datum/notice/observer_shuttle_added/fill(shuttle)
	src.shuttle = shuttle

/// The `observer_shuttle_moved` occurrence (it was an om event).
/datum/notice/observer_shuttle_moved
	var/old_location
	var/destination

/datum/notice/observer_shuttle_moved/fill(old_location, destination)
	src.old_location = old_location
	src.destination = destination

/// The `observer_shuttle_pre_move` occurrence (it was an om event).
/datum/notice/observer_shuttle_pre_move
	var/old_location
	var/destination

/datum/notice/observer_shuttle_pre_move/fill(old_location, destination)
	src.old_location = old_location
	src.destination = destination

/// The `observer_turf_entered` occurrence (it was an om event).
/datum/notice/observer_turf_entered
	var/arrived
	var/old_loc

/datum/notice/observer_turf_entered/fill(arrived, old_loc)
	src.arrived = arrived
	src.old_loc = old_loc

/// The `picked_up_item` occurrence (it was an om event).
/datum/notice/picked_up_item
	var/item

/datum/notice/picked_up_item/fill(item)
	src.item = item

/// From /client/proc/handle_popup_close() : (window_id)
/datum/notice/popup_cleared
	var/window_id

/datum/notice/popup_cleared/fill(window_id)
	src.window_id = window_id

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

/// /datum/remote_view event that can be sent from the mob remote viewing, the viewed mob, or object being used to view to forcibly end all related remote viewing components
/datum/notice/remote_view_clear

/// From the robot belly overlay provider: (belly_class, list/fullness_ref) Handlers may adjust fullness_ref[1].
/datum/notice/robot_belly_fullness
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)
	var/belly_class
	var/fullness_ref

/datum/notice/robot_belly_fullness/fill(belly_class, fullness_ref)
	src.belly_class = belly_class
	src.fullness_ref = fullness_ref

/// From /mob/living/silicon/robot/proc/after_equip(): (obj/item/equipped_or_null)
/datum/notice/robot_equipment_changed
	var/item

/datum/notice/robot_equipment_changed/fill(item)
	src.item = item

/// From /mob/living/silicon/proc/laws_changed(): ()
/datum/notice/silicon_laws_changed

/// The `stun_effect` occurrence (it was an om event).
/datum/notice/stun_effect
	var/stun_amount
	var/agony_amount
	var/def_zone
	var/used_weapon
	var/electric

/datum/notice/stun_effect/fill(stun_amount, agony_amount, def_zone, used_weapon, electric)
	src.stun_amount = stun_amount
	src.agony_amount = agony_amount
	src.def_zone = def_zone
	src.used_weapon = used_weapon
	src.electric = electric

/// Called when a techweb design is researched (datum/design/researched_design, custom)
/datum/notice/techweb_add_design
	var/researched_design
	var/custom

/datum/notice/techweb_add_design/fill(researched_design, custom)
	src.researched_design = researched_design
	src.custom = custom

/// Called when a techweb design is removed (datum/design/removed_design, custom)
/datum/notice/techweb_remove_design
	var/removed_design
	var/custom

/datum/notice/techweb_remove_design/fill(removed_design, custom)
	src.removed_design = removed_design
	src.custom = custom

/// From /obj/machinery/computer/telescience/proc/doteleport(mob/user): (list/atom/movable/teleported_things, turf/target_turf, sending )
/datum/notice/telesci_teleport
	var/teleported_things
	var/target_turf
	var/sending

/datum/notice/telesci_teleport/fill(teleported_things, target_turf, sending)
	src.teleported_things = teleported_things
	src.target_turf = target_turf
	src.sending = sending

/// Window is fully visible and we can make fragile calls
/datum/notice/tgui_window_visible
	var/client

/datum/notice/tgui_window_visible/fill(client)
	src.client = client

/// Was COMSIG_TOOL_ATOM_ACTED_PRIMARY(quality) / _SECONDARY(quality), sent on the tool
/// after it acted on `target`.
/datum/notice/tool_atom_acted
	var/tool_quality
	var/secondary
	var/target_
	var/user
	var/modifiers

/datum/notice/tool_atom_acted/fill(tool_quality, secondary, target_, user, modifiers)
	src.tool_quality = tool_quality
	src.secondary = secondary
	src.target_ = target_
	src.user = user
	src.modifiers = modifiers

/// Was SIGNAL_ADDTRAIT(trait): `trait` was gained (its first source added). Hook it and
/// test event.trait (hooks key on the event type, not the trait).
/datum/notice/trait_gained
	var/trait

/datum/notice/trait_gained/fill(trait)
	src.trait = trait

/// Was SIGNAL_REMOVETRAIT(trait): `trait` was lost (its last source removed).
/datum/notice/trait_lost
	var/trait

/datum/notice/trait_lost/fill(trait)
	src.trait = trait

/// From base of turf/ChangeTurf(): (path, list/new_baseturfs, flags, list/post_change_callbacks). `post_change_callbacks` is a list that handlers append rows list(owner, PROC_REF, with) to; each runs as after(owner, 0, PROC_REF, with = with + the new turf) after the turf has changed.
/datum/notice/turf_change
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)
	var/path
	var/new_baseturfs
	var/flags
	var/post_change_callbacks

/datum/notice/turf_change/fill(path, new_baseturfs, flags, post_change_callbacks)
	src.path = path
	src.new_baseturfs = new_baseturfs
	src.flags = flags
	src.post_change_callbacks = post_change_callbacks

/// From datum ui_act (usr, action)
/datum/notice/ui_act
	var/usr_
	var/action

/datum/notice/ui_act/fill(usr_, action)
	src.usr_ = usr_
	src.action = action

/// The `unittest_data` occurrence (it was an om event).
/datum/notice/unittest_data
	var/data_

/datum/notice/unittest_data/fill(data_)
	src.data_ = data_

/// Called after an explosion happened : (epicenter, devastation_range, heavy_impact_range, light_impact_range, took, orig_dev_range, orig_heavy_range, orig_light_range)
/datum/notice/world_explosion
	var/epicenter
	var/devastation_range
	var/heavy_impact_range
	var/light_impact_range
	var/took

/datum/notice/world_explosion/fill(epicenter, devastation_range, heavy_impact_range, light_impact_range, took)
	src.epicenter = epicenter
	src.devastation_range = devastation_range
	src.heavy_impact_range = heavy_impact_range
	src.light_impact_range = light_impact_range
	src.took = took

/// Called when a ghost or phaser is captured by a ghosttrap: (mob/passing_entity)
/datum/notice/world_ghost_captured
	var/passing_entity

/datum/notice/world_ghost_captured/fill(passing_entity)
	src.passing_entity = passing_entity

/// Called from base of /mob/Initialise : (mob)
/datum/notice/world_mob_created
	var/mob

/datum/notice/world_mob_created/fill(mob)
	src.mob = mob

/// Mob died somewhere : (mob/living, gibbed)
/datum/notice/world_mob_death
	var/living
	var/gibbed

/datum/notice/world_mob_death/fill(living, gibbed)
	src.living = living
	src.gibbed = gibbed

/// Payment account status changed /obj/machinery/account_database/tgui_act() : (datum/money_account/account)
/datum/notice/world_payment_account_status
	var/account

/datum/notice/world_payment_account_status/fill(account)
	src.account = account

/// Shuttle Comsigs Supply shuttle selling, before all items are sold, called by /datum/controller/subsystem/supply/proc/sell() : (/list/area/supply_shuttle_areas)
/datum/notice/world_supply_shuttle_depart
	var/supply_shuttle_areas

/datum/notice/world_supply_shuttle_depart/fill(supply_shuttle_areas)
	src.supply_shuttle_areas = supply_shuttle_areas

/// Called when a shadow wright passes by a ghosttrap: (obj/effect/shadow_wight)
/datum/notice/world_wight_captured
	var/shadow_wight

/datum/notice/world_wight_captured/fill(shadow_wight)
	src.shadow_wight = shadow_wight
