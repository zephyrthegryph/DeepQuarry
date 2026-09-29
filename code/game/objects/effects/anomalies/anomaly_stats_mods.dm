/datum/anomaly_modifiers
	var/name
	var/description
	var/value
	var/obj/effect/anomaly/attached_anomaly

/datum/anomaly_modifiers/proc/get_description()
	return description

/datum/anomaly_modifiers/proc/get_value()
	return value

/datum/anomaly_modifiers/proc/on_add(obj/effect/anomaly/anomaly)
	rel_set(src, "attached_anomaly", anomaly)
	if(!istype(attached_anomaly(), /obj/effect/anomaly))
		return FALSE
	return TRUE

/datum/anomaly_modifiers/proc/on_remove(obj/effect/anomaly/anomaly)
	rel_set(src, "attached_anomaly", anomaly)
	if(!istype(attached_anomaly(), /obj/effect/anomaly))
		return FALSE
	return TRUE

/datum/anomaly_modifiers/reflective
	name = "Reflective"
	description = "A protective coating was detected."
	value = 1.2

/datum/anomaly_modifiers/invisible
	name = "Invisible"
	description = "Light wave distortion was detected."
	value = 1.5

/datum/anomaly_modifiers/invisible/on_add(anomaly)
	if(!..())
		return
	om_after(attached_anomaly(), 2 SECONDS, TYPE_PROC_REF(/atom/movable, cloak))

/datum/anomaly_modifiers/invisible/on_remove(anomaly)
	if(!..())
		return
	om_after(attached_anomaly(), 2 SECONDS, TYPE_PROC_REF(/atom/movable, uncloak))

/datum/anomaly_modifiers/move
	name = "Move"
	description = "Anomalous anchoring could not be detected."
	value = 1.4

/datum/anomaly_modifiers/move/on_add(anomaly)
	if(!..())
		return
	attached_anomaly().move_chance = ANOMALY_MOVECHANCE

/datum/anomaly_modifiers/move/on_remove(anomaly)
	if(!..())
		return
	attached_anomaly().move_chance = 0

/datum/anomaly_modifiers/fast
	name = "Faster Pulses"
	description = "Anomalous pulses are more common."
	value = 0.9

/datum/anomaly_modifiers/fast/on_add(anomaly)
	if(!..())
		return

	var/datum/anomaly_stats/stats = attached_anomaly().stats
	stats.min_activation = 25 SECONDS
	stats.max_activation = 45 SECONDS

/datum/anomaly_modifiers/fast/on_remove(anomaly)
	if(!..())
		return

	var/datum/anomaly_stats/stats = attached_anomaly().stats

	stats.min_activation = initial(stats.min_activation)
	stats.max_activation = initial(stats.max_activation)

/// The relation view `attached_anomaly` (null once it is gone).
/datum/anomaly_modifiers/proc/attached_anomaly() as /obj/effect/anomaly
	return attached_anomaly
