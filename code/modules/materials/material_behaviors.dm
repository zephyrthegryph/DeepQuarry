// Material behaviours — the working implementation.
//
// A material's three active behaviours (luminescence, radioactivity, toxicity)
// are plain numeric magnitudes on /datum/material (see _materials.dm). This file
// owns: the read API, the item-side application, and the component that actually
// makes the behaviour happen. It replaces the earlier half-wired component layer
// (which only carried magnitudes and never irradiated/poisoned anything). The old
// material-synergy system was removed outright — no shims remain.

// ---- Read API --------------------------------------------------------------
// Canonical accessors; structural readers (walls, girders, doors, fuel) go
// through these so the storage can change without touching every site.

/proc/dq_material_luminescence(datum/material/M)
	return M ? M.luminescence : 0

/proc/dq_material_radioactivity(datum/material/M)
	return M ? M.radioactivity : 0

/proc/dq_material_toxicity(datum/material/M)
	return M ? M.toxicity : 0

// ---- Item application ------------------------------------------------------
// Called from each material item's set_material once the material is assigned.
// Configures the item's emissions (light now; rad/tox while carried).

/datum/material/proc/dq_apply_material_behaviors(obj/item/I)
	if(!I)
		return
	// Geometry-specific consumers can override thickness; ordinary fabricated
	// items use a five-millimeter representative path through their material.
	I.set_rad_insulation(material_radiation_transmission(5))
	configure_item_emissions(I, luminescence, radioactivity, toxicity, icon_colour)
	dq_apply_material_responses(I)

