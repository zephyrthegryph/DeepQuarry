// The singularity generator (doc/rewrite/final_api.html section 16): particles charge it (set_energy(), from the accelerator's particles) and at
// SINGULARITY_GENERATOR_THRESHOLD it collapses into its creation (a singularity, or for the tesla generator an energy ball). A wrench bolts it
// down; a screwdriver opens its mechanism (panel()), and with the mechanism open a super I/O coil turns it into a particle smasher.

/// The charge at which the generator collapses into what it creates.
#define SINGULARITY_GENERATOR_THRESHOLD 200

MSG_DEF(singularitygen/modifying, "You begin to modify %T% with %I%.", "%U% begins to modify %T% with %I%.")
MSG_DEF_SELF(singularitygen/adaptable, "It looks like it could be adapted to forge advanced materials via particle acceleration, somehow..")

/obj/machinery/the_singularitygen
	name = "Gravitational Singularity Generator"
	desc = "An Odd Device which produces a Gravitational Singularity when set up."
	icon = 'icons/obj/singularity.dmi'
	icon_state = "TheSingGen"
	anchored = FALSE
	density = TRUE
	use_power = USE_POWER_OFF
	/// The charge the particles gave it.
	var/energy = 0
	var/creation_type = /obj/singularity

TRACKED(/obj/machinery/the_singularitygen, energy)

CAPABILITIES(/obj/machinery/the_singularitygen)
	anchor()
	panel()
	on_change(nameof(energy), ANY, then(PROC_REF(collapse_check)))
	examine_line(PROC_REF(examine_secured))
	examine_line(MSG(singularitygen/adaptable), when = PANEL_OPEN)
	op("install", item(/obj/item/smes_coil/super_io), label("Install"), when(PANEL_OPEN), wait(30 SECONDS),
		says(MSG(singularitygen/modifying)), then(PROC_REF(install_done)))

/// Bolted down and ready, or not secured.
/obj/machinery/the_singularitygen/proc/examine_secured(datum/act/A)
	if(anchored)
		return span_notice("It has been securely bolted down and is ready for operation.")
	return span_warning("It is not secured!")

/// A particle charged it: once it holds SINGULARITY_GENERATOR_THRESHOLD it collapses into its creation.
/obj/machinery/the_singularitygen/proc/collapse_check(datum/act/A)
	if(energy < SINGULARITY_GENERATOR_THRESHOLD || QDELETED(src))
		return
	var/turf/T = get_turf(src)
	new creation_type(T, 50)
	qdel(src)

/// The coil is in: the generator becomes a particle smasher.
/obj/machinery/the_singularitygen/proc/install_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	act_message(user, src, MSG_SELF("You install %I% onto %T%."), MSG_OTHERS("%U% installs %I% onto %T%."), item = W)
	if(!global.consume(W, user))
		return OP_REFUSED
	var/turf/T = get_turf(src)
	new /obj/machinery/particle_smasher(T)
	qdel(src)
	return OP_OK

#undef SINGULARITY_GENERATOR_THRESHOLD
