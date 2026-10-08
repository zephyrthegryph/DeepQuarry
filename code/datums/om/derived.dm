// Legacy names forward to the real generic engine implementation.

/proc/om_derived(datum/E, name)
	return derived_derived(arglist(args))

/proc/om_dv_find(datum/om/rec/rec, didx)
	return derived_dv_find(arglist(args))

/proc/om_dv_create(datum/om/rec/rec, datum/om/derived/D)
	return derived_dv_create(arglist(args))

/proc/om_dv_full(datum/om/rec/rec, k, datum/om/derived/D)
	return derived_dv_full(arglist(args))

/proc/om_agg_contribution(datum/om/derived/D, datum/member)
	return derived_agg_contribution(arglist(args))

/proc/om_derived_inputs_changed(datum/om/rec/rec, bits)
	return derived_derived_inputs_changed(arglist(args))

/proc/om_dv_mark(datum/om/rec/rec, k, datum/om/derived/D)
	return derived_dv_mark(arglist(args))

/proc/om_edge_cache_get(datum/om/edge/edge, didx)
	return derived_edge_cache_get(arglist(args))

/proc/om_edge_cache_set(datum/om/edge/edge, didx, value)
	return derived_edge_cache_set(arglist(args))

/proc/om_agg_edge_added(datum/om/edge/edge)
	return derived_agg_edge_added(arglist(args))

/proc/om_agg_edge_removed(datum/om/edge/edge, datum/om/rec/rec)
	return derived_agg_edge_removed(arglist(args))

/proc/om_agg_member_changed(datum/origin, didx, datum/member)
	return derived_agg_member_changed(arglist(args))

/proc/om_agg_delta(datum/om/rec/rec, k, datum/om/derived/D, datum/member, old_c, new_c, sign)
	return derived_agg_delta(arglist(args))
