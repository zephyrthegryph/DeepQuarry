/obj/structure/blob/factory/get_mechanics_info(list/additional_information)
	return ..(list("Creates hostile entities to attack enemies of the blob. It requires a 'node' blob nearby, or it will cease functioning.") + additional_information)

/obj/structure/blob/factory
	name = "factory blob"
	base_name = "factory"
	icon = 'icons/mob/blob.dmi'
	icon_state = "blob_factory"
	desc = "A thick spire of tendrils."
	max_integrity = 40
	health_regen = 1
	point_return = 25
	var/list/spores
	var/max_spores = 3
	var/spore_delay = 0
	var/spore_cooldown = 8 SECONDS

// its spores lose their factory or nest (spores is REL_PAIR_LIST with the mob's factory, blob.dm).

/obj/structure/blob/factory/pulsed()
	. = ..()
	if(length(spores) >= max_spores)
		return
	if(!COOLDOWN_FINISHED(src, spore_delay))
		return
	flick("blob_factory_glow", src)
	COOLDOWN_START(src, spore_delay, spore_cooldown)
	var/mob/living/simple_mob/blob/spore/S = null
	if(overmind)
		S = new overmind.blob_type.spore_type(src.loc, src)
		S.faction = overmind.blob_type.faction
		if(istype(S))
			rel_set(S, nameof(S.overmind), overmind)
			if(overmind.blob_type.ranged_spores)
				S.projectiletype = overmind.blob_type.spore_projectile
				S.projectilesound = overmind.blob_type.spore_firesound
				S.projectile_accuracy = overmind.blob_type.spore_accuracy
				S.projectile_dispersion = overmind.blob_type.spore_dispersion
		else //Other mobs don't add themselves in New. Ew.
			S.nest = src
			// spores is a pair list with /mob/living/simple_mob/blob.factory (blob.dm); a mob
			// without that var is not counted.
			if(istype(S, /mob/living/simple_mob/blob))
				rel_set(S, nameof(S.factory), src)
		S.update_icons()

/obj/structure/blob/factory/sluggish // Capable of producing MORE spores, but quite a bit slower than normal.
	name = "sluggish factory blob"
	max_spores = 4
	spore_cooldown = 16 SECONDS

/obj/structure/blob/factory/turret	// Produces a single spore slowly, but is intended to be used as a 'mortar' by the blob type.
	name = "volatile factory blob"
	max_spores = 1
	spore_cooldown = 10 SECONDS
