// A declared type: every rule fires at least once, with its negative twin.
/obj/pointer
	var/energy = 8
	var/max_energy = 8
	var/pointing = FALSE
	var/spare = 0
	var/static/shared = 1
	var/list/kids
	var/obj/pointer/parent
	var
		blocked = 0
		tmp/hidden = 1
		list/stack[3]
	var/orphan

TRACKED(/obj/pointer, energy)
TRACKED(/obj/pointer, pointing)
SETTER(/obj/pointer, blocked)
OM_FIELD(/obj/pointer, max_energy)
OM_FIELD_TYPED(/obj/pointer, /obj/pointer, shared)
REL(/obj/pointer, parent)
OWN(/obj/pointer, kids)

/obj/pointer/should_run()
	return energy < max_energy

/obj/pointer/draw(datum/look/look, spare = 2)
	..()
	if(pointing)
		look.state("on")
	var/orphan = 3
	return src.blocked + hidden + spare + stack.len

/obj/pointer/hidden_verbs()
	// ALLOW(derived_reads): fixture keep on the line below
	if(shared)
		return 1
	if(orphan) // ALLOW(derived_reads): same line keep
		return 2
	return kids

/obj/pointer/tgui_data(mob/user as mob)
	// energy mentioned in a comment is not a read
	var/text = "energy [pointing] and shared"
	. = list("a" = energy, "b" = nameof(spare), "c" = initial(max_energy))
	energy = 5
	spare = 4
	foo(blocked = 1, other = 2)
	if(blocked == 2)
		return parent.energy
	return hidden

/obj/pointer/push_to_rust()
	return src.energy + shared

/obj/pointer/derived()
	. = ..()
	. += runs_while(nameof(energy))
	. += drawn_from(nameof(pointing), nameof(blocked), nameof(spare), nameof(kids), nameof(orphan),
		nameof(hidden))
	. += rust_push(nameof(energy))
	. += derive(nameof(blocked), nameof(energy), rel(nameof(parent), nameof(/obj/pointer::energy)), rel_each(nameof(kids), nameof(/obj/pointer/big::glow)))
	. += derive(nameof(hidden), nameof(nothing))
	. += ui_from(nameof(cap_data), nameof(cap_state))
	. += ui_from(nameof(/obj/pointer::energy))
	. += drawn_from(rel(nameof(stack), nameof(/obj/pointer::shared)), rel(nameof(/obj/x::y), nameof(/obj/pointer::energy)))

/obj/pointer/derive_hidden()
	return energy + max_energy + blocked

/obj/pointer/derive_orphan()
	return energy

/obj/pointer/derive_()
	return max_energy

/obj/pointer/on_state_changed(bits)
	return

/obj/pointer/big
	var/glow = FALSE

/obj/pointer/big/draw(datum/look/look)
	..()
	if(pointing && glow)
		look.state("big")

/obj/pointer/big/on_state_changed(bits)
	// ALLOW(derived_reads): a justified override
	return

/obj/pointer/big/derived()
	. = ..()
	. += drawn_from(nameof(glow))
	. += drawn_from(nameof(energy), rel(nameof(parent), nameof(/obj/pointer::glow)))
	. += runs_while()

/obj/pointer/proc/should_run_other()
	return energy

/obj/pointer/small/should_run()
	return glow

/obj/pointer/small/on_state_changed()
	return

/proc/should_run()
	return energy

/proc/derived()
	. += drawn_from(nameof(energy))
