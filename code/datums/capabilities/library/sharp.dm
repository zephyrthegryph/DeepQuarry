// cap_sharp(): the item cuts (sharp) and/or has a dismembering edge (edge). The item's own `sharp` and
// `edge` vars stay the truth every existing reader uses (is_sharp(), has_edge(), can_puncture(), the
// embed and armour code); the arguments are the type defaults written onto them at init, and a map
// edit of either var wins.
//
//	/obj/item/knife/capabilities()
//		. = ..()
//		. += cap_sharp(edge = TRUE)

/datum/capability/sharp
	works_broken = TRUE
	works_unpowered = TRUE
	var/sharp = TRUE
	var/edge = FALSE

/proc/cap_sharp(edge = FALSE, sharp = TRUE, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/sharp/C = new
	C.sharp = sharp
	C.edge = edge
	cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/datum/capability/sharp/on_holder_init(atom/holder, mapload)
	if(!isitem(holder))
		return
	var/obj/item/I = holder
	cap_default_var(I, nameof(I.sharp), sharp)
	cap_default_var(I, nameof(I.edge), edge)

/datum/capability/sharp/examine(atom/holder, mob/user)
	var/obj/item/I = holder
	if(!istype(I))
		return null
	if(I.edge)
		return list("It has a keen edge.")
	if(I.sharp)
		return list("It has a sharp point.")
	return null
