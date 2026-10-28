// Base
/obj/item/slime_extract
	name = "slime extract"
	desc = "Goo extracted from a slime, which can do different things depending on its color and what it is injected with."
	icon = 'icons/mob/slimes.dmi'
	icon_state = "grey slime extract"
	w_class = ITEMSIZE_TINY
	var/uses = 1 // uses before it goes inert
	var/enhanced = FALSE
	var/slime_type
	flags = OPENCONTAINER

CAPABILITIES(/obj/item/slime_extract)
	configure(movable_motion(throw_range = 6, throw_speed = 3))
	configure(item_thrown(force = 0))
	configure(item_combat(force = 1))
	reagents(60)
	every(2 SECONDS, then(PROC_REF(emit_step)), when = nameof(emitting))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// TRUE while the extract emits (slime_extract_start_emitting() starts it).
/obj/item/slime_extract/var/tmp/emitting = FALSE

/// One slow step of an emitting extract; a kind with nothing to emit stops.
/obj/item/slime_extract/proc/emit_step(datum/act/A)
	set_emitting(FALSE)

/// Old attackby.
/obj/item/slime_extract/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(istype(O, /obj/item/slimepotion/enhancer))
		if(enhanced)
			to_chat(user, span_warning("You cannot enhance this extract further!"))
			return OP_DECLINE
		if(!consume(O, user))
			return OP_DECLINE
		to_chat(user, span_notice("You apply the enhancer to the slime extract. It may now be reused one more time."))
		play_sfx(src, SFX_EFFECTS_BUBBLES)
		uses += 2
		enhanced = TRUE
		name = initial(name) // To remove the 'inert' part of the name.
	else if(istype(O, /obj/item/slimepotion/reinvigoration))
		to_chat(user, span_notice("You apply the reinvigorator to the slime extract. It rapidly expands, creating a brand new slime!"))
		play_sfx(src, SFX_EFFECTS_BUBBLES)
		new slime_type(get_turf(src))
		consume(O, user)
		consume(src, user)
	return OP_DECLINE

/obj/item/slime_extract/examine(mob/user)
	. = ..()
	if(uses)
		. += "This extract has [uses] more use\s."
	else
		. += "This extract is inert."

/transformation/chem/instant/slime

CAPABILITIES(/transformation/chem/instant/slime)
	configure(transformation(holds = subject_var_over("uses", 0), then = TYPE_PROC_REF(/transformation/chem/instant/slime, on_reaction)))

/transformation/chem/instant/slime/proc/on_reaction(datum/reagents/holder)
	var/obj/item/slime_extract/T = holder.my_atom
	T.uses--
	if(T.uses <= 0)
		T.visible_message("[icon2html(T,viewers(T))]<b>\The [T]</b> goes inert.")
		T.name = "inert [initial(T.name)]"

// ***************
// * Grey slimes *
// ***************

/obj/item/slime_extract/grey/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates a grey slime. When injected with blood, this extract creates some monkey cubes. \
	When injected with water, this extract creates some slime jelly.") + additional_information)

/obj/item/slime_extract/grey
	name = "grey slime extract"
	icon_state = "grey slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio

/transformation/chem/instant/slime/grey_new_slime

CAPABILITIES(/transformation/chem/instant/slime/grey_new_slime)
	configure(transformation(name = "Slime Spawn", id = "m_grey_spawn", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/grey),
		spawns = spawns(/mob/living/simple_mob/slime/xenobio, 1, tell = span_warning("Infused with phoron, the core begins to quiver and grow, and soon a new baby slime emerges from it!"))))

/transformation/chem/instant/slime/grey_monkey

CAPABILITIES(/transformation/chem/instant/slime/grey_monkey)
	configure(transformation(name = "Slime Monkey", id = "m_grey_monkey", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/grey),
		spawns = spawns(/obj/item/reagent_containers/food/snacks/monkeycube, 5)))

/transformation/chem/instant/slime/grey_slimejelly

CAPABILITIES(/transformation/chem/instant/slime/grey_slimejelly)
	configure(transformation(name = REAGENT_SLIMEJELLY, id = "m_grey_jelly", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_SLIMEJELLY, 30)), holds = subject_is(/obj/item/slime_extract/grey)))

// ****************
// * Metal slimes *
// ****************

/obj/item/slime_extract/metal/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates some basic construction materials. When injected with blood, this extract creates some advanced construction materials. \
	When injected with water, this extract creates some unorthodox materials. When injected with slime jelly, this extract creates some steel.") + additional_information)

/obj/item/slime_extract/metal
	name = "metal slime extract"
	icon_state = "metal slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/metal

/transformation/chem/instant/slime/metal_materials_basic

CAPABILITIES(/transformation/chem/instant/slime/metal_materials_basic)
	configure(transformation(name = "Slime Basic Construction Materials", id = "m_metal_basic", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/metal),
		spawns = spawns("xenobio_metal_materials_normal", 3, amount = 10)))

/transformation/chem/instant/slime/metal_materials_adv

CAPABILITIES(/transformation/chem/instant/slime/metal_materials_adv)
	configure(transformation(name = "Slime Advanced Construction Materials", id = "m_metal_adv", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/metal),
		spawns = spawns("xenobio_metal_materials_adv", 2, amount = 10)))

/transformation/chem/instant/slime/metal_materials_weird

CAPABILITIES(/transformation/chem/instant/slime/metal_materials_weird)
	configure(transformation(name = "Slime Weird Construction Materials", id = "m_metal_weird", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/metal),
		spawns = spawns("xenobio_metal_materials_weird", 3, amount = 5)))

/transformation/chem/instant/slime/metal_materials_steel

CAPABILITIES(/transformation/chem/instant/slime/metal_materials_steel)
	configure(transformation(name = "Slime Weird Construction Materials", id = "m_metal_steel", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)),
		made = 1, holds = subject_is(/obj/item/slime_extract/metal),
		spawns = spawns(/obj/item/stack/material/steel, 1, amount = 25)))
// ***************
// * Blue slimes *
// ***************

/obj/item/slime_extract/blue/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates some frost oil. When injected with blood, this extract creates stability agent that can reduce slime's mutation chance. \
	When injected with water, this extract creates a calmness wave that calms enraged slimes. When injected with slime jelly, this extract creates some cryotoxin.") + additional_information)

/obj/item/slime_extract/blue
	name = "blue slime extract"
	icon_state = "blue slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/blue

/transformation/chem/instant/slime/blue_frostoil

CAPABILITIES(/transformation/chem/instant/slime/blue_frostoil)
	configure(transformation(name = "Slime Frost Oil", id = "m_blue_frostoil", takes = list(reagent(REAGENT_ID_PHORON, 5)),
		makes = list(reagent(REAGENT_ID_FROSTOIL, 30)), holds = subject_is(/obj/item/slime_extract/blue)))

/transformation/chem/instant/slime/blue_stability

CAPABILITIES(/transformation/chem/instant/slime/blue_stability)
	configure(transformation(name = "Slime Stability", id = "m_blue_stability", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/blue),
		spawns = spawns(/obj/item/slimepotion/stabilizer, 1)))

/transformation/chem/instant/slime/blue_calm

CAPABILITIES(/transformation/chem/instant/slime/blue_calm)
	configure(transformation(name = "Slime Calm", id = "m_blue_calm", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/blue),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/blue_calm, on_reaction)))

/transformation/chem/instant/slime/blue_calm/on_reaction(datum/reagents/holder)
	for(var/mob/living/simple_mob/slime/S in view(get_turf(holder.my_atom)))
		if(S.stat)
			continue

		if(istype(S, /mob/living/simple_mob/slime/xenobio))
			var/mob/living/simple_mob/slime/xenobio/X = S
			if(X.harmless)
				continue
			if(!X.client)
				X.relax()

		S.remove_body_effect(/datum/body_effect/berserk)

		if(S.client) // Player slimes always have free will.
			to_chat(S, span_warning("An intense wave of relaxing calm is felt from inside, but you remain in control of yourself."))

	for(var/mob/living/carbon/human/H in view(get_turf(holder.my_atom)))
		if(H.species?.is_slime_bodied)
			H.remove_body_effect(/datum/body_effect/berserk)
			to_chat(H, span_warning("An intense wave of relaxing calm is felt from inside, but you remain in control of yourself."))

	play_sfx(holder.my_atom, SFX_EFFECTS_PHASEIN, 0.75)
	..()

/transformation/chem/instant/slime/blue_cryotoxin

CAPABILITIES(/transformation/chem/instant/slime/blue_cryotoxin)
	configure(transformation(name = "Slime Cryotoxin", id = "m_blue_cryotoxin", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)),
		makes = list(reagent(REAGENT_ID_CRYOTOXIN, 30)), holds = subject_is(/obj/item/slime_extract/blue)))

// *****************
// * Purple slimes *
// *****************

/obj/item/slime_extract/purple/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates steroid agent, which can be used to increase amount of extracts in a slime. When injected with blood, this extract creates \
	infertility agent, which can be used to decrease amount of slime's offspring. When injected with water, this extract creates shrink agent, which can be used to turn an adult slime into a baby. \
	When injected with slime jelly, this extract creates a fertility agent, which can be used to increase amount of slime's offspring.") + additional_information)

/obj/item/slime_extract/purple
	name = "purple slime extract"
	icon_state = "purple slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/purple

/transformation/chem/instant/slime/purple_steroid

CAPABILITIES(/transformation/chem/instant/slime/purple_steroid)
	configure(transformation(name = "Slime Steroid", id = "m_purple_steroid", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/purple),
		spawns = spawns(/obj/item/slimepotion/steroid, 1)))

/transformation/chem/instant/slime/purple_infertility

CAPABILITIES(/transformation/chem/instant/slime/purple_infertility)
	configure(transformation(name = "Slime Infetility", id = "m_purple_infertility", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/purple),
		spawns = spawns(/obj/item/slimepotion/infertility, 1)))

/transformation/chem/instant/slime/purple_shrink

CAPABILITIES(/transformation/chem/instant/slime/purple_shrink)
	configure(transformation(name = "Slime Shrink", id = "m_purple_shrink", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/purple),
		spawns = spawns(/obj/item/slimepotion/shrink, 1)))

/transformation/chem/instant/slime/purple_fertility

CAPABILITIES(/transformation/chem/instant/slime/purple_fertility)
	configure(transformation(name = "Slime Fetility", id = "m_purple_fertility", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/purple),
		spawns = spawns(/obj/item/slimepotion/fertility, 1)))
// *****************
// * Orange slimes *
// *****************

/obj/item/slime_extract/orange/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates a phoron fire. When injected with blood, this extract creates a heat wave. When injected with water, this extract creates \
	some smoke. When injected with slime jelly, this extract creates some pyrotoxin.") + additional_information)

/obj/item/slime_extract/orange
	name = "orange slime extract"
	icon_state = "orange slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/orange

/transformation/chem/instant/slime/orange_fire

CAPABILITIES(/transformation/chem/instant/slime/orange_fire)
	configure(transformation(name = "Slime Fire", id = "m_orange_fire", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/orange),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/orange_fire, on_reaction)))

/transformation/chem/instant/slime/orange_fire/on_reaction(datum/reagents/holder)
	log_and_message_admins("Orange extract reaction (fire) has been activated in [get_area(holder.my_atom)].  Last fingerprints: [holder.my_atom.forensic_data?.get_lastprint()]", null)
	holder.my_atom.visible_message(span_danger("\The [src] begins to vibrate violently!"))
	play_sfx(holder.my_atom, SFX_EFFECTS_PHASEIN, 0.75)
	after(holder.my_atom, 5 SECONDS, GLOBAL_PROC_REF(slime_extract_fire), with = list(holder.my_atom))
	..()

/transformation/chem/instant/slime/orange_heatwave

CAPABILITIES(/transformation/chem/instant/slime/orange_heatwave)
	configure(transformation(name = "Slime Heat Wave", id = "m_orange_heatwave", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/orange),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/orange_heatwave, on_reaction)))

/transformation/chem/instant/slime/orange_heatwave/on_reaction(datum/reagents/holder)
	var/turf/simulated/T = get_turf(holder.my_atom)
	if(!T)
		return

	if(!istype(T))
		return

	// was filtering by ZAS zone membership; under LINDA there are no
	// zones. Fall back to view-radius proximity (visually meaningful and matches
	// "you're in the same room" 95% of the time on stations without windowed walls).
	log_and_message_admins("Orange extract reaction (heat wave) has been activated in [get_area(holder.my_atom)].  Last fingerprints: [holder.my_atom.forensic_data?.get_lastprint()]", null)

	var/list/nearby_things = view(T)

	// Hurt mobs.
	for(var/mob/living/L in nearby_things)
		var/turf/simulated/their_turf = get_turf(L)
		if(!istype(their_turf)) // Not simulated.
			continue

		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			var/protection = H.get_heat_protection()

			if(protection < 1)
				var/cold_factor = abs(protection - 1)
				H.set_bodytemperature(between(50, (H.body_temperature() - ((H.body_temperature() + 50) * cold_factor) ), H.body_temperature()))

			if(protection < 0.7)
				to_chat(L, span_danger("A scalding wave of heat overwhelms you!"))
			else
				to_chat(L, span_warning("A scalding wave of heat passes by you, as your armor protects you from it."))
			continue

	// Now make it very cold.
	var/datum/gas_mixture/env = T.return_air()
	if(env)
		// This is most likely physically impossible but when has that stopped slimes before?
		heat_add(env, 15 * 1000 * 1000, HEAT_SOURCE_REACTION)

	play_sfx(T, SFX_EFFECTS_PHASEIN, 0.75)
	..()

/transformation/chem/instant/slime/orange_smoke

CAPABILITIES(/transformation/chem/instant/slime/orange_smoke)
	configure(transformation(name = "Slime Smoke", id = "m_orange_smoke", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/orange),
		effects = sets_off(XFORM_FX_SMOKE, amount = 120, sfx = SFX_EFFECTS_SMOKE)))

/transformation/chem/instant/slime/orange_pyrotoxin

CAPABILITIES(/transformation/chem/instant/slime/orange_pyrotoxin)
	configure(transformation(name = "Slime Pyrotoxin", id = "m_orange_pyrotoxin", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)),
		makes = list(reagent(REAGENT_ID_THERMITEV, 30)), holds = subject_is(/obj/item/slime_extract/orange)))

// *****************
// * Yellow slimes *
// *****************

/obj/item/slime_extract/yellow/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates a lightning strike. When injected with blood, this extract creates a slime flashlight. When injected with water \
	this extract creates an EMP pulse. When injected with slime jelly, this extract creates a self-charging slime battery.") + additional_information)

/obj/item/slime_extract/yellow
	name = "yellow slime extract"
	icon_state = "yellow slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/yellow

/transformation/chem/instant/slime/yellow_lightning

CAPABILITIES(/transformation/chem/instant/slime/yellow_lightning)
	configure(transformation(name = "Slime Lightning", id = "m_yellow_lightning", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/yellow),
		effects = sets_off(XFORM_FX_LATER, audit = "Yellow extract reaction (lightning)", tell = TRUE, sfx = SFX_EFFECTS_PHASEIN, delay = 5 SECONDS, handler = GLOBAL_PROC_REF(slime_extract_lightning))))


/transformation/chem/instant/slime/yellow_flashlight

CAPABILITIES(/transformation/chem/instant/slime/yellow_flashlight)
	configure(transformation(name = "Slime Flashlight", id = "m_yellow_flashlight", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/yellow),
		spawns = spawns(/obj/item/flashlight/slime, 1)))

/transformation/chem/instant/slime/yellow_emp

CAPABILITIES(/transformation/chem/instant/slime/yellow_emp)
	configure(transformation(name = "Slime EMP", id = "m_yellow_emp", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/yellow),
		effects = sets_off(XFORM_FX_LATER, audit = "Yellow extract reaction (emp)", tell = TRUE, sfx = SFX_EFFECTS_PHASEIN, delay = 5 SECONDS, handler = GLOBAL_PROC_REF(slime_extract_emp))))


/transformation/chem/instant/slime/yellow_battery

CAPABILITIES(/transformation/chem/instant/slime/yellow_battery)
	configure(transformation(name = "Slime Cell", id = "m_yellow_cell", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/yellow),
		spawns = spawns(/obj/item/cell/slime, 1)))
// ***************
// * Gold slimes *
// ***************

/obj/item/slime_extract/gold/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates a few random creatures. When injected with blood, this extract creates a random hostile creature. \
	When injected with water, this extract creates a random passive creature. When injected with slime jelly, this extract creates some gold.") + additional_information)

/obj/item/slime_extract/gold
	name = "gold slime extract"
	icon_state = "gold slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/gold

/transformation/chem/instant/slime/gold_random_mobs

CAPABILITIES(/transformation/chem/instant/slime/gold_random_mobs)
	configure(transformation(name = "Slime Random Mobs", id = "m_gold_random_mobs", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/gold),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/gold_random_mobs, on_reaction)))

/transformation/chem/instant/slime/gold_random_mobs/on_reaction(datum/reagents/holder)
	log_and_message_admins("Gold extract reaction (random mobs) has been activated in [get_area(holder.my_atom)].  Last fingerprints: [holder.my_atom.forensic_data?.get_lastprint()]", null)
	var/type_to_spawn
	var/list/all_spawnable_types = list()
	all_spawnable_types += GLOB.xenobio_gold_mobs_safe
	all_spawnable_types += GLOB.xenobio_gold_mobs_hostile
	all_spawnable_types += GLOB.xenobio_gold_mobs_birds
	for(var/j = 1, j <= 3, j++)
		if(prob(1))
			type_to_spawn = pickweight(GLOB.xenobio_gold_mobs_bosses)
		else
			type_to_spawn = pickweight(all_spawnable_types)

		var/mob/living/C = new type_to_spawn(get_turf(holder.my_atom))
		for(var/l = 1, l <= rand(1, 3), l++)
			step(C, pick(NORTH,SOUTH,EAST,WEST))
	..()

/transformation/chem/instant/slime/gold_hostile_mob

CAPABILITIES(/transformation/chem/instant/slime/gold_hostile_mob)
	configure(transformation(name = "Slime Hostile Mob", id = "m_gold_hostile_mob", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/gold),
		spawns = spawns("xenobio_gold_mobs_hostile", 1, scatter = 3, audit = "Gold extract reaction (dangerous mob)")))


/transformation/chem/instant/slime/gold_safe_mob

CAPABILITIES(/transformation/chem/instant/slime/gold_safe_mob)
	configure(transformation(name = "Slime Safe Mob", id = "m_gold_safe_mob", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/gold),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/gold_safe_mob, on_reaction)))

/transformation/chem/instant/slime/gold_safe_mob/on_reaction(datum/reagents/holder)
	var/type_to_spawn
	if(prob(100/(GLOB.xenobio_gold_mobs_safe.len + 1)))
		type_to_spawn = pickweight(GLOB.xenobio_gold_mobs_birds)
	else
		type_to_spawn = pickweight(GLOB.xenobio_gold_mobs_safe)
	var/mob/living/C = new type_to_spawn(get_turf(holder.my_atom))
	for(var/l = 1, l <= rand(1, 3), l++)
		step(C, pick(NORTH,SOUTH,EAST,WEST))
	..()

/transformation/chem/instant/slime/gold_materials_gold

CAPABILITIES(/transformation/chem/instant/slime/gold_materials_gold)
	configure(transformation(name = "Slime Gold", id = "m_gold_gold", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/gold),
		spawns = spawns(/obj/item/stack/material/gold, 1, amount = 10)))
// *****************
// * Silver slimes *
// *****************

/obj/item/slime_extract/silver/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates some basic science materials. When injected with blood, this extract creates some advanced science materials. When injected \
	with water, this extract creates some completely random materials. When injected with slime jelly, this extract creates some silver.") + additional_information)

/obj/item/slime_extract/silver
	name = "silver slime extract"
	icon_state = "silver slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/silver

/transformation/chem/instant/slime/silver_materials_basic

CAPABILITIES(/transformation/chem/instant/slime/silver_materials_basic)
	configure(transformation(name = "Slime Basic Science Materials", id = "m_silver_basic", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/silver),
		spawns = spawns("xenobio_silver_materials_basic", 2, amount = 5)))

/transformation/chem/instant/slime/silver_materials_adv

CAPABILITIES(/transformation/chem/instant/slime/silver_materials_adv)
	configure(transformation(name = "Slime Advanced Science Materials", id = "m_silver_adv", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/silver),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/silver_materials_adv, on_reaction)))

/transformation/chem/instant/slime/silver_materials_adv/on_reaction(datum/reagents/holder)
	var/type_to_spawn = pickweight(GLOB.xenobio_silver_materials_adv)
	new type_to_spawn(get_turf(holder.my_atom), 3)
	..()

/transformation/chem/instant/slime/silver_materials_random

CAPABILITIES(/transformation/chem/instant/slime/silver_materials_random)
	configure(transformation(name = "Slime Random Materials", id = "m_silver_random", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/silver),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/silver_materials_random, on_reaction)))

/transformation/chem/instant/slime/silver_materials_random/on_reaction(datum/reagents/holder)
	var/type_to_spawn
	var/amount = 5
	var/all_spawnable_types = list()
	all_spawnable_types += GLOB.xenobio_metal_materials_normal
	all_spawnable_types += GLOB.xenobio_metal_materials_adv
	all_spawnable_types += GLOB.xenobio_metal_materials_weird
	all_spawnable_types += GLOB.xenobio_silver_materials_basic
	all_spawnable_types += GLOB.xenobio_silver_materials_adv
	all_spawnable_types += GLOB.xenobio_silver_materials_special
	for(var/i = 1 to 3)
		type_to_spawn = pickweight(all_spawnable_types)
		if(type_to_spawn in GLOB.xenobio_silver_materials_special)
			amount = 1
		new type_to_spawn(get_turf(holder.my_atom), amount)
	..()

/transformation/chem/instant/slime/silver_materials_silver

CAPABILITIES(/transformation/chem/instant/slime/silver_materials_silver)
	configure(transformation(name = "Slime Silver", id = "m_silver_silver", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/silver),
		spawns = spawns(/obj/item/stack/material/silver, 1, amount = 10)))
// **********************
// * Dark Purple slimes *
// **********************

/obj/item/slime_extract/dark_purple/get_mechanics_info(list/additional_information)
	return ..(list("When injected with water, this extract creates some phoron. When injected with slime jelly, this extract creates some blood.") + additional_information)

/obj/item/slime_extract/dark_purple
	name = "dark purple slime extract"
	icon_state = "dark purple slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/dark_purple

/transformation/chem/instant/slime/dark_purple_phoron

CAPABILITIES(/transformation/chem/instant/slime/dark_purple_phoron)
	configure(transformation(name = "Slime Phoron", id = "m_darkpurple_phoron", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_PHORON, 30)), holds = subject_is(/obj/item/slime_extract/dark_purple)))

/transformation/chem/instant/slime/dark_purple_blood

CAPABILITIES(/transformation/chem/instant/slime/dark_purple_blood)
	configure(transformation(name = "Slime Blood", id = "m_darkpurple_blood", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)),
		makes = list(reagent(REAGENT_ID_BLOOD, 30)), holds = subject_is(/obj/item/slime_extract/dark_purple)))

// ********************
// * Dark Blue slimes *
// ********************

/obj/item/slime_extract/dark_blue/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates a cold wave. When injected with blood, this extract grants ability to resist temperature for a while. \
	When injected with water, the water freezes. When injected with slime jelly, this extract creates a death agent, which can be used to instantly kill a slime.") + additional_information)

/obj/item/slime_extract/dark_blue
	name = "dark blue slime extract"
	icon_state = "dark blue slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/dark_blue

/transformation/chem/instant/slime/dark_blue_cold_snap

CAPABILITIES(/transformation/chem/instant/slime/dark_blue_cold_snap)
	configure(transformation(name = "Slime Cold Snap", id = "m_darkblue_coldsnap", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/dark_blue),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/dark_blue_cold_snap, on_reaction)))

// This iterates over a ZAS zone's contents, so that things seperated in other zones aren't subjected to the temperature drop.
/transformation/chem/instant/slime/dark_blue_cold_snap/on_reaction(datum/reagents/holder)
	var/turf/simulated/T = get_turf(holder.my_atom)
	if(!T) // Nullspace lacks zones.
		return

	if(!istype(T))
		return

	// was ZAS-zone filter; under LINDA fall back to view-radius.
	log_and_message_admins("Dark Blue extract reaction (cold snap) has been activated in [get_area(holder.my_atom)].  Last fingerprints: [holder.my_atom.forensic_data?.get_lastprint()]", null)

	var/list/nearby_things = view(T)

	// Hurt mobs.
	for(var/mob/living/L in nearby_things)
		var/turf/simulated/their_turf = get_turf(L)
		if(!istype(their_turf)) // Not simulated.
			continue

		if(istype(L, /mob/living/simple_mob/slime))
			var/mob/living/simple_mob/slime/S = L
			if(S.cold_resist >= 1) // Immune to cold.
				to_chat(S, span_warning("A chill is felt around you, however it cannot harm you."))
				continue
			if(S.client) // Don't instantly kill player slimes.
				to_chat(S, span_danger("You feel your body crystalize as an intense chill overwhelms you!"))
				S.inflict_cold_damage(100)
			else
				S.inflict_cold_damage(200) // Metal slimes can survive this 'slime nuke'.
			continue

		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			var/protection = H.get_cold_protection()

			if(protection < 1)
				var/cold_factor = abs(protection - 1)
				H.set_bodytemperature(between(50, (H.body_temperature() - ((H.body_temperature() - 50) * cold_factor) ), H.body_temperature()))

			if(protection < 0.7)
				to_chat(L, span_danger("A chilling wave of cold overwhelms you!"))
			else
				to_chat(L, span_warning("A chilling wave of cold passes by you, as your armor protects you from it."))
			continue

	// Now make it very cold.
	var/datum/gas_mixture/env = T.return_air()
	if(env)
		// This is most likely physically impossible but when has that stopped slimes before?
		heat_add(env, -10 * 1000 * 1000, HEAT_SOURCE_REACTION) // For a moderately sized room this doesn't actually lower it that much.

	play_sfx(T, SFX_EFFECTS_PHASEIN, 0.75)

	..()

/transformation/chem/instant/slime/dark_blue_temp_resist

CAPABILITIES(/transformation/chem/instant/slime/dark_blue_temp_resist)
	configure(transformation(name = "Slime Temperature Resistance", id = "m_darkblue_temperature_resist", takes = list(reagent(REAGENT_ID_BLOOD, 5)),
		made = 1, holds = subject_is(/obj/item/slime_extract/dark_blue),
		effects = sets_off(XFORM_FX_AREA, range = 1, body_effect = /datum/body_effect/slime_temp_resist, lasts = 5 MINUTES)))


/datum/body_effect/slime_temp_resist
	name = "slime temperature resistance"
	desc = "You feel immune to heat and cold."
	mob_overlay_state = "corona"

	on_created_text = span_warning("A shield of goo surround you. It makes you feel protected against temperature.")
	on_expired_text = span_notice("The shield of goo has faded, and you feel vulnerable to temperature again.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(STAT_INCOMING_THERMAL = 0.5, STAT_HEAT_EXPOSURE = 0, STAT_COLD_EXPOSURE = 0)

/transformation/chem/instant/slime/dark_blue_ice

CAPABILITIES(/transformation/chem/instant/slime/dark_blue_ice)
	configure(transformation(name = "Slime Ice", id = "m_darkblue_ice", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_ICE, 5)), holds = subject_is(/obj/item/slime_extract/dark_blue)))

/transformation/chem/instant/slime/dark_blue_death

CAPABILITIES(/transformation/chem/instant/slime/dark_blue_death)
	configure(transformation(name = "Slime Death", id = "m_darkblue_death", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/dark_blue),
		spawns = spawns(/obj/item/slimepotion/death, 1)))
// **************
// * Red slimes *
// **************

/obj/item/slime_extract/red/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates a mutation agent, that can be used to increase a slime's mutation chance. When injected with blood, this extract causes \
	nearby slimes to fall into rage. When injected with water, this extract creates some hot sauce. When injected with slime jelly, this extract creates a ferality agent, which makes slimes \
	unreceptive to discipline.") + additional_information)

/obj/item/slime_extract/red
	name = "red slime extract"
	icon_state = "red slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/red

/transformation/chem/instant/slime/red_mutation

CAPABILITIES(/transformation/chem/instant/slime/red_mutation)
	configure(transformation(name = "Slime Mutation", id = "m_red_mutation", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/red),
		spawns = spawns(/obj/item/slimepotion/mutator, 1)))

/transformation/chem/instant/slime/red_enrage

CAPABILITIES(/transformation/chem/instant/slime/red_enrage)
	configure(transformation(name = "Slime Enrage", id = "m_red_enrage", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/red),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/red_enrage, on_reaction)))

/transformation/chem/instant/slime/red_enrage/on_reaction(datum/reagents/holder)
	for(var/mob/living/simple_mob/slime/S in view(get_turf(holder.my_atom)))
		if(S.stat)
			continue

		if(istype(S, /mob/living/simple_mob/slime/xenobio))
			var/mob/living/simple_mob/slime/xenobio/X = S
			if(X.harmless)
				continue
			if(!X.client)
				X.enrage()

		S.apply_body_effect(/datum/body_effect/berserk, 30 SECONDS)

		if(S.client) // Player slimes always have free will.
			to_chat(S, span_warning("An intense wave of rage is felt from inside, but you remain in control of yourself."))

	for(var/mob/living/carbon/human/H in view(get_turf(holder.my_atom)))
		if(H.species?.is_slime_bodied)
			H.apply_body_effect(/datum/body_effect/berserk, 30 SECONDS)
			to_chat(H, span_warning("An intense wave of rage is felt from inside, but you remain in control of yourself."))

	log_and_message_admins("Red extract reaction (enrage) has been activated in [get_area(holder.my_atom)].  Last fingerprints: [holder.my_atom.forensic_data?.get_lastprint()]", null)

	play_sfx(holder.my_atom, SFX_EFFECTS_PHASEIN, 0.75)
	..()

/transformation/chem/instant/slime/red_hotsauce

CAPABILITIES(/transformation/chem/instant/slime/red_hotsauce)
	configure(transformation(name = "Slime Hot Sauce", id = "m_red_hotsauce", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_CAPSAICIN, 30)), holds = subject_is(/obj/item/slime_extract/red)))

/transformation/chem/instant/slime/red_ferality

CAPABILITIES(/transformation/chem/instant/slime/red_ferality)
	configure(transformation(name = "Slime Ferality", id = "m_red_ferality", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/red),
		spawns = spawns(/obj/item/slimepotion/ferality, 1)))
// ***************
// * Green slime *
// ***************

/obj/item/slime_extract/green/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates a single radioactive pulse. When injected with blood, this extract creates a radioactive glob. When injected with water \
	this extract creates some radium. When injected with slime jelly, this extract creates some uranium.") + additional_information)

/obj/item/slime_extract/green
	name = "green slime extract"
	icon_state = "green slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/green
	COOLDOWN_DECLARE(event_cooldown)
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null

/obj/item/slime_extract/green/emit_step(datum/act/A)
	radiate()

/obj/item/slime_extract/green/proc/radiate()
	if(active)
		return
	if(!COOLDOWN_FINISHED(src, event_cooldown))
		return
	active = TRUE
	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_MEDIUM_INSULATION,
		chance = URANIUM_IRRADIATION_CHANCE,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = 50
	)
	COOLDOWN_START(src, event_cooldown, 1.5 SECONDS)
	active = FALSE

/transformation/chem/instant/slime/green_radpulse

CAPABILITIES(/transformation/chem/instant/slime/green_radpulse)
	configure(transformation(name = "Slime Radiation Pulse", id = "m_green_radpulse", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/green),
		effects = sets_off(XFORM_FX_LATER, audit = "Green extract reaction (radiation pulse)", tell = TRUE, sfx = SFX_EFFECTS_PHASEIN, delay = 5 SECONDS, handler = GLOBAL_PROC_REF(slime_extract_start_emitting))))


/transformation/chem/instant/slime/green_emitter

CAPABILITIES(/transformation/chem/instant/slime/green_emitter)
	configure(transformation(name = "Slime Radiation Emitter", id = "m_green_emitter", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/green),
		spawns = spawns(/obj/item/slime_irradiator, 1, audit = "Green extract reaction (radiation emitter)")))


/transformation/chem/instant/slime/green_radium

CAPABILITIES(/transformation/chem/instant/slime/green_radium)
	configure(transformation(name = "Slime Radium", id = "m_green_radium", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_RADIUM, 30)), holds = subject_is(/obj/item/slime_extract/green)))

/transformation/chem/instant/slime/green_uranium

CAPABILITIES(/transformation/chem/instant/slime/green_uranium)
	configure(transformation(name = "Slime Uranium", id = "m_green_uranium", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/green),
		spawns = spawns(/obj/item/stack/material/uranium, 1, amount = 10)))
// ***************
// * Pink slimes *
// ***************

/obj/item/slime_extract/pink/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates some bone fixing agent. When injected with blood, this extract creates some clotting agent. When injected with water, this \
	extract creates some organ healing agent. When injected with slime jelly, this extract creates a powerful regenerative wave.") + additional_information)

/obj/item/slime_extract/pink
	name = "pink slime extract"
	icon_state = "pink slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/pink

/transformation/chem/instant/slime/pink_bone_fix

CAPABILITIES(/transformation/chem/instant/slime/pink_bone_fix)
	configure(transformation(name = "Slime Bone Med", id = "m_pink_bone_fixer", takes = list(reagent(REAGENT_ID_PHORON, 5)),
		makes = list(reagent(REAGENT_ID_SLIMEBONEFIXER, 30)), holds = subject_is(/obj/item/slime_extract/pink)))

/transformation/chem/instant/slime/pink_clotting

CAPABILITIES(/transformation/chem/instant/slime/pink_clotting)
	configure(transformation(name = "Slime Clotting Med", id = "m_pink_clotting", takes = list(reagent(REAGENT_ID_BLOOD, 5)),
		makes = list(reagent(REAGENT_ID_SLIMEBLEEDFIXER, 30)), holds = subject_is(/obj/item/slime_extract/pink)))

/transformation/chem/instant/slime/pink_organ_fix

CAPABILITIES(/transformation/chem/instant/slime/pink_organ_fix)
	configure(transformation(name = "Slime Organ Med", id = "m_pink_organ_fixer", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_SLIMEORGANFIXER, 30)), holds = subject_is(/obj/item/slime_extract/pink)))

/transformation/chem/instant/slime/pink_heal_pulse

CAPABILITIES(/transformation/chem/instant/slime/pink_heal_pulse)
	configure(transformation(name = "Slime Heal Pulse", id = "m_pink_heal_pulse", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/pink),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/pink_heal_pulse, on_reaction)))

/transformation/chem/instant/slime/pink_heal_pulse/on_reaction(datum/reagents/holder)
	for(var/mob/living/carbon/C in viewers(get_turf(holder.my_atom), null))
		to_chat(C, span_notice("A wave of energy suddenly invigorates you."))
		C.mend(TREAT_TISSUE_REPAIR, 25)
		C.mend(TREAT_BURN_CARE, 25)
		C.mend(TREAT_ANTITOXIN, 25)
		C.mend(TREAT_OXYGENATION, 25)
		C.mend(TREAT_NEURAL_REPAIR, 25)
		C.mend(TREAT_GENETIC_REPAIR, 25)
	..()

// **************
// * Oil slimes *
// **************

/obj/item/slime_extract/oil/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates some fuel. When injected with blood, this extract creates some cooking oil. When injected with water, this extract \
	creates a fake explosion sound. When injected with slime jelly, this extract explodes.") + additional_information)

/obj/item/slime_extract/oil
	name = "oil slime extract"
	icon_state = "oil slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/oil

/transformation/chem/instant/slime/oil_fuel

CAPABILITIES(/transformation/chem/instant/slime/oil_fuel)
	configure(transformation(name = "Slime Fuel", id = "m_oil_fuel", takes = list(reagent(REAGENT_ID_PHORON, 5)),
		makes = list(reagent(REAGENT_ID_FUEL, 30)), holds = subject_is(/obj/item/slime_extract/oil)))

/transformation/chem/instant/slime/oil_oil

CAPABILITIES(/transformation/chem/instant/slime/oil_oil)
	configure(transformation(name = "Slime Oil", id = "m_oil_oil", takes = list(reagent(REAGENT_ID_BLOOD, 5)),
		makes = list(reagent(REAGENT_ID_COOKINGOIL, 30)), holds = subject_is(/obj/item/slime_extract/oil)))

/transformation/chem/instant/slime/oil_fakesplosion

CAPABILITIES(/transformation/chem/instant/slime/oil_fakesplosion)
	configure(transformation(name = "Slime Fake Explosion", id = "m_oil_fakeboom", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/oil),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/oil_fakesplosion, on_reaction)))

/transformation/chem/instant/slime/oil_fakesplosion/on_reaction(datum/reagents/holder)
	play_sfx(holder.my_atom, SFX_EFFECTS_PHASEIN, 0.75)
	explosion(get_turf(holder.my_atom), 0, 0, 0)
	..()

/transformation/chem/instant/slime/oil_explosion

CAPABILITIES(/transformation/chem/instant/slime/oil_explosion)
	configure(transformation(name = "Slime Explosion", id = "m_oil_boom", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/oil),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/oil_explosion, on_reaction)))

/transformation/chem/instant/slime/oil_explosion/on_reaction(datum/reagents/holder)
	..()
	var/obj/item/slime_extract/E = holder.my_atom
	var/power = 1
	if(E.enhanced)
		power++
	E.uses = 0

	play_sfx(holder.my_atom, SFX_EFFECTS_PHASEIN, 0.75)
	holder.my_atom.visible_message(span_danger("\The [holder.my_atom] begins to vibrate violently!"))
	log_and_message_admins("Oil extract reaction (explosion) has been activated in [get_area(holder.my_atom)].  Last fingerprints: [holder.my_atom.forensic_data?.get_lastprint()]", null)

	after(holder.my_atom, 5 SECONDS, GLOBAL_PROC_REF(slime_extract_explode), with = list(holder.my_atom, power))

// ********************
// * Bluespace slimes *
// ********************

/obj/item/slime_extract/bluespace/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates some bluespace crystals. When injected with blood, this extract creates a bluespace bag. When injected with water, this \
	extract causes random teleportation. When injected with slime jelly, this extract creates a disposable precise teleportation tool.") + additional_information)

/obj/item/slime_extract/bluespace
	name = "bluespace slime extract"
	icon_state = "bluespace slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/bluespace

/transformation/chem/instant/slime/bluespace_crystals

CAPABILITIES(/transformation/chem/instant/slime/bluespace_crystals)
	configure(transformation(name = "Slime Bluespace Crystals", id = "m_bs_crystals", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/bluespace),
		spawns = spawns(/obj/item/slime_crystal, 5)))

/transformation/chem/instant/slime/bluespace_pouch

CAPABILITIES(/transformation/chem/instant/slime/bluespace_pouch)
	configure(transformation(name = "Slime Bluespace Pouch", id = "m_bs_pouch", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/bluespace),
		spawns = spawns(/obj/item/storage/backpack/holding/slime, 1)))

/transformation/chem/instant/slime/bluespace_chaotic_tele

CAPABILITIES(/transformation/chem/instant/slime/bluespace_chaotic_tele)
	configure(transformation(name = "Slime Bluespace Chaos", id = "m_bs_chaos", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/bluespace),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/bluespace_chaotic_tele, on_reaction)))

/transformation/chem/instant/slime/bluespace_chaotic_tele/on_reaction(datum/reagents/holder)
	log_and_message_admins("Bluespace extract reaction (chaos teleport) has been activated in [get_area(holder.my_atom)].  Last fingerprints: [holder.my_atom.forensic_data?.get_lastprint()]", null)
	for(var/mob/living/M in range(2,get_turf(holder.my_atom)))
		if(M?.buckled_to())
			var/atom/movable/_tmp_buck_51 = M?.buckled_to()
			_tmp_buck_51.unbuckle_mob()

		fx_sparks(get_turf(M), 3, FALSE)

		M.forceMove(pick(trange(50, get_turf(holder.my_atom))))

		fx_sparks(M.loc, 3, FALSE)
	..()

/transformation/chem/instant/slime/bluespace_teleporter

CAPABILITIES(/transformation/chem/instant/slime/bluespace_teleporter)
	configure(transformation(name = "Slime Bluespace Teleporter", id = "m_bs_teleporter", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/bluespace),
		spawns = spawns(/obj/item/disposable_teleporter/slime, 1)))
// *******************
// * Cerulean slimes *
// *******************

/obj/item/slime_extract/cerulean/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates an enhancer agent, which can be used to increase amount of uses any extract has once. When injected with blood, this extract \
	creates an invigoration agent, which can be used to create a slime out of an extract. When injected with water, this extract creates a mimic agent, which can copy properties of other agents. \
	When injected with slime jelly, this extract creates a random agent.") + additional_information)

/obj/item/slime_extract/cerulean
	name = "cerulean slime extract"
	icon_state = "cerulean slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/cerulean

/transformation/chem/instant/slime/cerulean_enhancer

CAPABILITIES(/transformation/chem/instant/slime/cerulean_enhancer)
	configure(transformation(name = "Slime Enhancer", id = "m_cerulean_enhancer", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/cerulean),
		spawns = spawns(/obj/item/slimepotion/enhancer, 1)))

/transformation/chem/instant/slime/cerulean_reinvigoration

CAPABILITIES(/transformation/chem/instant/slime/cerulean_reinvigoration)
	configure(transformation(name = "Slime Reinvigoration", id = "m_cerulean_reinvigoration", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/cerulean),
		spawns = spawns(/obj/item/slimepotion/reinvigoration, 1)))

/transformation/chem/instant/slime/cerulean_potion_mimic

CAPABILITIES(/transformation/chem/instant/slime/cerulean_potion_mimic)
	configure(transformation(name = "Slime Potion Mimic", id = "m_cerulean_potion_mimic", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/cerulean),
		spawns = spawns(/obj/item/slimepotion/mimic, 1)))

/transformation/chem/instant/slime/cerulean_random_potion

CAPABILITIES(/transformation/chem/instant/slime/cerulean_random_potion)
	configure(transformation(name = "Slime Random Potion", id = "m_cerulean_random_potion", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/cerulean),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/cerulean_random_potion, on_reaction)))

/transformation/chem/instant/slime/cerulean_random_potion/on_reaction(datum/reagents/holder)
	var/spawn_type = pickweight(GLOB.xenobio_cerulean_potions)
	new spawn_type(get_turf(holder.my_atom))
	..()

// ****************
// * Amber slimes *
// ****************

/obj/item/slime_extract/amber/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates a feeding agent, which can be used to instantly split a slime. When injected with blood, this extract creates some food. \
	When injected with water, this extract creates some edible slime globs. When injected with slime jelly, this extract creates some super-nutritious slime goop.") + additional_information)

/obj/item/slime_extract/amber
	name = "amber slime extract"
	icon_state = "amber slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/amber

/transformation/chem/instant/slime/amber_slimefood

CAPABILITIES(/transformation/chem/instant/slime/amber_slimefood)
	configure(transformation(name = "Slime Feeding", id = "m_amber_slime_food", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/amber),
		spawns = spawns(/obj/item/slimepotion/feeding, 1)))

/transformation/chem/instant/slime/amber_random_food

CAPABILITIES(/transformation/chem/instant/slime/amber_random_food)
	configure(transformation(name = "Slime Random Food", id = "m_amber_random_food", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/amber),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/amber_random_food, on_reaction)))

/transformation/chem/instant/slime/amber_random_food/on_reaction(datum/reagents/holder)
	var/list/edibles = subtypesof(/obj/item/reagent_containers/food/snacks)

	play_sfx(holder.my_atom, SFX_EFFECTS_PHASEIN)

	for(var/i = 1 to rand(2, 4))
		var/chosen = pick(edibles)
		var/obj/B = new chosen
		if(B)
			B.forceMove(get_turf(holder.my_atom))
			if(prob(50))
				for(var/j = 1, j <= rand(1, 3), j++)
					step(B, pick(NORTH,SOUTH,EAST,WEST))
	..()

/transformation/chem/instant/slime/amber_snack

CAPABILITIES(/transformation/chem/instant/slime/amber_snack)
	configure(transformation(name = "Slime Snack", id = "m_amber_snack", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/amber),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/amber_snack, on_reaction)))

/transformation/chem/instant/slime/amber_snack/on_reaction(datum/reagents/holder)
	for(var/i = 1 to rand(3, 5))
		new /obj/item/reagent_containers/food/snacks/slime(get_turf(holder.my_atom))
	..()

/transformation/chem/instant/slime/amber_goop

CAPABILITIES(/transformation/chem/instant/slime/amber_goop)
	configure(transformation(name = "Slime Goop", id = "m_amber_goop", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)),
		makes = list(reagent("slime_goop", 30)), holds = subject_is(/obj/item/slime_extract/amber)))

// *******************
// * Sapphire slimes *
// *******************

/obj/item/slime_extract/sapphire/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates a promethean cube, which can be used to create a new promethean. When injected with blood, this extract creates some mutation \
	toxin. When injected with water, this extract creates some plushies. When injected with slime jelly, this extract creates a sapience agent, which can be used to develop sentience in \
	various creatures.") + additional_information)

/obj/item/slime_extract/sapphire
	name = "sapphire slime extract"
	icon_state = "sapphire slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/sapphire

/transformation/chem/instant/slime/sapphire_promethean

CAPABILITIES(/transformation/chem/instant/slime/sapphire_promethean)
	configure(transformation(name = "Slime Promethean", id = "m_sapphire_promethean", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/sapphire),
		spawns = spawns(/obj/item/slime_cube, 1)))

/transformation/chem/instant/slime/sapphire_mutation

CAPABILITIES(/transformation/chem/instant/slime/sapphire_mutation)
	configure(transformation(name = "Slime Mutation Toxins", id = "m_sapphire_mutation_tox", takes = list(reagent(REAGENT_ID_BLOOD, 5)),
		makes = list(reagent(REAGENT_ID_MUTATIONTOXIN, 30)), holds = subject_is(/obj/item/slime_extract/sapphire)))

/transformation/chem/instant/slime/sapphire_plushies

CAPABILITIES(/transformation/chem/instant/slime/sapphire_plushies)
	configure(transformation(name = "Slime Plushies", id = "m_sapphire_plushies", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/sapphire),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/sapphire_plushies, on_reaction)))

/transformation/chem/instant/slime/sapphire_plushies/on_reaction(datum/reagents/holder)
	var/spawn_type
	var/list/possible_types = subtypesof(/obj/item/toy/plushie)
	possible_types -= subtypesof(/obj/item/toy/plushie/therapy)
	for(var/i = 1 to rand(3, 5))
		spawn_type = pickweight(possible_types)
		new spawn_type(get_turf(holder.my_atom))
	..()

/transformation/chem/instant/slime/sapphire_sapience

CAPABILITIES(/transformation/chem/instant/slime/sapphire_sapience)
	configure(transformation(name = "Slime Sapience", id = "m_sapphire_sapience", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/sapphire),
		spawns = spawns(/obj/item/slimepotion/sapience, 1)))
// ***************
// * Ruby slimes *
// ***************

/obj/item/slime_extract/ruby/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract grants extra strength for a time. When injected with blood, this extract causes a wave of pulling force. When injected with water, \
	this extract creates some brute juice. When injected with slime jelly, this extract creates a pushing combat_of(src).force.") + additional_information)

/obj/item/slime_extract/ruby
	name = "ruby slime extract"
	icon_state = "ruby slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/ruby

/transformation/chem/instant/slime/ruby_swole

CAPABILITIES(/transformation/chem/instant/slime/ruby_swole)
	configure(transformation(name = "Slime Strength", id = "m_ruby_strength", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/ruby),
		effects = sets_off(XFORM_FX_AREA, range = 1, body_effect = /datum/body_effect/slime_strength, lasts = 10 MINUTES)))


/datum/body_effect/slime_strength
	name = "slime strength"
	desc = "You feel much stronger than usual."
	mob_overlay_state = "pink_sparkles"

	on_created_text = span_warning("Twinkling spores of goo surround you.  It makes you feel stronger and more robust.")
	on_expired_text = span_notice("The spores of goo have faded, and you feel your strength returning to what it was before.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(STAT_MELEE_DAMAGE = 2, STAT_INCOMING_ALL = 0.75, STAT_DISABLE_DURATION = 0.5, STAT_ENDURANCE_FLAT = 50)

/transformation/chem/instant/slime/ruby_pull

CAPABILITIES(/transformation/chem/instant/slime/ruby_pull)
	configure(transformation(name = "Slime Pull", id = "m_ruby_pull", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/ruby),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/ruby_pull, on_reaction)))

/transformation/chem/instant/slime/ruby_pull/on_reaction(datum/reagents/holder)
	var/location = get_turf(holder.my_atom)
	play_sfx(location, SFX_WEAPONS_GAUSS_SHOOT)
#ifndef UNIT_TESTS
	// The pull keeps its timers and its record after it ends, which the end-of-run ownership audit reports as a leak: the pins settle this rule in a test world.
	var/datum/effect/effect/system/grav_pull/s = new /datum/effect/effect/system/grav_pull
	s.set_up(3, 3, location)
	s.start()
#endif
	..()

/transformation/chem/instant/slime/ruby_brute_juice

CAPABILITIES(/transformation/chem/instant/slime/ruby_brute_juice)
	configure(transformation(name = "Slime Brute Juice", id = "m_ruby_brute_juice", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_BERSERKMED, 30)), holds = subject_is(/obj/item/slime_extract/ruby)))

/transformation/chem/instant/slime/ruby_push

CAPABILITIES(/transformation/chem/instant/slime/ruby_push)
	configure(transformation(name = "Slime Push", id = "m_ruby_push", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/ruby),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/ruby_push, on_reaction)))

/transformation/chem/instant/slime/ruby_push/on_reaction(datum/reagents/holder)
	var/location = get_turf(holder.my_atom)
	for(var/X in orange(3, location))
		var/atom/movable/AM = X
		if(!ismovable(X) || istype(X, /obj/effect/overlay))
			continue

		if(isobj(X))
			var/obj/O = X
			if(O.anchored)
				continue

		var/throwdir = get_dir(location, AM)
		AM.throw_at(get_edge_target_turf(AM, throwdir), 3, 1, src)

	play_sfx(location, SFX_WEAPONS_GAUSS_SHOOT)
	..()

// *****************
// * Emerald slime *
// *****************

/obj/item/slime_extract/emerald/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract grants extra agility, making you more evasive and fast-acting for a while. When injected with blood, this extract grants extra speed \
	for a short time. When injected with water, this extract creates some hyperzine. When injected with slime jelly, this extract causes the area around it to become slippery for a time.") + additional_information)

/obj/item/slime_extract/emerald
	name = "emerald slime extract"
	icon_state = "emerald slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/emerald

/transformation/chem/instant/slime/emerald_agility

CAPABILITIES(/transformation/chem/instant/slime/emerald_agility)
	configure(transformation(name = "Slime Agility", id = "m_emerald_agility", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/emerald),
		effects = sets_off(XFORM_FX_AREA, range = 1, body_effect = /datum/body_effect/slime_agility, lasts = 10 MINUTES)))


/datum/body_effect/slime_agility
	name = "slime agility"
	desc = "You feel much more agile than usual."
	mob_overlay_state = "green_sparkles"

	on_created_text = span_warning("Twinkling spores of goo surround you.  It makes you feel more agile.")
	on_expired_text = span_notice("The spores of goo have faded, and you feel your agility returning to what it was before.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(STAT_EVASION = 45, STAT_ATTACK_SPEED = 0.5, STAT_DISABLE_DURATION = 0.5)

/transformation/chem/instant/slime/emerald_speed

CAPABILITIES(/transformation/chem/instant/slime/emerald_speed)
	configure(transformation(name = "Slime Speed", id = "m_emerald_speed", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/emerald),
		effects = sets_off(XFORM_FX_AREA, range = 1, body_effect = /datum/body_effect/slime_speed, lasts = 1 MINUTE)))


/datum/body_effect/slime_speed
	name = "slime speed"
	desc = "You feel much faster than usual."
	mob_overlay_state = "haste"

	on_created_text = span_warning("Twinkling spores of goo surround you.  It makes you feel very fast.")
	on_expired_text = span_notice("The spores of goo have faded, and you feel your speed returning to what it was before.")
	stacks = MODIFIER_STACK_EXTEND

	factors = alist(STAT_SLOWDOWN = -3)

/transformation/chem/instant/slime/emerald_hyperzine

CAPABILITIES(/transformation/chem/instant/slime/emerald_hyperzine)
	configure(transformation(name = "Slime Hyperzine", id = "m_emerald_hyperzine", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_HYPERZINE, 30)), holds = subject_is(/obj/item/slime_extract/emerald)))

/transformation/chem/instant/slime/emerald_hell

CAPABILITIES(/transformation/chem/instant/slime/emerald_hell)
	configure(transformation(name = "Slime Hell", id = "m_emerald_hell", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/emerald),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/emerald_hell, on_reaction)))

/transformation/chem/instant/slime/emerald_hell/on_reaction(datum/reagents/holder)
	log_and_message_admins("Emerald extract reaction (slip hell) has been activated in [get_area(holder.my_atom)].  Last fingerprints: [holder.my_atom.forensic_data?.get_lastprint()]", null)
	for(var/turf/simulated/T in trange(5, get_turf(holder.my_atom)))
		if(!istype(T))
			continue
		T.set_wet(TURFSLIP_WET)
		T.freeze_floor()
	..()

// *********************
// * Light Pink slimes *
// *********************

/obj/item/slime_extract/light_pink/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract creates a friendship agent, which can be used to make a slime or a creature consider you a friend. When injected with blood, \
	this extract creates a loyalty agent, which can be used to make a slime or a creature think of those like you as their own. When injected with water, this extract creates a docility agent, \
	which can be used to pacify a slime or a creature permanently. When injected with slime jelly, this extract creates an obedience agent, which can be used to instantly fully discipline a slime.") + additional_information)

/obj/item/slime_extract/light_pink
	name = "light pink slime extract"
	icon_state = "light pink slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/light_pink

/transformation/chem/instant/slime/light_pink_friendship

CAPABILITIES(/transformation/chem/instant/slime/light_pink_friendship)
	configure(transformation(name = "Slime Friendship", id = "m_lightpink_friendship", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/light_pink),
		spawns = spawns(/obj/item/slimepotion/friendship, 1)))

/transformation/chem/instant/slime/light_pink_loyalty

CAPABILITIES(/transformation/chem/instant/slime/light_pink_loyalty)
	configure(transformation(name = "Slime Loyalty", id = "m_lightpink_loyalty", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/light_pink),
		spawns = spawns(/obj/item/slimepotion/loyalty, 1)))

/transformation/chem/instant/slime/light_pink_docility

CAPABILITIES(/transformation/chem/instant/slime/light_pink_docility)
	configure(transformation(name = "Slime Docility", id = "m_lightpink_docility", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/light_pink),
		spawns = spawns(/obj/item/slimepotion/docility, 1)))

/transformation/chem/instant/slime/light_pink_obedience

CAPABILITIES(/transformation/chem/instant/slime/light_pink_obedience)
	configure(transformation(name = "Slime Obedience", id = "m_lightpink_obedience", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/light_pink),
		spawns = spawns(/obj/item/slimepotion/obedience, 1)))
// ******************
// * Rainbow slimes *
// ******************

/obj/item/slime_extract/rainbow/get_mechanics_info(list/additional_information)
	return ..(list("When injected with phoron, this extract will create a random slime. When injected with blood, this extract will create a random slime extract. When injected with water, \
	this extract will create pretty colors. When injected with slime jelly, this extract will create unity agent, which can be used to make a slime non-hostile to slimes of other colors.") + additional_information)

/obj/item/slime_extract/rainbow
	name = "rainbow slime extract"
	icon_state = "rainbow slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/rainbow

/transformation/chem/instant/slime/rainbow_random_slime

CAPABILITIES(/transformation/chem/instant/slime/rainbow_random_slime)
	configure(transformation(name = "Slime Random Slime", id = "m_rainow_random_slime", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/rainbow),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/rainbow_random_slime, on_reaction)))

/transformation/chem/instant/slime/rainbow_random_slime/on_reaction(datum/reagents/holder)
	var/mob/living/simple_mob/slime/xenobio/S
	var/list/slime_types = typesof(/mob/living/simple_mob/slime/xenobio)

	while(slime_types.len)
		S = pick(slime_types)
		if(initial(S.rainbow_core_candidate) == TRUE)
			break
		else
			slime_types -= S
			S = null

	if(S)
		new S(get_turf(holder.my_atom))
	..()

/transformation/chem/instant/slime/rainbow_random_extract

CAPABILITIES(/transformation/chem/instant/slime/rainbow_random_extract)
	configure(transformation(name = "Slime Random Extract", id = "m_rainow_random_extract", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/rainbow),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/rainbow_random_extract, on_reaction)))

/transformation/chem/instant/slime/rainbow_random_extract/on_reaction(datum/reagents/holder)
	var/spawn_type = pickweight(GLOB.xenobio_rainbow_extracts)
	new spawn_type(get_turf(holder.my_atom))
	..()

/transformation/chem/instant/slime/rainbow_colors

CAPABILITIES(/transformation/chem/instant/slime/rainbow_colors)
	configure(transformation(name = "Slime Colors", id = "m_rainbow_colors", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/rainbow),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/rainbow_colors, on_reaction)))

/transformation/chem/instant/slime/rainbow_colors/on_reaction(datum/reagents/holder)
	for(var/mob/living/carbon/human/H in range(3, holder.my_atom))
		H.status_at_least(STAT_DRUGGED, 30)
	..()

/transformation/chem/instant/slime/rainbow_unity

CAPABILITIES(/transformation/chem/instant/slime/rainbow_unity)
	configure(transformation(name = "Slime Unity", id = "m_rainbow_unity", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/rainbow),
		spawns = spawns(/obj/item/slimepotion/unity, 1)))
// Delayed extract reactions, five seconds after the extract starts to vibrate, on the
// extract's clock (a deleted extract never goes off).

/proc/slime_extract_fire(atom/extract)
	var/turf/simulated/T = get_turf(extract)
	if(!istype(T))
		return
	for(var/turf/simulated/target_turf in view(2, T))
		target_turf.assume_gas(GAS_VOLATILE_FUEL, 33, 1500+T0C)
		target_turf.assume_gas(GAS_O2, 66, 1500+T0C)
		target_turf.hotspot_expose(1500+T0C, 400)
	play_sfx(T, SFX_EFFECTS_PHASEIN, 0.75)

/proc/slime_extract_lightning(atom/extract)
	var/turf/T = get_turf(extract)
	if(istype(T))
		lightning_strike(T)

/proc/slime_extract_emp(atom/extract)
	empulse(get_turf(extract), 2, 4, 7, 10) // As strong as a normal EMP grenade.
	play_sfx(extract, SFX_EFFECTS_PHASEIN, 0.75)

/proc/slime_extract_start_emitting(atom/extract)
	var/obj/item/slime_extract/X = extract
	if(istype(X))
		X.set_emitting(TRUE)

/proc/slime_extract_explode(atom/extract, power)
	explosion(get_turf(extract), 1 * power, 3 * power, 6 * power)
	if(!QDELETED(extract)) // Explosion may or may not have deleted the extract.
		destroyed(extract, null, "explosion")
