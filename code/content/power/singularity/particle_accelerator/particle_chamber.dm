/obj/structure/particle_accelerator/fuel_chamber
	name = "EM Acceleration Chamber"
	desc_holder = "This is where the Alpha particles are accelerated to <b><i>radical speeds</i></b>."
	icon = 'icons/obj/machines/particle_accelerator2.dmi'
	icon_state = "fuel_chamber"
	reference = "fuel_chamber"

/obj/structure/particle_accelerator/fuel_chamber/pre_mapped
	anchored = TRUE

CAPABILITIES(/obj/structure/particle_accelerator/fuel_chamber/pre_mapped)
	configure(construction_graph(start = STAGE_PA_CLOSED, via = list(STAGE_PA_BOLTED, STAGE_PA_WIRED)))
