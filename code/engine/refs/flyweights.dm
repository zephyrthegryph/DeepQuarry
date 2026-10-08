// Generic shared-value classification; downstream providers populate the root type table.
/proc/is_flyweight(datum/D)
	return isdatum(D) && !!GLOB.flyweight_types?[D.type]
