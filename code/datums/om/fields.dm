// Legacy names forward to the real generic engine implementation.

/datum/om/field_def
	parent_type = /datum/scheduler_field_definition

/proc/om_field_channel(datum/E, name)
	return scheduler_field_field_channel(arglist(args))

/proc/om_set(datum/E, name, value)
	return scheduler_field_set(arglist(args))

/proc/om_field_changed(datum/E, name)
	return scheduler_field_field_changed(arglist(args))

/proc/om_flag_channels(list/table, changed, fallback)
	return scheduler_field_flag_channels(arglist(args))

/proc/om_field_table(path)
	return scheduler_field_field_table(arglist(args))

/proc/om_check_derived_inputs()
	return scheduler_field_check_derived_inputs(arglist(args))

/proc/om_derived_relays_of(path)
	return scheduler_field_derived_relays_of(arglist(args))

/proc/om_relay_targets(datum/E, var_name)
	return scheduler_field_relay_targets(arglist(args))

/proc/om_derived_relink(datum/E, datum/om/rec/rec)
	return scheduler_field_derived_relink(arglist(args))

/proc/om_relay_remove(datum/E, datum/om/rec/rec, datum/target)
	return scheduler_field_relay_remove(arglist(args))

/proc/om_relay_clear(datum/E, datum/om/rec/rec)
	return scheduler_field_relay_clear(arglist(args))
