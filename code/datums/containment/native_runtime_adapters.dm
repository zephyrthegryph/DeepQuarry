// Concrete world bridges for containment's engine-declared interfaces.
/atom/create_latent_generator_line(path, value)
	var/list/spec = dq_resolve_spawn_value(value)
	for(var/i in 1 to max(1, spec["count"]))
		spawn_with_variant(path, src, spec["variant"])

/atom/movable/containment_move(atom/destination)
	return forceMove(destination)

/atom/containment_drop_location()
	return drop_location()

/atom/containment_blast_exposure(severity)
	return ex_act(severity)

/atom/containment_armor_share(key, penetration)
	return dq_armor_average_percent(get_armor().effective(key, penetration)) / 100

/atom/containment_bay_share(datum/relation_definition/slot/def, effect)
	return dq_bay_share(src, def, effect)

/mob/living/containment_living()
	return TRUE

/atom/containment_slot_changed(slot_id, atom/movable/thing, inserted)
	return occupant_pod_slot_changed(src, slot_id, thing, inserted)

/atom/receive_containment_damage(datum/damage_packet/packet)
	return receive_damage(packet)

/atom/movable/containment_redraw()
	return update_icon()

/atom/movable/containment_fire(temperature, volume)
	return fire_act(temperature, volume)
