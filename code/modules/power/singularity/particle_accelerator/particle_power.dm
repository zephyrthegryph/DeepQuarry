/obj/structure/particle_accelerator/power_box
	name = "Particle Focusing EM Lens"
	desc_holder = "This uses electromagnetic waves to focus the Alpha-Particles."
	icon = 'icons/obj/machines/particle_accelerator2.dmi'
	icon_state = "power_box"
	reference = "power_box"

/obj/structure/particle_accelerator/power_box/pre_mapped
	anchored = TRUE

CAPABILITIES(/obj/structure/particle_accelerator/power_box/pre_mapped)
	configure(construction_graph(start = STAGE_PA_CLOSED, via = list(STAGE_PA_BOLTED, STAGE_PA_WIRED)))
