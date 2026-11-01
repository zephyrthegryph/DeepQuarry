// The one place containment paths couple to the heat model (roadmap C2 and
// M4; doc/rewrite/temperature.md §2.2, containment.md §3.2 and §4.2).
//
// Until the heat domain (code/modules/heat/) is on master, heat reaches
// contents as fire exposure: /obj/fire_act() calls propagate_fire() (paths.dm),
// which scales the fire's excess over the interior's ambient temperature by
// the path share. The two procs below are the whole interface; the heat
// domain calls them and nothing else:
//
//   dq_heat_path_ambient(holder)
//       the temperature inside `holder` when nothing heats it.
//   child.heat_path_conductance(base)
//       a heat body's conductance to its holder's interior: M4's
//       heat_coupling()/create_heat_body()/heat_recouple() pass the body's own
//       conductance (thermal_properties()[THERMAL_CONDUCTANCE]) through this,
//       so a closet's insulation and a suit over a jumpsuit slow the coupling
//       instead of each type writing its own rule.
//
// Latent entries (C5) never get heat bodies: a container's body carries their
// heat capacity (the ledger's PROP_HEAT_CAPACITY aggregate) and thresholds.

/// Temperature inside `holder` with no heat added: its turf's air, else 20 C.
/// A holder's own heat body is not the reference: propagate_fire() scales a
/// fire's excess over the room, and bodies carry the rest (H3).
/proc/dq_heat_path_ambient(atom/holder)
	var/turf/T = get_turf(holder)
	var/datum/gas_mixture/air = T?.return_air()
	var/temperature = air?.return_temperature()
	return temperature > 0 ? temperature : T20C


/atom/containment_ambient_temperature()
	return dq_heat_path_ambient(src)
