/datum/spell/aoe_turf/conjure/construct
	name = "Artificer"
	desc = "This spell conjures a construct which may be controlled by Shades"

	school = "conjuration"
	charge_max = 600
	spell_flags = 0
	invocation = "none"
	invocation_type = SpI_NONE
	range = 0

	summon_type = list(/obj/structure/constructshell)

	hud_state = "artificer"

/datum/spell/aoe_turf/conjure/construct/lesser
	charge_max = 1800
	summon_type = list(/obj/structure/constructshell/cult)
	hud_state = "const_shell"
	override_base = "const"

/datum/spell/aoe_turf/conjure/floor
	name = "Floor Construction"
	desc = "This spell constructs a cult floor"

	charge_max = 20
	spell_flags = Z2NOCAST | CONSTRUCT_CHECK
	invocation = "none"
	invocation_type = SpI_NONE
	range = 0
	summon_type = list(/turf/simulated/floor/cult)

	hud_state = "const_floor"

/datum/spell/aoe_turf/conjure/floor/conjure_animation(atom/movable/overlay/animation, turf/target)
	animation.set_icon_state("cultfloor")
	flick("cultfloor",animation)
	animation.expire(1 SECOND)

/datum/spell/aoe_turf/conjure/wall
	name = "Lesser Construction"
	desc = "This spell constructs a cult wall"

	charge_max = 100
	spell_flags = Z2NOCAST | CONSTRUCT_CHECK
	invocation = "none"
	invocation_type = SpI_NONE
	range = 0
	summon_type = list(/turf/simulated/wall/cult)

	hud_state = "const_wall"

/datum/spell/aoe_turf/conjure/wall/conjure_animation(atom/movable/overlay/animation, turf/target)
	animation.set_icon_state("cultwall")
	flick("cultwall",animation)
	animation.expire(1 SECOND)

/datum/spell/aoe_turf/conjure/wall/reinforced
	name = "Greater Construction"
	desc = "This spell constructs a reinforced metal wall"

	charge_max = 300
	spell_flags = Z2NOCAST
	invocation = "none"
	invocation_type = SpI_NONE
	range = 0
	cast_delay = 50

	summon_type = list(/turf/simulated/wall/r_wall)

/datum/spell/aoe_turf/conjure/soulstone
	name = "Summon Soulstone"
	desc = "This spell reaches into Nar-Sie's realm, summoning one of the legendary fragments across time and space"

	charge_max = 3000
	spell_flags = 0
	invocation = "none"
	invocation_type = SpI_NONE
	range = 0

	summon_type = list(/obj/item/soulstone)

	hud_state = "const_stone"
	override_base = "const"

/datum/spell/aoe_turf/conjure/door
	name = "Stone Door"
	desc = "This spell conjures a massive stone door."

	charge_max = 100
	spell_flags = CONSTRUCT_CHECK
	invocation = "none"
	invocation_type = SpI_NONE
	range = 0

	summon_type = list(/obj/structure/simple_door/cult)

	hud_state = "const_door"

/datum/spell/aoe_turf/conjure/grille
	name = "Arcane Grille"
	desc = "This spell conjures an airtight grille."

	charge_max = 100
	spell_flags = CONSTRUCT_CHECK
	invocation = "none"
	invocation_type = SpI_NONE
	range = 0

	summon_type = list(/obj/structure/grille/cult)

	hud_state = "const_grille"

/datum/spell/aoe_turf/conjure/forcewall/lesser
	name = "Shield"
	desc = "Allows you to pull up a shield to protect yourself and allies from incoming threats"

	charge_max = 300
	spell_flags = 0
	invocation = "none"
	invocation_type = SpI_NONE
	range = 0
	summon_type = list(/obj/effect/forcefield/cult)
	duration = 200

	hud_state = "const_juggwall"

/*
 * Harvest has been disabled due to the lack of Nar'Sie. Here for posterity / future rework.
 */

/*
/datum/spell/targeted/harvest
	name = "Harvest"
	desc = "Back to where I come from, and you're coming with me."

	school = "transmutation"
	charge_max = 200
	spell_flags = Z2NOCAST | CONSTRUCT_CHECK | INCLUDEUSER
	invocation = ""
	invocation_type = SpI_NONE
	range = 0
	max_targets = 0

	overlay = 1
	overlay_icon = 'icons/effects/effects.dmi'
	overlay_icon_state = "rune_teleport"
	overlay_lifespan = 0

	hud_state = "const_harvest"

/datum/spell/targeted/harvest/cast(list/targets, mob/user)//because harvest is already a proc
	..()

	var/destination = null
	for(var/obj/singularity/narsie/large/N in REGISTRY_MEMBERS(REGISTRY_NARSIE))
		destination = N.loc
		break
	if(destination)
		var/prey = 0
		for(var/mob/living/M in targets)
			if(!findNullRod(M))
				M.forceMove(destination)
				if(M != user)
					prey = 1
		to_chat(user, span_sinister("You warp back to Nar-Sie[prey ? " along with your prey":""]."))
	else
		to_chat(user, span_danger("...something's wrong!")) //There shouldn't be an instance of Harvesters when Nar-Sie isn't in the world.
*/

/datum/spell/targeted/fortify
	name = "Fortify Shell"
	desc = "Emit a field of energy around your shell to reduce incoming damage incredibly, while decreasing your mobility."

	range = -1
	school = "evocation"
	charge_type = Sp_RECHARGE
	invocation_type = SpI_NONE

	spell_flags = CONSTRUCT_CHECK | INCLUDEUSER

	hud_state = "const_fortify"
	smoke_amt = 0

	charge_max = 600

/datum/spell/targeted/fortify/cast(list/targets, mob/living/user)
	if(findNullRod(user) || user.has_body_effect(/datum/body_effect/fortify))
		charge_counter = 400
		return
	user.apply_body_effect(/datum/body_effect/fortify, 1 MINUTES)

/datum/spell/targeted/occult_repair_aura
	name = "Repair Aura"
	desc = "Emit a field of energy around your shell to repair nearby constructs at range."

	range = -1
	school = "evocation"
	charge_type = Sp_RECHARGE
	invocation_type = SpI_NONE

	spell_flags = CONSTRUCT_CHECK | INCLUDEUSER

	hud_state = "const_repairaura"
	smoke_amt = 0

	charge_max = 600

/datum/spell/targeted/occult_repair_aura/cast(list/targets, mob/living/user)
	if(findNullRod(user) || user.has_body_effect(/datum/body_effect/repair_aura))
		charge_counter = 300
		return
	user.apply_body_effect(/datum/body_effect/repair_aura, 30 SECONDS)

/*
 *
 * These are the spells that place spell-objects into the construct's hands akin to technomancers.
 *
 */

/datum/spell/targeted/construct_advanced
	name = "Base Construct Spell"
	desc = "If you see this, please tell a developer!"

	range = -1
	school = "evocation"
	charge_type = Sp_RECHARGE
	invocation_type = SpI_NONE

	spell_flags = CONSTRUCT_CHECK | INCLUDEUSER

	hud_state = "const_rune"
	smoke_amt = 0

	charge_max = 10

	var/spell_obj = null //This is the var that determines what Technomancer-style spell is put into their hands.

/datum/spell/targeted/construct_advanced/cast(list/targets, mob/living/user)
	if(!findNullRod(user))
		user.place_spell_in_hand(spell_obj)

/datum/spell/targeted/construct_advanced/inversion_beam
	name = "Inversion Beam"
	desc = "Fire a searing beam of darkness at your foes."

	hud_state = "const_beam"
	spell_obj = /obj/item/spell/construct/projectile/inverted_beam

/datum/spell/targeted/construct_advanced/mend_acolyte
	name = "Mend Acolyte"
	desc = "Mend a target acolyte or construct over time."

	charge_max = 100

	hud_state = "const_mend"
	spell_obj = /obj/item/spell/construct/mend_occult

/datum/spell/targeted/construct_advanced/agonizing_sphere
	name = "Sphere of Agony"
	desc = "Rend a portal into a plane of naught but pain at the target location."

	charge_max = 100

	hud_state = "const_harvest"
	spell_obj = /obj/item/spell/construct/spawner/agonizing_sphere

/datum/spell/targeted/construct_advanced/slam
	name = "Slam"
	desc = "Empower your FIST."

	charge_max = 300

	hud_state = "const_fist"
	spell_obj = /obj/item/spell/construct/slam

////////////////////////////
//	Purity Construct - Bishop - Spells
////////////////////////////

/datum/spell/targeted/construct_advanced/crippling_beam
	name = "Crippling Beam"
	desc = "Fire a crippling beam to hold down your enemies or prey."

	hud_state = "const_beam"
	spell_obj = /obj/item/spell/construct/projectile/crippling_beam

/datum/spell/targeted/construct_advanced/banishment
	name = "banishment"
	desc = "Fire a searing beam of light, banishing unholy foes."

	hud_state = "const_beam"
	spell_obj = /obj/item/spell/construct/projectile/banishment

////////////////////////////
//	Purity Construct - Deacon - Spells
////////////////////////////

///Deacon Laser
/datum/spell/targeted/construct_advanced/force_beam
	name = "Force Beam"
	desc = "Fire a beam of kinetic energy to force back troublemakers."

	hud_state = "const_beam"
	spell_obj = /obj/item/spell/construct/projectile/force_beam

///Deacon Healing Sphere
/datum/spell/targeted/construct_advanced/soothing_sphere
	name = "Sphere of soothing"
	desc = "Rend a portal into a plane of sothing energy at the target location."

	charge_max = 100

	hud_state = "const_harvest"
	spell_obj = /obj/item/spell/construct/spawner/soothing_sphere

////////////////////////////
//	Purity Construct - Priest - Spells
////////////////////////////

/datum/spell/targeted/construct_advanced/mend_purity
	name = "Mend Purity"
	desc = "Mend a target living being or construct over time."

	charge_max = 100

	hud_state = "const_mend"
	spell_obj = /obj/item/spell/construct/mend_purity

/datum/spell/targeted/purity_repair_aura
	name = "Repair Aura"
	desc = "Emit a field of energy around your shell to repair nearby constructs at range."

	range = -1
	school = "evocation"
	charge_type = Sp_RECHARGE
	invocation_type = SpI_NONE

	spell_flags = CONSTRUCT_CHECK | INCLUDEUSER

	hud_state = "const_repairaura"
	smoke_amt = 0

	charge_max = 600

/datum/spell/targeted/purity_repair_aura/cast(list/targets, mob/living/user)
	if(findNullRod(user) || user.has_body_effect(/datum/body_effect/repair_aura))
		charge_counter = 300
		return
	user.apply_body_effect(/datum/body_effect/repair_aura_purity, 30 SECONDS)
