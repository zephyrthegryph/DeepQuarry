// C8a: occupant machines (doc/rewrite/containment.md §10, roadmap C8).
//
// An occupant slot is sealed and reaches_mobs: its holder defines the
// occupant's environment the same way a vore belly does (C7) -- the holder's
// own shell is what stands between the occupant and the outside, and gas
// doesn't cross a sealed slot's boundary. What the holder *does* to its
// occupant (despawning, resleeving, gibbing, charging, scanning...) is each
// machine's own business and untouched here; this only carries the move in,
// move out and destroy bookkeeping onto the ledger (C1) so the machine's
// contents go through the same path as every other holder: propagation
// shares it (C2), and explosion severity now reads its slot's own share
// instead of a bespoke override.

/// Base for a machine's sealed, single-occupant slot. Subtype per holder to
/// set the id and any damage/heat shares that differ from the sealed default.
/datum/om/relation/slot/occupant
	name = "occupant"
	// Not the default: a machine's incidental raw contents (component parts,
	// its cell, a loaded disk, a radio built in Initialize()...) must not
	// compete with the occupant for this slot's one-person capacity. Every
	// holder below also declares /datum/om/relation/slot/machine_internals (stock.dm,
	// C6) as its default, which is what legacy new(src)/forceMove(src) calls
	// land in instead.
	exposure = SLOT_EXPOSURE_SEALED
	reaches_mobs = TRUE
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1
	drop_policy = SLOT_DROP_SPILL
	heat_transmission = 0
	radiation_transmission = 1
	damage_transmission = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

/// Share (0..1) of an explosion's severity that reaches `holder`'s contents,
/// from its declared slots' own DAMAGE_BLAST share, attenuated the same way
/// dq_path_step() attenuates any other damage kind (holder armour, then outer
/// layers). Replaces a holder's own explosion_contents_severity() override
/// (D5, containment.md §10): the number now lives on the slot, as data.
/proc/dq_slot_blast_severity(atom/movable/holder, severity)
	var/datum/ledger/L = dq_ledger(holder)
	if(!L || !severity)
		return 0
	var/share = 0
	for(var/datum/om/relation/slot/def as anything in L.defs)
		var/def_share = def.damage_share(DAMAGE_BLAST)
		if(def_share <= 0)
			continue
		if(def.is_inside())
			def_share *= dq_path_attenuation(holder, PATH_EFFECT_DAMAGE, DAMAGE_BLAST)
		share = max(share, def_share)
	if(share <= 0)
		return 0
	return round(severity * share)
