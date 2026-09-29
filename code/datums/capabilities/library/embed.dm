// embed(): how readily the item lodges in what it hits. The item's `embed_chance` stays the truth the
// hit code reads (carbon_defense.dm, human_defense.dm); `chance` is the type default written onto it
// at init, before /obj/item/Initialize() would derive one from force, and a map edit wins.
//
//	/obj/item/material/shard/capabilities()
//		. = ..()
//		. += embed(chance = 40)

/datum/capability/embed
	works_broken = TRUE
	works_unpowered = TRUE
	/// Percent chance to lodge on a hit hard enough (0 never embeds).
	var/chance = 0

/proc/embed(chance = 0)
	var/datum/capability/embed/C = new
	C.chance = clamp(chance, 0, 100)
	return C

/datum/capability/embed/on_holder_init(atom/holder, mapload)
	if(!isitem(holder))
		return
	var/obj/item/I = holder
	cap_default_var(I, nameof(I.embed_chance), chance)

/datum/capability/embed/examine(atom/holder, mob/user)
	var/obj/item/I = holder
	if(!istype(I) || I.embed_chance <= 0)
		return null
	return list(I.embed_chance >= 50 ? "It looks like it would lodge in a wound." : "It could lodge in a wound.")
