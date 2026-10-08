// Compatibility entry points; relation identity forwarding is engine-owned.

/proc/om_forward_family(datum/original)
	return rel_forward_family(original)

/proc/om_forward_compatible(datum/original, datum/successor)
	return rel_forward_compatible(original, successor)

/proc/om_handle_forward(datum/original, datum/successor)
	return rel_forward_identity(original, successor)

/proc/om_forward_state(datum/original, datum/successor)
	return rel_forward_state(original, successor)
