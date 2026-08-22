// Substance ammunition — material as an effect-payload on ANY round, built on the
// existing material-response machinery rather than a bespoke ammo type.
//
// Forging a magazine from an alloy at a lathe (any material-selectable ammo design)
// stamps every round with that material. For a substance alloy, the round's chambered
// bullet receives the same /datum/component/material_response a blade or thrown charge
// carries, and the base projectile's on_impact() emits the shared form-trigger — so the
// round discharges its substance where it strikes, only when the substance's own trigger
// is one a bullet presents (IMPACT/PRESSURE, + ENERGY for energy shots).
//
// This lives entirely on the BASE ammo_casing / ammo_magazine (plus the base projectile
// hook in projectile.dm and the base-magazine material_key plumbing in ammunition.dm), so
// it works for every caliber with zero per-caliber subtypes. A lathe design just points at
// a stock magazine and sets material_selectable; 9mm (material_selectable.dm) is the sample.

// ---- Casing: carry a forged material; infuse the chambered bullet ---------------
/obj/item/ammo_casing
	/// The material this round was forged from — an alloy payload, not its structure.
	var/datum/material/forged_material

// Stamp this round with a forged material: name it for the alloy, and for a substance
// alloy hand the chambered bullet the discharge infusion (not the persistent light/rad/tox
// behaviours — the bullet is a transient effect-carrier, destroyed on impact).
/obj/item/ammo_casing/proc/set_forged_material(datum/material/M)
	if(!istype(M))
		return
	forged_material = M
	name = "[M.display_name] [initial(name)]"
	color = M.icon_colour
	if(BB)
		BB.damage = max(1, round(BB.damage * clamp(0.75 + M.density / 240 + M.hardness / 400, 0.75, 1.25)))
		BB.armor_penetration = max(0, BB.armor_penetration + round((M.hardness - M.brittleness * 0.35) / 12))
		M.dq_apply_material_behaviors(BB)

// ---- Magazine: propagate the forged material to its rounds -----------------------
/obj/item/ammo_magazine
	/// The material this magazine's rounds were forged from, if any (naming / examine).
	var/datum/material/forged_material

// Apply a forged material to the whole magazine: rename it and stamp every stored round.
/obj/item/ammo_magazine/proc/set_forged_material(datum/material/M)
	if(!istype(M))
		return
	forged_material = M
	name = "[M.display_name] [initial(name)]"
	for(var/obj/item/ammo_casing/C in stored_ammo)
		C.set_forged_material(M)

// Shared examine line for a forged round / magazine (called from the base examine procs).
/proc/substance_round_examine(datum/material/forged, list/examine_text)
	if(!istype(forged))
		return
	if(istype(forged, /datum/material/processed_alloy))
		var/datum/material/processed_alloy/processed = forged
		examine_text += span_notice("Forged projectile stock: hardness [processed.hardness], density [processed.density], brittleness [processed.brittleness].")
	if(!length(forged.material_effects))
		return
	var/list/effects = list()
	for(var/datum/substance/effect as anything in forged.material_effects)
		effects += "[substance_family_name(effect.family)] on [substance_trigger_name(effect.trigger)]"
	examine_text += span_notice("Forged material responses: [jointext(effects, "; ")].")
