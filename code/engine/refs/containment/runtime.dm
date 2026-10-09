// Declared world interfaces; physical implementations stay downstream.
/atom/movable/proc/containment_move(atom/destination)
	return FALSE
/atom/proc/containment_drop_location()
	return get_turf(src)
/atom/proc/containment_blast_exposure(severity)
	return
/atom/proc/containment_armor_share(key, penetration)
	return 0
/atom/proc/containment_bay_share(datum/relation_definition/slot/def, effect)
	return 1
/atom/movable/proc/containment_living()
	return FALSE
/atom/proc/containment_slot_changed(slot_id, atom/movable/thing, inserted)
	return
/atom/proc/create_latent_generator_line(path, value)
	var/list/spec = dq_resolve_spawn_value(value)
	for(var/i in 1 to max(1, spec["count"]))
		new path(src)

/atom/proc/receive_containment_damage(datum/damage_packet/packet)
	return 0

/atom/movable/proc/containment_redraw()
	return

/atom/movable/proc/containment_fire(temperature, volume)
	return

/atom/movable/proc/containment_move_flags()
	return rx?.containment_move_hooks || 0
/atom/movable/proc/set_containment_move_flags(value)
	if(!value && !rx)
		return
	var/datum/rx_state/S = rx_of(src)
	S.containment_move_hooks = value

/atom/movable/proc/containment_successor()
	return rx?.containment_successor
/atom/movable/proc/set_containment_successor(atom/movable/value)
	if(!value && !rx)
		return
	var/datum/rx_state/S = rx_of(src)
	S.containment_successor = value

/atom/proc/latent_is_declared()
	return !!rx?.containment_declared
/atom/proc/set_latent_declared(value)
	if(!value && !rx)
		return
	var/datum/rx_state/S = rx_of(src)
	if(S.containment_declared != value)
		PUBLISH_CHANGE(src, SLOT_OCCUPANCY_KEY) // what slot_kinds() answers moves from the generator to the ledger
	S.containment_declared = value

/atom/proc/latent_policy_disabled()
	return !!rx?.containment_policy_disabled
/atom/proc/set_latent_policy_disabled(value)
	if(!value && !rx)
		return
	var/datum/rx_state/S = rx_of(src)
	S.containment_policy_disabled = value
