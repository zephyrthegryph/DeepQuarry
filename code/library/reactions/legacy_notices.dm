// Notices that replaced the OM events and are still published with PUBLISH_LEGACY(E, /datum/notice/x, fields...) in fill() order
// (doc/rewrite/reactions.md section 3). Written by hand: the generator (tools/dx/gen_om_notices.py) went with the events. A notice
// leaves this file when its ACTION() declaration replaces it (the declaration generates the notice type with the same fields).

/// examine and living_shield_injury: their fields come from ACTION(examine) and ACTION(living_shield_injury) (PUBLISH delivers at once, so a sender always reads what
/// the handlers wrote); the type still declares read_back because the read_back lint asks every notice a handler writes into for it.
/datum/notice/examine
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)

/datum/notice/living_shield_injury
	read_back = TRUE // the sender reads what the handlers wrote: answered at once, even mid-delivery (reactions.md section 3)

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
