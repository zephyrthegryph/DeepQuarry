/obj/item/projectile/energy/blob //Not super strong.
	name = "spore"
	icon_state = "declone"
	damage = 3
	armor_penetration = 40
	injury_kind = INJURY_BLUNT
	pass_flags = PASSTABLE | PASSBLOB
	fire_sound = SFX_EFFECTS_SLIME_SQUISH
	var/splatter = FALSE			// Will this make a cloud of reagents?
	var/splatter_volume = 5			// The volume of its chemical container, for said cloud of reagents.

TYPE_TABLE_DECLARE(/obj/item/projectile/energy/blob, blob_projectile_chems, list(REAGENT_ID_MOLD))

/obj/item/projectile/energy/blob/splattering
	splatter = TRUE

CAPABILITIES(/obj/item/projectile/energy/blob/splattering)
	reagents(nameof(splatter_volume)) // the cloud it bursts into

/obj/item/projectile/energy/blob/Initialize(mapload)
	. = ..()
	if(splatter)
		ready_chemicals()

/obj/item/projectile/energy/blob/on_impact(atom/A)
	if(splatter)
		var/turf/location = get_turf(src)
		var/datum/effect/effect/system/smoke_spread/chem/blob/S = new /datum/effect/effect/system/smoke_spread/chem/blob
		S.attach(location)
		S.set_up(reagents, rand(1, splatter_volume), 0, location)
		play_sfx(location, SFX_EFFECTS_SLIME_SQUISH, 0.6, extrarange = -3)
		S.start()
	..()

/obj/item/projectile/energy/blob/proc/ready_chemicals()
	if(reagents)
		var/reagent_vol = (round((splatter_volume / length(TYPE_TABLE_GET(src, blob_projectile_chems))) * 100) / 100) //Cut it at the hundreds place, please.
		for(var/reagent in TYPE_TABLE_GET(src, blob_projectile_chems))
			reagents.add_reagent(reagent, reagent_vol)

/obj/item/projectile/energy/blob/toxic
	injury_kind = INJURY_TOXIN

TYPE_TABLE(/obj/item/projectile/energy/blob/toxic, blob_projectile_chems, list(REAGENT_ID_AMATOXIN))

/obj/item/projectile/energy/blob/toxic/splattering
	splatter = TRUE

/obj/item/projectile/energy/blob/acid
	injury_kind = INJURY_BURN

TYPE_TABLE(/obj/item/projectile/energy/blob/acid, blob_projectile_chems, list(REAGENT_ID_SACID, REAGENT_ID_MOLD))

/obj/item/projectile/energy/blob/acid/splattering
	splatter = TRUE

/obj/item/projectile/energy/blob/combustible
	splatter = TRUE
	flammability = 0.25

TYPE_TABLE(/obj/item/projectile/energy/blob/combustible, blob_projectile_chems, list(REAGENT_ID_FUEL, REAGENT_ID_MOLD))

/obj/item/projectile/energy/blob/freezing
	modifier_type_to_apply = /datum/body_effect/chilled
	modifier_duration = 0.25 MINUTE // Determined to be to long of a slowdown time.

TYPE_TABLE(/obj/item/projectile/energy/blob/freezing, blob_projectile_chems, list(REAGENT_ID_FROSTOIL))

/obj/item/projectile/energy/blob/freezing/splattering
	splatter = TRUE

/obj/item/projectile/bullet/thorn
	name = "spike"
	icon_state = "SpearFlight"
	damage = 20
	injury_kind = INJURY_CORROSIVE
	armor_penetration = 20
	penetrating = 3
	fire_sound = SFX_EFFECTS_SLIME_SQUISH
