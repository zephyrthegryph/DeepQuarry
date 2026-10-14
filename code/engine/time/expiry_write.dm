/// Called by EXPIRY_SET / EXPIRY_EXTEND with the value being written; returns it unchanged.
/proc/expiry_written(datum/D, var_name, value)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(D)
	if(decls?.expiry_hooks && decls.expiry_hooks[var_name])
		D.arm_declared_expiry(var_name, value)
	return value


/// Declared expiry observers are implemented by the compatibility library.
/datum/proc/arm_declared_expiry(var_name, value)
	return
