// A gas port's starting mixture: an empty /datum/gas_mixture an atmospherics device makes for one of its port vars when it initializes.
//
//   gas_port(nameof(air1), volume = nameof(air1_volume))       // a binary device's inlet: a subtype sets air1_volume, not a set_volume() call
//   gas_port(nameof(air_contents), volume = 200)
//
// The var is the device's PROTO gas port (owns_one(..., on_destroy = ON_DESTROY_PRIVATE_COPY), declared by the device): the mixture is put in
// through atmos_air_set(), as the old Initialize() did after ..(), so a pipe network may later point the var at its own mixture and gas_watch()
// and gas_level() follow it. `volume` is litres or nameof() a holder var, read per instance (a mapped edit counts). A var that already holds a
// mixture keeps it. It runs in the capability init: after the device's capabilities and before any type's code after its ..().

CAPABILITY_TYPE(gas_port, CAP_GAS_PORT, /datum/capability/lib/gas_port, key = var_name, var_name = null, volume = 200)

/datum/capability/lib/gas_port
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/gas_port/on_holder_init(datum/act/eval/A)
	var/datum/holder = A.holder
	if(!(var_name in holder.vars))
		stack_trace("gas_port([var_name]) on [holder.type], which has no such var")
		return
	if(isdatum(holder.vars[var_name]))
		return
	var/litres = istext(volume) ? holder.vars[volume] : volume
	atmos_air_set(holder, var_name, new /datum/gas_mixture(litres))
