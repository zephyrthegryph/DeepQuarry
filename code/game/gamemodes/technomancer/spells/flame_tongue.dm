/datum/technomancer/spell/flame_tongue
	name = "Flame Tongue"
	desc = "Using a miniturized flamethrower in your gloves, you can emit a flame strong enough to melt both your enemies and walls."
	cost = 50
	obj_path = /obj/item/spell/flame_tongue
	ability_icon_state = "tech_flametongue"
	category = OFFENSIVE_SPELLS

/obj/item/spell/flame_tongue
	name = "flame tongue"
	icon_state = "flame_tongue"
	desc = "Burn!"
	cast_methods = CAST_MELEE
	aspect = ASPECT_FIRE
	var/obj/item/weldingtool/spell/welder = null

CAPABILITIES(/obj/item/spell/flame_tongue)
	owns_one(nameof(welder), starts = /obj/item/weldingtool/spell)

/obj/item/spell/flame_tongue/Initialize(mapload, coreless)
	. = ..()
	set_light(3, 2, l_color = "#FF6A00")
	visible_message(span_warning("\The [loc]'s hand begins to emit a flame."))
	welder.setWelding(1)


/obj/item/weldingtool/spell
	name = "flame"
	eye_safety_modifier = 3

/// The spell welder never burns or regenerates fuel.
/obj/item/weldingtool/spell/burner_active(datum/act/A)
	return FALSE

//Needed to make the spell welder have infinite fuel.  Don't worry, it uses energy instead.
/obj/item/weldingtool/spell/remove_fuel()
	return 1

/obj/item/weldingtool/spell/eyecheck(mob/user as mob)
	return

/obj/item/spell/flame_tongue/on_melee_cast(atom/hit_atom, mob/living/user, def_zone, stance = I_HURT)
	if(isliving(hit_atom) && stance != I_HELP)
		var/mob/living/L = hit_atom
		if(pay_energy(1000))
			act_message(user, L, others = span_danger("%U% reaches out towards %T% with the flaming hand, and they ignite!"))
			to_chat(L, span_danger("You ignite!"))
			L.fire_act()
			add_attack_logs(user,L,"Ignited with [src]")
			adjust_instability(12)
	else
		//This is needed in order for the welder to work, and works similarly to grippers.
		welder.forceMove(user)
		var/resolved = hit_atom.attackby(welder, user)
		if(!resolved && welder && hit_atom)
			if(pay_energy(500))
				welder.attack(hit_atom, user, def_zone)
				adjust_instability(4)
		if(welder && user && (welder.loc == user))
			welder.forceMove(src)
		else
			rel_take(src, nameof(welder))
			consume(src, user)
			return
