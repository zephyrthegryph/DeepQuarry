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
