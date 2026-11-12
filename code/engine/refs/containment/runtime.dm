// Declared world interfaces; physical implementations stay downstream.
/atom/movable/proc/containment_move(atom/destination)
	return FALSE
/atom/proc/containment_drop_location()
	return get_turf(src)
/atom/proc/containment_armor_share(key, penetration)
	return 0
/atom/proc/containment_bay_share(datum/relation_definition/slot/def, effect)
	return 1
/atom/movable/proc/containment_living()
	return FALSE
/atom/proc/containment_slot_changed(slot_id, atom/movable/thing, inserted)
	return
/// The thing a VARIANT() reference names, made at `where` (code/content/variants/variant_alias.dm).
/atom/proc/variant_make_at(path, atom/where)
	return null
/// Makes a spawn list (`path` = count, or `path` = list(count, variant)) inside this atom.
/atom/proc/create_spawn_contents(list/spawn_list)
	for(var/path in spawn_list)
		create_spawn_line(path, spawn_list[path])
/// Makes one spawn-list line (`path` = count, or list(count, variant)) inside this atom.
/atom/proc/create_spawn_line(path, value)
	var/list/spec = dq_resolve_spawn_value(value)
	for(var/i in 1 to max(1, spec["count"]))
		new path(src)

/atom/proc/receive_containment_damage(datum/damage_packet/packet)
	return 0

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

