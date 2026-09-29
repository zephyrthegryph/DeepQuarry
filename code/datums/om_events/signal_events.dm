// Events that replaced the DCS signals (object_model_core.md sec 10,
// signal_migration_map.md). One type per former COMSIG_*, payload vars named after
// the signal's documented arguments. Plain events are `sync`: delivered at once to
// the entity's behaviours and then to its hooks (om_hook), with numeric returns ORed
// into `result`, which om_emit() returns. before/ events are `accumulate`: the same,
// for events whose sender reads the result (the former COMPONENT_* return bits, or
// EVENT_VETO). Send with OM_EMIT(entity, /datum/om/event/x, args...).
// Keep domain-specific events next to their domain when you touch them.

/// From /datum/affliction/proc/set_severity(), sent to the owning mob: (datum/affliction/affliction, old_severity)
/datum/om/event/affliction_severity_changed
	sync = TRUE
	var/affliction
	var/old_severity

/datum/om/event/affliction_severity_changed/New(affliction, old_severity)
	src.affliction = affliction
	src.old_severity = old_severity

/// From /obj/machinery/computer/arcade/prizevend(mob/user, prizes = 1)
/datum/om/event/arcade_prizevend
	sync = TRUE
	var/user

/datum/om/event/arcade_prizevend/New(user)
	src.user = user

/// /atom signals from SSatoms InitAtom - Only if the  atom was not deleted or failed initialization from SSatoms InitAtom - Only if the  atom was not deleted or failed initialization and has a loc
/datum/om/event/atom_after_successful_initialized_on
	sync = TRUE
	var/created
	var/mapload

/datum/om/event/atom_after_successful_initialized_on/New(created, mapload)
	src.created = created
	src.mapload = mapload

/// From base of atom/bullet_act(): (/obj/proj, def_zone, piercing_hit, blocked)
/datum/om/event/before/atom_bullet_act
	accumulate = TRUE
	var/projectile
	var/def_zone

/datum/om/event/before/atom_bullet_act/New(projectile, def_zone)
	src.projectile = projectile
	src.def_zone = def_zone

/// From base of atom/Bumped(): (/atom/movable) (the one that gets bumped)
/datum/om/event/atom_bumped
	sync = TRUE
	var/bumped

/datum/om/event/atom_bumped/New(bumped)
	src.bumped = bumped

/// From base of atom/setDir(): (old_dir, new_dir). Called before the direction changes.
/datum/om/event/atom_dir_change
	sync = TRUE
	var/old_dir
	var/new_dir

/datum/om/event/atom_dir_change/New(old_dir, new_dir)
	src.old_dir = old_dir
	src.new_dir = new_dir

/// From base of atom/emp_act(severity): (severity, protection)
/datum/om/event/atom_emp_act
	sync = TRUE
	var/severity
	var/protection

/datum/om/event/atom_emp_act/New(severity, protection)
	src.severity = severity
	src.protection = protection

/// From base of atom/Entered(): (atom/movable/arrived, atom/old_loc, list/atom/old_locs)
/datum/om/event/atom_entered
	sync = TRUE
	var/arrived
	var/old_loc

/datum/om/event/atom_entered/New(arrived, old_loc)
	src.arrived = arrived
	src.old_loc = old_loc

/// Sent from the atom that just Entered src. From base of atom/Entered(): (/atom/destination, atom/old_loc, list/atom/old_locs)
/datum/om/event/atom_entering
	sync = TRUE
	var/destination
	var/old_loc

/datum/om/event/atom_entering/New(destination, old_loc)
	src.destination = destination
	src.old_loc = old_loc

/// From base of atom/Exited(): `gone` left the atom for `new_loc`.
/datum/om/event/atom_exited
	sync = TRUE
	var/gone
	var/new_loc

/datum/om/event/atom_exited/New(gone, new_loc)
	src.gone = gone
	src.new_loc = new_loc

/// From base of atom/attack_basic_mob(): (/mob/user) from base of [/atom/proc/extinguish]
/datum/om/event/before/atom_extinguish
	accumulate = TRUE

/// From the [EX_ACT] wrapper macro: (severity, target)
/datum/om/event/before/atom_ex_act
	accumulate = TRUE
	var/severity
	var/target

/datum/om/event/before/atom_ex_act/New(severity, target)
	src.severity = severity
	src.target = target

/// From base of atom/fire_act(): (exposed_temperature, exposed_volume)
/datum/om/event/atom_fire_act
	sync = TRUE
	var/exposed_temperature
	var/exposed_volume

/datum/om/event/atom_fire_act/New(exposed_temperature, exposed_volume)
	src.exposed_temperature = exposed_temperature
	src.exposed_volume = exposed_volume

/// From base of atom/emp_act(severity): (severity). return EMP protection flags
/datum/om/event/before/atom_pre_emp_act
	accumulate = TRUE
	var/severity

/datum/om/event/before/atom_pre_emp_act/New(severity)
	src.severity = severity

/// From internal loop in /atom/proc/propagate_radiation_pulse: (atom/pulse_source)
/datum/om/event/atom_propagate_rad_pulse
	sync = TRUE
	var/pulse_source

/datum/om/event/atom_propagate_rad_pulse/New(pulse_source)
	src.pulse_source = pulse_source

/// From base of [/atom/proc/take_damage]: (damage_amount, damage_type, damage_flag, sound_effect, attack_dir, aurmor_penetration)
/datum/om/event/before/atom_take_damage
	accumulate = TRUE
	var/damage_amount
	var/damage_type
	var/damage_flag
	var/sound_effect
	var/attack_dir
	var/aurmor_penetration

/datum/om/event/before/atom_take_damage/New(damage_amount, damage_type, damage_flag, sound_effect, attack_dir, aurmor_penetration)
	src.damage_amount = damage_amount
	src.damage_type = damage_type
	src.damage_flag = damage_flag
	src.sound_effect = sound_effect
	src.attack_dir = attack_dir
	src.aurmor_penetration = aurmor_penetration

/// Called right after the atom changes the value of light_color to a different one, from base of [/atom/proc/set_light_color]: (old_color)
/datum/om/event/atom_update_light_color
	sync = TRUE
	var/old_color

/datum/om/event/atom_update_light_color/New(old_color)
	src.old_color = old_color

/// Called right after the atom changes the value of light_flags to a different one, from base of [/atom/proc/set_light_flags]: (old_flags)
/datum/om/event/atom_update_light_flags
	sync = TRUE
	var/old_flags

/datum/om/event/atom_update_light_flags/New(old_flags)
	src.old_flags = old_flags

/// Called right after the atom changes the value of light_on to a different one, from base of [/atom/proc/set_light_on]: (old_value)
/datum/om/event/atom_update_light_on
	sync = TRUE
	var/old_value

/datum/om/event/atom_update_light_on/New(old_value)
	src.old_value = old_value

/// Lighting: Called right after the atom changes the value of light_power to a different one, from base of [/atom/proc/set_light_power]: (old_power)
/datum/om/event/atom_update_light_power
	sync = TRUE
	var/old_power

/datum/om/event/atom_update_light_power/New(old_power)
	src.old_power = old_power

/// Called right after the atom changes the value of light_range to a different one, from base of [/atom/proc/set_light_range]: (old_range)
/datum/om/event/atom_update_light_range
	sync = TRUE
	var/old_range

/datum/om/event/atom_update_light_range/New(old_range)
	src.old_range = old_range

/// From base of atom/used_in_craft(): (atom/result)
/datum/om/event/atom_used_in_craft
	sync = TRUE
	var/result_

/datum/om/event/atom_used_in_craft/New(result_)
	src.result_ = result_

/// From base of /obj/item/autopsy_scanner/do_surgery() : (mob/user, mob/target)
/datum/om/event/autopsy_performed
	sync = TRUE
	var/user
	var/target

/datum/om/event/autopsy_performed/New(user, target)
	src.user = user
	src.target = target

/// From /obj/belly/HandleBellyReagents() and /obj/belly/update_internal_overlay()
/datum/om/event/before/belly_update_vore_fx
	accumulate = TRUE
	var/volume

/datum/om/event/before/belly_update_vore_fx/New(volume)
	src.volume = volume

/// From /datum/body/add_affliction() and remove_affliction(): (datum/affliction/affliction, added)
/datum/om/event/body_afflictions_changed
	sync = TRUE
	var/affliction
	var/added

/datum/om/event/body_afflictions_changed/New(affliction, added)
	src.affliction = affliction
	src.added = added

/// From /datum/body/proc/adopt_subtree(), sent to the owning mob once per part that joined it: (obj/item/organ/part)
/datum/om/event/body_part_attached
	sync = TRUE
	var/part

/datum/om/event/body_part_attached/New(part)
	src.part = part

/// From /datum/body/proc/release_subtree(), sent to the owning mob once per part that left it: (obj/item/organ/part)
/datum/om/event/body_part_detached
	sync = TRUE
	var/part

/datum/om/event/body_part_detached/New(part)
	src.part = part

/// From base of atom/Click(): (atom/location, control, params, mob/user)
/datum/om/event/click
	sync = TRUE
	var/location
	var/control
	var/params
	var/user

/datum/om/event/click/New(location, control, params, user)
	src.location = location
	src.control = control
	src.params = params
	src.user = user

/// #define COMSIG_MOB_CANCEL_CLICKON (1<<0) //shared with other forms of click, this is so you're aware it exists here too. from base of atom/click_alt(): (/mob)
/datum/om/event/before/click_alt
	accumulate = TRUE
	var/mob

/datum/om/event/before/click_alt/New(mob)
	src.mob = mob

/// From base of client/Click(): (atom/target, atom/location, control, params, mob/user)
/datum/om/event/client_click
	sync = TRUE
	var/target
	var/location
	var/control
	var/params
	var/user

/datum/om/event/client_click/New(target, location, control, params, user)
	src.target = target
	src.location = location
	src.control = control
	src.params = params
	src.user = user

/// Called when a disposal connected object flushes its contents into the disposal pipe network
/datum/om/event/before/disposal_flush
	accumulate = TRUE
	var/items
	var/gas

/datum/om/event/before/disposal_flush/New(items, gas)
	src.items = items
	src.gas = gas

/// Called when a disposal connected object attempts to link to a trunk: (/obj/structure/disposalpipe/trunk)
/datum/om/event/disposal_link
	sync = TRUE
	var/trunk

/datum/om/event/disposal_link/New(trunk)
	src.trunk = trunk

/// Called when a disposal connected object recieves an object from it's connected trunk
/datum/om/event/disposal_receive
	sync = TRUE
	var/items
	var/gas

/datum/om/event/disposal_receive/New(items, gas)
	src.items = items
	src.gas = gas

/// Called when a disposal trunk attempts to send a packet, to be recieved by an atom with a disposal network connection component.
/datum/om/event/before/disposal_send
	accumulate = TRUE
	var/holder

/datum/om/event/before/disposal_send/New(holder)
	src.holder = holder

/// Called when a disposal connected object should unlink from a trunk it's attached to.
/datum/om/event/disposal_unlink
	sync = TRUE

/// Sent from /proc/do_after if someone starts a do_after action bar.
/datum/om/event/do_after_began
	sync = TRUE

/// Sent from /proc/do_after once a do_after action completes, whether via the bar filling or via interruption.
/datum/om/event/do_after_ended
	sync = TRUE

/datum/om/event/dqai_ally_distress
	sync = TRUE
	var/ally
	var/target

/datum/om/event/dqai_ally_distress/New(ally, target)
	src.ally = ally
	src.target = target

/// --------------------------------------------------------------------------- Signals emitted on the mob by the brain framework. Behaviors can subscribe to these via their eval_triggers list to re-evaluate only when relevant. ---------------------------------------------------------------------------
/datum/om/event/dqai_damage_taken
	sync = TRUE
	var/amount
	var/injury_kind
	var/attacker

/datum/om/event/dqai_damage_taken/New(amount, injury_kind, attacker)
	src.amount = amount
	src.injury_kind = injury_kind
	src.attacker = attacker

/datum/om/event/dqai_target_changed
	sync = TRUE
	var/new_target
	var/old_target

/datum/om/event/dqai_target_changed/New(new_target, old_target)
	src.new_target = new_target
	src.old_target = old_target

/datum/om/event/dqai_target_lost
	sync = TRUE
	var/old_target

/datum/om/event/dqai_target_lost/New(old_target)
	src.old_target = old_target

/// Fired when scanning something with a geiger counter. (mob/user, obj/item/geiger_counter/geiger_counter)
/datum/om/event/before/geiger_counter_scan
	accumulate = TRUE
	var/user
	var/geiger_counter

/datum/om/event/before/geiger_counter_scan/New(user, geiger_counter)
	src.user = user
	src.geiger_counter = geiger_counter

/// Signal that gets sent when a ghost query is completed
/datum/om/event/ghost_query_complete
	sync = TRUE

/// Base /obj/item/autopsy_scanner/do_surgery() : (mob/user, mob/target)
/datum/om/event/world_autopsy_performed
	sync = TRUE
	var/user
	var/target

/datum/om/event/world_autopsy_performed/New(user, target)
	src.user = user
	src.target = target

/// NON TG Signals: brain removed from body, called by /obj/item/organ/internal/brain/proc/transfer_identity() : (mob/living/carbon/brain/brainmob)
/datum/om/event/world_brain_removed
	sync = TRUE
	var/brainmob

/datum/om/event/world_brain_removed/New(brainmob)
	src.brainmob = brainmob

/// Called after an explosion happened : (epicenter, devastation_range, heavy_impact_range, light_impact_range, took, orig_dev_range, orig_heavy_range, orig_light_range)
/datum/om/event/world_explosion
	sync = TRUE
	var/epicenter
	var/devastation_range
	var/heavy_impact_range
	var/light_impact_range
	var/took

/datum/om/event/world_explosion/New(epicenter, devastation_range, heavy_impact_range, light_impact_range, took)
	src.epicenter = epicenter
	src.devastation_range = devastation_range
	src.heavy_impact_range = heavy_impact_range
	src.light_impact_range = light_impact_range
	src.took = took

/// Called when a ghost or phaser is captured by a ghosttrap: (mob/passing_entity)
/datum/om/event/world_ghost_captured
	sync = TRUE
	var/passing_entity

/datum/om/event/world_ghost_captured/New(passing_entity)
	src.passing_entity = passing_entity

/// Called from base of /mob/Initialise : (mob)
/datum/om/event/world_mob_created
	sync = TRUE
	var/mob

/datum/om/event/world_mob_created/New(mob)
	src.mob = mob

/// Mob died somewhere : (mob/living, gibbed)
/datum/om/event/world_mob_death
	sync = TRUE
	var/living
	var/gibbed

/datum/om/event/world_mob_death/New(living, gibbed)
	src.living = living
	src.gibbed = gibbed

/// Payment account status changed /obj/machinery/account_database/tgui_act() : (datum/money_account/account)
/datum/om/event/world_payment_account_status
	sync = TRUE
	var/account

/datum/om/event/world_payment_account_status/New(account)
	src.account = account

/// Called by datum/cinematic/play() : (datum/cinematic/new_cinematic)
/datum/om/event/before/world_play_cinematic
	accumulate = TRUE
	var/new_cinematic

/datum/om/event/before/world_play_cinematic/New(new_cinematic)
	src.new_cinematic = new_cinematic

/// Shuttle Comsigs Supply shuttle selling, before all items are sold, called by /datum/controller/subsystem/supply/proc/sell() : (/list/area/supply_shuttle_areas)
/datum/om/event/world_supply_shuttle_depart
	sync = TRUE
	var/supply_shuttle_areas

/datum/om/event/world_supply_shuttle_depart/New(supply_shuttle_areas)
	src.supply_shuttle_areas = supply_shuttle_areas

/// Called when a shadow wright passes by a ghosttrap: (obj/effect/shadow_wight)
/datum/om/event/world_wight_captured
	sync = TRUE
	var/shadow_wight

/datum/om/event/world_wight_captured/New(shadow_wight)
	src.shadow_wight = shadow_wight

/// Non TG signals: From the disabilities life system.
/datum/om/event/handle_disabilities
	sync = TRUE

/// From the mutations life system
/datum/om/event/before/handle_mutations
	accumulate = TRUE

/// From the radiation life system
/datum/om/event/before/handle_radiation
	accumulate = TRUE

/// Hose Connector Component
/datum/om/event/hose_forcepump
	sync = TRUE

/// From /datum/species/handle_fire. Called when the human is set on fire and burning clothes and stuff
/datum/om/event/human_burning
	sync = TRUE

/// NON TG Signals When the mob's dna and species have been fully applied
/datum/om/event/human_dna_finalized
	sync = TRUE

/// From /mob/living/carbon/human/GetAltName(): (list/name_data) - name_data[1] contains the alt name
/datum/om/event/before/human_get_alt_name
	accumulate = TRUE
	var/name_data

/datum/om/event/before/human_get_alt_name/New(name_data)
	src.name_data = name_data

/// From /mob/living/carbon/human/get_visible_name(), not sent if the mob has TRAIT_UNKNOWN: (identity)
/datum/om/event/before/human_get_visible_name
	accumulate = TRUE
	var/identity

/datum/om/event/before/human_get_visible_name/New(identity)
	src.identity = identity

/// From /mob/living/carbon/human/GetVoice(): (list/voice_data) - voice_data[1] contains the voice name
/datum/om/event/before/human_get_voice
	accumulate = TRUE
	var/voice_data

/datum/om/event/before/human_get_voice/New(voice_data)
	src.voice_data = voice_data

/// Sent to the instrument when a song stops playing
/datum/om/event/instrument_end
	sync = TRUE
	var/finished

/datum/om/event/instrument_end/New(finished)
	src.finished = finished

/// Sent to the instrument when a song starts playing: (datum/starting_song, atom/player)
/datum/om/event/instrument_start
	sync = TRUE
	var/starting_song
	var/player

/datum/om/event/instrument_start/New(starting_song, player)
	src.starting_song = starting_song
	src.player = player

/// From the radiation subsystem, called before a potential irradiation. This does not guarantee radiation can reach or will succeed, but merely that there's a radiation source within range. (datum/radiation_pulse_information/pulse_information, insulation_to_target)
/datum/om/event/before/in_range_of_irradiation
	accumulate = TRUE
	var/pulse_information
	var/insulation_to_target

/datum/om/event/before/in_range_of_irradiation/New(pulse_information, insulation_to_target)
	src.pulse_information = pulse_information
	src.insulation_to_target = insulation_to_target

/// From base of /obj/item/attack(): (mob/living, mob/living, list/modifiers, list/attack_modifiers)
/datum/om/event/item_attack
	sync = TRUE
	var/target
	var/user
	var/target_zone

/datum/om/event/item_attack/New(target, user, target_zone)
	src.target = target
	src.user = user
	src.target_zone = target_zone

/// From base of obj/item/dropped(): (mob/user)
/datum/om/event/item_dropped
	sync = TRUE
	var/user

/datum/om/event/item_dropped/New(user)
	src.user = user

/// From base of obj/item/equipped(): (mob/equipper, slot)
/datum/om/event/item_equipped
	sync = TRUE
	var/equipper
	var/slot

/datum/om/event/item_equipped/New(equipper, slot)
	src.equipper = equipper
	src.slot = slot

/// From base of obj/item/pickup(): (/mob/taker)
/datum/om/event/item_pickup
	sync = TRUE
	var/taker

/datum/om/event/item_pickup/New(taker)
	src.taker = taker

/// From base of obj/item/pre_attack(): (atom/target, mob/user, list/modifiers, list/attack_modifiers)
/datum/om/event/before/item_pre_attack
	accumulate = TRUE
	var/target
	var/user
	var/params

/datum/om/event/before/item_pre_attack/New(target, user, params)
	src.target = target
	src.user = user
	src.params = params

/// Sent from [atom/proc/item_interaction], when this atom is used as a tool and an event occurs
/datum/om/event/item_tool_acted
	sync = TRUE
	var/target
	var/user
	var/tool_quality
	var/modifiers

/datum/om/event/item_tool_acted/New(target, user, tool_quality, modifiers)
	src.target = target
	src.user = user
	src.tool_quality = tool_quality
	src.modifiers = modifiers

/// From end of revival_healing_action(): ()
/datum/om/event/living_aheal
	sync = TRUE

/// From /datum/body/evaluate_status(), before death/unconsciousness is applied: ()
/datum/om/event/before/living_body_status
	accumulate = TRUE

/// From /mob/proc/death(), once per death, after EVERY death side effect (on_death(), HUD refresh, antag win check): (gibbed). Never sent on a repeated or replaced death. Hang end-of-death work (delete_on_death) here; death() itself never deletes the mob.
/datum/om/event/living_death_final
	sync = TRUE
	var/gibbed

/datum/om/event/living_death_final/New(gibbed)
	src.gibbed = gibbed

/// From base of /mob/living/proc/injure(), before mitigation: (kind, list/amount_ref, zone, atom/source, flags). amount_ref[1] may be modified.
/datum/om/event/before/living_injure
	accumulate = TRUE
	var/kind
	var/amount_ref
	var/zone
	var/source
	var/flags

/datum/om/event/before/living_injure/New(kind, amount_ref, zone, source, flags)
	src.kind = kind
	src.amount_ref = amount_ref
	src.zone = zone
	src.source = source
	src.flags = flags

/// From base of /mob/living/proc/injure(), after the injury applied: (kind, applied, zone, atom/source, flags)
/datum/om/event/living_injured
	sync = TRUE
	var/kind
	var/applied
	var/zone
	var/source
	var/flags

/datum/om/event/living_injured/New(kind, applied, zone, source, flags)
	src.kind = kind
	src.applied = applied
	src.zone = zone
	src.source = source
	src.flags = flags

/// From /mob/living/proc/injure() once mitigation is done, when something listens or the injury trace is on: (incoming_kind, landed_kind, list/stages, zone, atom/source, flags). Each stage is list(INJURY_STAGE_*, amount_in, amount_out, detail).
/datum/om/event/living_injury_explained
	sync = TRUE
	var/incoming_kind
	var/landed_kind
	var/stages
	var/zone
	var/source
	var/flags

/datum/om/event/living_injury_explained/New(incoming_kind, landed_kind, stages, zone, source, flags)
	src.incoming_kind = incoming_kind
	src.landed_kind = landed_kind
	src.stages = stages
	src.zone = zone
	src.source = source
	src.flags = flags

/// From base of /mob/living/proc/apply_effect(var/effect = 0,var/effecttype = STUN, var/blocked = 0, var/check_protection = 1, rad_protection)
/datum/om/event/before/living_irradiate_effect
	accumulate = TRUE
	var/effect
	var/stun
	var/blocked
	var/check_protection
	var/rad_protection

/datum/om/event/before/living_irradiate_effect/New(effect, stun, blocked, check_protection, rad_protection)
	src.effect = effect
	src.stun = stun
	src.blocked = blocked
	src.check_protection = check_protection
	src.rad_protection = rad_protection

/// From base of /mob/living/regenerate_limbs(): (noheal, excluded_limbs)
/datum/om/event/living_regenerate_limbs
	sync = TRUE
	var/noheal
	var/excluded_limbs

/datum/om/event/living_regenerate_limbs/New(noheal, excluded_limbs)
	src.noheal = noheal
	src.excluded_limbs = excluded_limbs

/// From /mob/living/proc/return_from_death(), after the mob is alive again: (datum/source, reason)
/datum/om/event/living_revived
	sync = TRUE
	var/source
	var/reason

/datum/om/event/living_revived/New(source, reason)
	src.source = source
	src.reason = reason

/// From /mob/living/proc/injure(), mitigation stage 2 (energy shields), after armour: (kind, list/amount_ref, zone, atom/source, flags). Shields scale amount_ref[1].
/datum/om/event/living_shield_injury
	sync = TRUE
	var/kind
	var/amount_ref
	var/zone
	var/source
	var/flags

/datum/om/event/living_shield_injury/New(kind, amount_ref, zone, source, flags)
	src.kind = kind
	src.amount_ref = amount_ref
	src.zone = zone
	src.source = source
	src.flags = flags

/// Before a blindness increase (amount)
/datum/om/event/living_status_blind
	sync = TRUE
	var/amount

/datum/om/event/living_status_blind/New(amount)
	src.amount = amount

/// Before a paralysis increase (amount)
/datum/om/event/living_status_paralyze
	sync = TRUE
	var/amount

/datum/om/event/living_status_paralyze/New(amount)
	src.amount = amount

/// Before a sleep increase (amount)
/datum/om/event/before/living_status_sleep
	accumulate = TRUE
	var/amount

/datum/om/event/before/living_status_sleep/New(amount)
	src.amount = amount

/// Before a stun increase (amount)
/datum/om/event/living_status_stun
	sync = TRUE
	var/amount

/datum/om/event/living_status_stun/New(amount)
	src.amount = amount

/// Before a weakness increase (amount)
/datum/om/event/living_status_weaken
	sync = TRUE
	var/amount

/datum/om/event/living_status_weaken/New(amount)
	src.amount = amount

/// Called when a living mob collides with a dense turf : /mob/living/proc/turf_collision(var/turf/T, var/speed)
/datum/om/event/before/living_turf_collision
	accumulate = TRUE
	var/t
	var/speed

/datum/om/event/before/living_turf_collision/New(t, speed)
	src.t = t
	src.speed = speed

/// From /obj/machinery/atom_break(damage_flag): (damage_flag)
/datum/om/event/machinery_broken
	sync = TRUE
	var/damage_flag

/datum/om/event/machinery_broken/New(damage_flag)
	src.damage_flag = damage_flag

/// From /obj/machinery/rnd/destructive_analyzer/proc/destroy_item(gain_research_points = FALSE): Runs when the destructive scanner scans a group of objects. (list/scanned_atoms)
/datum/om/event/machinery_destructive_scan
	sync = TRUE
	var/scanned_atoms

/datum/om/event/machinery_destructive_scan/New(scanned_atoms)
	src.scanned_atoms = scanned_atoms

/// From /obj/machinery/doppler_array/proc/sense_explosion(): Runs when an explosion is detected. (turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, seconds_taken)
/datum/om/event/machinery_explosion_detected
	sync = TRUE
	var/epicenter
	var/devastation_range
	var/heavy_impact_range
	var/light_impact_range
	var/seconds_taken

/datum/om/event/machinery_explosion_detected/New(epicenter, devastation_range, heavy_impact_range, light_impact_range, seconds_taken)
	src.epicenter = epicenter
	src.devastation_range = devastation_range
	src.heavy_impact_range = heavy_impact_range
	src.light_impact_range = light_impact_range
	src.seconds_taken = seconds_taken

/// From base power_change() when power is lost
/datum/om/event/machinery_power_lost
	sync = TRUE

/// From base power_change() when power is restored
/datum/om/event/machinery_power_restored
	sync = TRUE

/// Material Container Signals Called from datum/component/material_container/proc/insert_item() : (item, primary_mat, mats_consumed, material_amount, context)
/datum/om/event/matcontainer_item_consumed
	sync = TRUE
	var/item
	var/primary_mat
	var/mats_consumed
	var/material_amount
	var/context

/datum/om/event/matcontainer_item_consumed/New(item, primary_mat, mats_consumed, material_amount, context)
	src.item = item
	src.primary_mat = primary_mat
	src.mats_consumed = mats_consumed
	src.material_amount = material_amount
	src.context = context

/// Called from datum/component/material_container/proc/retrieve_stack() : (new_stack, context)
/datum/om/event/matcontainer_stack_retrieved
	sync = TRUE
	var/new_stack
	var/context

/datum/om/event/matcontainer_stack_retrieved/New(new_stack, context)
	src.new_stack = new_stack
	src.context = context

/datum/om/event/material_surgery
	sync = TRUE
	var/patient
	var/zone
	var/success

/datum/om/event/material_surgery/New(patient, zone, success)
	src.patient = patient
	src.zone = zone
	src.success = success

/// From base of /mob/living/proc/apply_damage(): (damage, damagetype, def_zone, blocked, wound_bonus, exposed_wound_bonus, sharpness, attack_direction, attacking_item)
/datum/om/event/mob_apply_damage
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

/datum/om/event/mob_apply_damage/New(damage, damagetype, def_zone, blocked, wound_bonus, exposed_wound_bonus, sharpness, attack_direction, attacking_item)
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
/datum/om/event/mob_client_login
	sync = TRUE
	var/client

/datum/om/event/mob_client_login/New(client)
	src.client = client

/// From /mob/proc/set_combat_mode(): (new_mode)
/datum/om/event/mob_combat_mode_changed
	sync = TRUE
	var/new_mode

/datum/om/event/mob_combat_mode_changed/New(new_mode)
	src.new_mode = new_mode

/// From base of mob/death(): (gibbed)
/datum/om/event/mob_death
	sync = TRUE
	var/gibbed

/datum/om/event/mob_death/New(gibbed)
	src.gibbed = gibbed

/// From /proc/domutcheck(): ()
/datum/om/event/mob_dna_mutation
	sync = TRUE

/// A mob has just equipped an item. Called on [/mob] from base of [/obj/item/equipped()]: (/obj/item/equipped_item, slot)
/datum/om/event/mob_equipped_item
	sync = TRUE
	var/equipped_item
	var/slot

/datum/om/event/mob_equipped_item/New(equipped_item, slot)
	src.equipped_item = equipped_item
	src.slot = slot

/// From /datum/action/Grant(): (datum/action)
/datum/om/event/mob_granted_action
	sync = TRUE
	var/action

/datum/om/event/mob_granted_action/New(action)
	src.action = action

/// From the HUD life system (/mob/proc/hud_available()).
/datum/om/event/before/mob_handle_hud
	accumulate = TRUE

/// From the HUD life system (darksight()).
/datum/om/event/mob_handle_hud_darksight
	sync = TRUE

/// From the HUD life system (health_icons()).
/datum/om/event/before/mob_handle_hud_health_icon
	accumulate = TRUE

/// From the vision life system (/mob/proc/refresh_vision() for mobs without one).
/datum/om/event/mob_handle_vision
	sync = TRUE

/// From base of /mob/Login(): ()
/datum/om/event/mob_login
	sync = TRUE

/// From base of /mob/Logout(): ()
/datum/om/event/mob_logout
	sync = TRUE

/// A condition was attached, removed, or crossed a clinically meaningful threshold.
/datum/om/event/mob_medical_issues_changed
	sync = TRUE

/// From mind/transfer_to. Sent to the receiving mob.
/datum/om/event/mob_mind_transferred_into
	sync = TRUE
	var/old_character

/datum/om/event/mob_mind_transferred_into/New(old_character)
	src.old_character = old_character

/// From mind/transfer_from. Sent to the mob the mind is being transferred out of.
/datum/om/event/mob_mind_transferred_out_of
	sync = TRUE
	var/new_character

/datum/om/event/mob_mind_transferred_out_of/New(new_character)
	src.new_character = new_character

/// From base of /client/Move(n, direct) : (direction) returns bool, if component handled movement
/datum/om/event/before/mob_relay_movement
	accumulate = TRUE
	var/direction

/datum/om/event/before/mob_relay_movement/New(direction)
	src.direction = direction

/// From /datum/action/Remove(): (datum/action)
/datum/om/event/mob_removed_action
	sync = TRUE
	var/action

/datum/om/event/mob_removed_action/New(action)
	src.action = action

/// From base of /mob/proc/reset_perspective() : ()
/datum/om/event/mob_reset_perspective
	sync = TRUE

/// From base of mob/set_stat(): (new_stat, old_stat)
/datum/om/event/mob_statchange
	sync = TRUE
	var/new_stat
	var/old_stat

/datum/om/event/mob_statchange/New(new_stat, old_stat)
	src.new_stat = new_stat
	src.old_stat = old_stat

/// A mob has just unequipped an item.
/datum/om/event/mob_unequipped_item
	sync = TRUE
	var/item
	var/target

/datum/om/event/mob_unequipped_item/New(item, target)
	src.item = item
	src.target = target

/// From base of atom/movable/Moved(): (/atom, newloc, direction)
/datum/om/event/movable_attempted_move
	sync = TRUE
	var/old_loc
	var/new_loc

/datum/om/event/movable_attempted_move/New(old_loc, new_loc)
	src.old_loc = old_loc
	src.new_loc = new_loc

/// From base of atom/movable/Bump(): (/atom)
/datum/om/event/before/movable_bump
	accumulate = TRUE
	var/atom

/datum/om/event/before/movable_bump/New(atom)
	src.atom = atom

/// From base of atom/movable/throw_impact() after confirming a hit: (/atom/hit_atom, /datum/thrownthing/throwingdatum)
/datum/om/event/movable_impact
	sync = TRUE
	var/hit_atom
	var/throwingdatum

/datum/om/event/movable_impact/New(hit_atom, throwingdatum)
	src.hit_atom = hit_atom
	src.throwingdatum = throwingdatum

/// From /datum/controller/subsystem/motion_tracker/notice() (source_atom OM handle,/turf/echo_turf_location)
/datum/om/event/movable_motiontracker
	sync = TRUE
	var/handle
	var/echo_turf_location

/datum/om/event/movable_motiontracker/New(handle, echo_turf_location)
	src.handle = handle
	src.echo_turf_location = echo_turf_location

/// From base of atom/movable/Moved(): (/atom)
/datum/om/event/before/movable_pre_move
	accumulate = TRUE
	var/new_loc
	var/direction
	var/movetime

/datum/om/event/before/movable_pre_move/New(new_loc, direction, movetime)
	src.new_loc = new_loc
	src.direction = direction
	src.movetime = movetime

/// From base of atom/movable/on_changed_z_level(): (turf/old_turf, turf/new_turf, same_z_layer)
/datum/om/event/before/movable_z_changed
	accumulate = TRUE
	var/old_z
	var/new_z

/datum/om/event/before/movable_z_changed/New(old_z, new_z)
	src.old_z = old_z
	src.new_z = new_z

/// /obj signals from base of obj/deconstruct(): (disassembled)
/datum/om/event/obj_deconstruct
	sync = TRUE
	var/disassembled

/datum/om/event/obj_deconstruct/New(disassembled)
	src.disassembled = disassembled

/datum/om/event/observer_apc
	sync = TRUE

/datum/om/event/observer_globalmoved
	sync = TRUE

/datum/om/event/observer_shuttle_added
	sync = TRUE
	var/shuttle

/datum/om/event/observer_shuttle_added/New(shuttle)
	src.shuttle = shuttle

/datum/om/event/observer_shuttle_moved
	sync = TRUE
	var/old_location
	var/destination

/datum/om/event/observer_shuttle_moved/New(old_location, destination)
	src.old_location = old_location
	src.destination = destination

/datum/om/event/observer_shuttle_pre_move
	sync = TRUE
	var/old_location
	var/destination

/datum/om/event/observer_shuttle_pre_move/New(old_location, destination)
	src.old_location = old_location
	src.destination = destination

/datum/om/event/observer_turf_entered
	sync = TRUE
	var/datum/arrived
	var/old_loc

/datum/om/event/observer_turf_entered/New(arrived_handle, old_loc)
	rel_set(src, "arrived", arrived_handle)
	src.old_loc = old_loc

/// From /client/proc/handle_popup_close() : (window_id)
/datum/om/event/popup_cleared
	sync = TRUE
	var/window_id

/datum/om/event/popup_cleared/New(window_id)
	src.window_id = window_id

/// Just before a datum's Destroy() is called: (force), at this point none of the other components chose to interrupt qdel and Destroy will be called
/datum/om/event/qdeleting
	sync = TRUE
	var/force

/datum/om/event/qdeleting/New(force)
	src.force = force

/// Non TG signals: from base of /datum/reagents/proc/handle_reactions(): (list/datum/decl/chemical_reaction)
/datum/om/event/reagents_holder_reacted
	sync = TRUE
	var/chemical_reaction

/datum/om/event/reagents_holder_reacted/New(chemical_reaction)
	src.chemical_reaction = chemical_reaction

/// Sent to the obj from base of [/datum/reagent/proc/touch_obj]: (datum/reagent/reagent, amount)
/datum/om/event/reagent_expose_obj
	sync = TRUE
	/// The /datum/reagent touching the obj.
	var/reagent
	var/amount

/datum/om/event/reagent_expose_obj/New(reagent, amount)
	src.reagent = reagent
	src.amount = amount

/// /datum/remote_view event that can be sent from the mob remote viewing, the viewed mob, or object being used to view to forcibly end all related remote viewing components
/datum/om/event/remote_view_clear
	sync = TRUE

/// From the robot belly overlay provider: (belly_class, list/fullness_ref) Handlers may adjust fullness_ref[1].
/datum/om/event/robot_belly_fullness
	sync = TRUE
	var/belly_class
	var/fullness_ref

/datum/om/event/robot_belly_fullness/New(belly_class, fullness_ref)
	src.belly_class = belly_class
	src.fullness_ref = fullness_ref

/// From /mob/living/silicon/robot/proc/after_equip(): (obj/item/equipped_or_null)
/datum/om/event/robot_equipment_changed
	sync = TRUE
	var/item

/datum/om/event/robot_equipment_changed/New(item)
	src.item = item

/// Non TG signals: from the base of /mob/living/silicon/robot/ClickOn(): (var/atom/A, var/params)
/datum/om/event/before/robot_item_attack
	accumulate = TRUE
	var/item
	var/user
	var/params

/datum/om/event/before/robot_item_attack/New(item, user, params)
	src.item = item
	src.user = user
	src.params = params

/// From [/mob/living/carbon/human/Move]: ()
/datum/om/event/before/shoes_step_action
	accumulate = TRUE
	var/m_intent

/datum/om/event/before/shoes_step_action/New(m_intent)
	src.m_intent = m_intent

/// From /mob/living/silicon/proc/laws_changed(): ()
/datum/om/event/silicon_laws_changed
	sync = TRUE

/// From the ledger after a thing entered one of the holder's slots: (atom/movable/thing, slot_id)
/datum/om/event/slot_inserted
	sync = TRUE
	var/thing
	var/slot_id

/datum/om/event/slot_inserted/New(thing, slot_id)
	src.thing = thing
	src.slot_id = slot_id

/// Containment ledger (code/datums/containment/). Sent on the holder. from the ledger before a thing enters one of the holder's slots: (atom/movable/thing, slot_id, mob/actor)
/datum/om/event/before/slot_pre_insert
	accumulate = TRUE
	var/thing
	var/slot_id
	var/actor

/datum/om/event/before/slot_pre_insert/New(thing, slot_id, actor)
	src.thing = thing
	src.slot_id = slot_id
	src.actor = actor

/// From the ledger before a thing leaves one of the holder's slots: (atom/movable/thing, slot_id, mob/actor)
/datum/om/event/before/slot_pre_remove
	accumulate = TRUE
	var/thing
	var/slot_id
	var/actor

/datum/om/event/before/slot_pre_remove/New(thing, slot_id, actor)
	src.thing = thing
	src.slot_id = slot_id
	src.actor = actor

/// From the ledger after a thing left one of the holder's slots: (atom/movable/thing, slot_id)
/datum/om/event/slot_removed
	sync = TRUE
	var/thing
	var/slot_id

/datum/om/event/slot_removed/New(thing, slot_id)
	src.thing = thing
	src.slot_id = slot_id

/// Called when a techweb design is researched (datum/design/researched_design, custom)
/datum/om/event/techweb_add_design
	sync = TRUE
	var/researched_design
	var/custom

/datum/om/event/techweb_add_design/New(researched_design, custom)
	src.researched_design = researched_design
	src.custom = custom

/// Called when a techweb design is removed (datum/design/removed_design, custom)
/datum/om/event/techweb_remove_design
	sync = TRUE
	var/removed_design
	var/custom

/datum/om/event/techweb_remove_design/New(removed_design, custom)
	src.removed_design = removed_design
	src.custom = custom

/// From /obj/machinery/computer/telescience/proc/doteleport(mob/user): (list/atom/movable/teleported_things, turf/target_turf, sending )
/datum/om/event/telesci_teleport
	sync = TRUE
	var/teleported_things
	var/target_turf
	var/sending

/datum/om/event/telesci_teleport/New(teleported_things, target_turf, sending)
	src.teleported_things = teleported_things
	src.target_turf = target_turf
	src.sending = sending

/// Window is fully visible and we can make fragile calls
/datum/om/event/tgui_window_visible
	sync = TRUE
	var/client

/datum/om/event/tgui_window_visible/New(client)
	src.client = client

/// From base of turf/ChangeTurf(): (path, list/new_baseturfs, flags, list/post_change_callbacks). `post_change_callbacks` is a list that signal handlers can mutate to append `/datum/callback` objects. They will be called with the new turf after the turf has changed.
/datum/om/event/turf_change
	sync = TRUE
	var/path
	var/new_baseturfs
	var/flags
	var/post_change_callbacks

/datum/om/event/turf_change/New(path, new_baseturfs, flags, post_change_callbacks)
	src.path = path
	src.new_baseturfs = new_baseturfs
	src.flags = flags
	src.post_change_callbacks = post_change_callbacks

/// From /datum/om/behaviour/footstep/prepare_step(): (list/steps)
/datum/om/event/before/turf_prepare_step_sound
	accumulate = TRUE
	var/steps

/datum/om/event/before/turf_prepare_step_sound/New(steps)
	src.steps = steps

/// From datum ui_act (usr, action)
/datum/om/event/ui_act
	sync = TRUE
	var/usr_
	var/action

/datum/om/event/ui_act/New(usr_, action)
	src.usr_ = usr_
	src.action = action

/datum/om/event/unittest_data
	sync = TRUE
	var/data

/datum/om/event/unittest_data/New(data)
	src.data = data

// ---------------------------------------------------------------- computed-name signals

/// Was SIGNAL_ADDTRAIT(trait): `trait` was gained (its first source added). Hook it and
/// test event.trait (hooks key on the event type, not the trait).
/datum/om/event/trait_gained
	sync = TRUE
	var/trait

/datum/om/event/trait_gained/New(trait)
	src.trait = trait

/// Was SIGNAL_REMOVETRAIT(trait): `trait` was lost (its last source removed).
/datum/om/event/trait_lost
	sync = TRUE
	var/trait

/datum/om/event/trait_lost/New(trait)
	src.trait = trait

/// Was COMSIG_ATOM_TOOL_ACT(quality) / COMSIG_ATOM_SECONDARY_TOOL_ACT(quality): `user`
/// uses `tool` of `tool_quality` on the atom. Result bits are the tool_act return flags.
/datum/om/event/before/atom_tool_act
	accumulate = TRUE
	var/tool_quality
	var/secondary
	var/user
	var/tool

/datum/om/event/before/atom_tool_act/New(tool_quality, secondary, user, tool)
	src.tool_quality = tool_quality
	src.secondary = secondary
	src.user = user
	src.tool = tool

/// Was COMSIG_TOOL_ATOM_ACTED_PRIMARY(quality) / _SECONDARY(quality), sent on the tool
/// after it acted on `target`.
/datum/om/event/tool_atom_acted
	sync = TRUE
	var/tool_quality
	var/secondary
	var/target
	var/user
	var/modifiers

/datum/om/event/tool_atom_acted/New(tool_quality, secondary, target, user, modifiers)
	src.tool_quality = tool_quality
	src.secondary = secondary
	src.target = target
	src.user = user
	src.modifiers = modifiers
