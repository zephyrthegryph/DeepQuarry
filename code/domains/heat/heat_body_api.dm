// The heat domain's calls into the native heat network, for content: a thing with a heat body keeps it, heats it, couples it to what it
// touches and reads or sets its temperature through these. Content does not call the vg_ binds (lint_scopes.toml, legacy_forms).

/// Keeps (`keep` TRUE) or lets go of the body `body`'s resting state in the native network.
/proc/heat_body_keep(body, keep)
	return vg_heat_body_keep(body, keep)

/// Heats the body at `watts` (0 stops it).
/proc/heat_body_power(body, watts)
	return vg_heat_body_power(body, watts)

/// Couples `body`'s coupling `slot` to `target_kind` (HEAT_TARGET_*) `target_ref` at `conductance`.
/proc/heat_body_couple(body, slot, target_kind, target_ref, conductance)
	return vg_heat_body_couple(body, slot, target_kind, target_ref, conductance)

/// Sets the body's temperature (K).
/proc/heat_body_set_temperature(body, temperature)
	return vg_heat_body_set_temperature(body, temperature)

/// The body's temperature (K), or null when the native network has no such body.
/proc/heat_body_temperature(body)
	return vg_heat_body_temperature(body)

/// Removes the heat edge `id` from the native network.
/proc/heat_edge_drop(id)
	return vg_heat_edge_remove(id)

/// Sets one parameter (HEAT_PARAM_*) of the heat edge `id`.
/proc/heat_edge_param(id, param, value)
	return vg_heat_edge_set(id, param, value)

/// The work the heat edge `id` produced since it was last asked (J), taken from the native network.
/proc/heat_edge_work_taken(id)
	return vg_heat_edge_take_work(id)
