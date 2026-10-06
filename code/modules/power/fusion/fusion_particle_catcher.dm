/obj/effect/fusion_particle_catcher
	icon = 'icons/effects/effects.dmi'
	density = TRUE
	anchored = TRUE
	invisibility = INVISIBILITY_ABSTRACT
	var/obj/effect/fusion_em_field/parent
	var/mysize = 0

	light_color = COLOR_BLUE

// The field owns its catchers (rel_add in fusion_em_field/Initialize()); a catcher names its field.
CAPABILITIES(/obj/effect/fusion_particle_catcher)
	ref_one(nameof(parent), /obj/effect/fusion_em_field)

/obj/effect/fusion_particle_catcher/proc/SetSize(newsize)
	name = "collector [newsize]"
	mysize = newsize
	UpdateSize()

/obj/effect/fusion_particle_catcher/proc/AddParticles(name, quantity = 1)
	if(parent && parent.size >= mysize)
		parent.AddParticles(name, quantity)
		return 1
	return 0

/obj/effect/fusion_particle_catcher/proc/UpdateSize()
	if(parent.size >= mysize)
		set_density(TRUE)
		name = "collector [mysize] ON"
	else
		set_density(FALSE)
		name = "collector [mysize] OFF"

/obj/effect/fusion_particle_catcher/bullet_act(obj/item/projectile/Proj)
	parent.AddEnergy(Proj.damage)
	return 0

/obj/effect/fusion_particle_catcher/CanPass(atom/movable/mover, turf/target)
	if(istype(mover, /obj/effect/accelerated_particle) || istype(mover, /obj/item/projectile/beam))
		return !density
	return TRUE
