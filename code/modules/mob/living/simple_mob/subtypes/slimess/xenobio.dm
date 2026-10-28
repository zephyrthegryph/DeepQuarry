/mob/living/simple_mob/slime/xenobio/yellow
	projectiletype = /obj/item/projectile/energy/mob/electric_spider

/mob/living/simple_mob/slime/xenobio/sepia
	desc = "This slime is rather unknown and strange."
	color = "#968473"
	slime_color = "sepia"
	coretype = /obj/item/slime_extract/sepia
	reagent_injected = REAGENT_ID_STOXIN

	mutation_chance = 100

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/sepia,
			/mob/living/simple_mob/slime/xenobio/oil,
			/mob/living/simple_mob/slime/xenobio/green,
			/mob/living/simple_mob/slime/xenobio/ruby
		)

/obj/item/slime_extract/sepia
	name = "sepia slime extract"
	icon_state = "sepia slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/sepia

/transformation/chem/instant/slime/senseenhancer

CAPABILITIES(/transformation/chem/instant/slime/senseenhancer)
	configure(transformation(name = "Slime Sense Enhancer", id = "sepia_sh", takes = list(reagent(REAGENT_ID_PHORON, 5)),
		makes = list(reagent(REAGENT_ID_SENSEENHANCER, 30)), holds = subject_is(/obj/item/slime_extract/sepia)))

/transformation/chem/instant/slime/secertslime

CAPABILITIES(/transformation/chem/instant/slime/secertslime)
	configure(transformation(name = "Secert Slime ", id = "sepia_swapm", takes = list(reagent(REAGENT_ID_BLOOD, 5), reagent(REAGENT_ID_WATER, 5)),
		made = 1, holds = subject_is(/obj/item/slime_extract/sepia),
		spawns = spawns(/mob/living/simple_mob/slime/xenobio/redspace, 1, tell = span_warning("Infused with the mixture, the core begins to quiver and grow, and soon a new baby slime emerges from it!"))))

/transformation/chem/instant/slime/sepia_new_slime

CAPABILITIES(/transformation/chem/instant/slime/sepia_new_slime)
	configure(transformation(name = "Slime Spawn", id = "m_sepia_spawn", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/sepia),
		spawns = spawns(/mob/living/simple_mob/slime/xenobio/sepia, 1, tell = span_warning("Infused with slime jelly, the core begins to quiver and grow, and soon a new baby slime emerges from it!"))))
/mob/living/simple_mob/slime/xenobio/redspace
	desc = "This slime is rather unknown and strange."
	color = "#A50021"
	slime_color = "redspace"
	coretype = /obj/item/slime_extract/redspace
	reagent_injected = REAGENT_ID_MINDBREAKER

	mutation_chance = 0

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/dark,
			/mob/living/simple_mob/slime/xenobio/redspace,
			/mob/living/simple_mob/slime/xenobio/dream,
			/mob/living/simple_mob/slime/xenobio/plague
		)

/obj/item/slime_extract/redspace
	name = "redspace slime extract"
	icon_state = "ruby slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/redspace


/transformation/chem/instant/slime/redspace_fire

CAPABILITIES(/transformation/chem/instant/slime/redspace_fire)
	configure(transformation(name = "Slime Living Fire", id = "m_liquid_fire", takes = list(reagent(REAGENT_ID_PHORON, 5)),
		makes = list(reagent(REAGENT_ID_NEOLIQUIDFIRE, 30)), holds = subject_is(/obj/item/slime_extract/redspace)))

/transformation/chem/instant/slime/soulstone

CAPABILITIES(/transformation/chem/instant/slime/soulstone)
	configure(transformation(name = "Slime Soulstone", id = "m_redspace_soulstone", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/redspace),
		spawns = spawns(/obj/item/soulstone, 1)))

/transformation/chem/instant/slime/redspace_smoke

CAPABILITIES(/transformation/chem/instant/slime/redspace_smoke)
	configure(transformation(name = "Slime Smoke", id = "m_redspace_smoke", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/redspace),
		effects = sets_off(XFORM_FX_SMOKE, amount = 120, sfx = SFX_EFFECTS_SMOKE)))


/transformation/chem/instant/slime/slime_mindbreaker

CAPABILITIES(/transformation/chem/instant/slime/slime_mindbreaker)
	configure(transformation(name = "Slime Pyrotoxin", id = "m_redspace_mindbreaker", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)),
		makes = list(reagent(REAGENT_ID_MINDBREAKER, 30)), holds = subject_is(/obj/item/slime_extract/redspace)))


/mob/living/simple_mob/slime/xenobio/dark
	desc = "This slime is rather unknown and strange."
	color = "#080808"
	slime_color = "dark"
	coretype = /obj/item/slime_extract/dark
	reagent_injected = "potassium_chlorophoride"

	mutation_chance = 0

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/dark,
			/mob/living/simple_mob/slime/xenobio/redspace,
			/mob/living/simple_mob/slime/xenobio/dream,
			/mob/living/simple_mob/slime/xenobio/plague
		)

/obj/item/slime_extract/dark
	name = "dark slime extract"
	icon_state = "oil slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/dark

/transformation/chem/instant/slime/dark_neofire

CAPABILITIES(/transformation/chem/instant/slime/dark_neofire)
	configure(transformation(name = "Slime Healing Liquid", id = "m_liquid_healing", takes = list(reagent(REAGENT_ID_NEOLIQUIDFIRE, 5)),
		makes = list(reagent(REAGENT_ID_HEALINGNANITES, 30)), holds = subject_is(/obj/item/slime_extract/dark)))

/transformation/chem/instant/slime/dark_liquidfire

CAPABILITIES(/transformation/chem/instant/slime/dark_liquidfire)
	configure(transformation(name = "Slime Secert Guard", id = "m_slime_guardian", takes = list(reagent(REAGENT_ID_LIQUIDFIRE, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/dark),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/dark_liquidfire, on_reaction)))


/transformation/chem/instant/slime/dark_liquidfire/on_reaction(datum/reagents/holder)
	for(var/mob/living/L in range(1, holder.my_atom))
		L.apply_body_effect(/datum/body_effect/feysight, 10 MINUTES, src)
	..()

/transformation/chem/instant/slime/dark_deathblood

CAPABILITIES(/transformation/chem/instant/slime/dark_deathblood)
	configure(transformation(name = "Slime Secert Painite", id = "m_slime_painite", takes = list(reagent(REAGENT_ID_DEATHBLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/dark),
		spawns = spawns(/obj/item/stack/material/painite, 1)))

/transformation/chem/instant/slime/dark_liquidlife

CAPABILITIES(/transformation/chem/instant/slime/dark_liquidlife)
	configure(transformation(name = "Slime Secert Overcharge", id = "m_slime_darkspeed", takes = list(reagent(REAGENT_ID_LIQUIDLIFE, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/dark),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/dark_liquidlife, on_reaction)))

/transformation/chem/instant/slime/dark_liquidlife/on_reaction(datum/reagents/holder)
	for(var/mob/living/L in range(49, holder.my_atom))
		L.apply_body_effect(/datum/body_effect/sprinting, 5 MINUTES, src)
	..()


/transformation/chem/instant/slime/dark_carpotoxin

CAPABILITIES(/transformation/chem/instant/slime/dark_carpotoxin)
	configure(transformation(name = "Slime Dark Secert ", id = "m_fish_slime", takes = list(reagent(REAGENT_ID_CARPOTOXIN, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/dark),
		spawns = spawns(/mob/living/simple_mob/slime/xenobio/oceanic, 1, tell = span_warning("Infused with slime jelly, the core begins to quiver and grow, and soon a new baby slime emerges from it!"))))

/transformation/chem/instant/slime/dark_spidertoxin

CAPABILITIES(/transformation/chem/instant/slime/dark_spidertoxin)
	configure(transformation(name = "Slime Secert Dark Spooder", id = "m_slime_darkspooder", takes = list(reagent(REAGENT_ID_SPIDERTOXIN, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/dark),
		spawns = spawns(/obj/effect/spider/eggcluster/royal/space, 1)))

/transformation/chem/instant/slime/dark_blood

CAPABILITIES(/transformation/chem/instant/slime/dark_blood)
	configure(transformation(name = "Slime Secert Void Opal", id = "m_slime_voidopal", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/dark),
		spawns = spawns(/obj/item/stack/material/void_opal, 1)))
/mob/living/simple_mob/slime/xenobio/plague
	desc = "This slime is rather unknown and strange."
	color = "#336600"
	slime_color = "plague"
	coretype = /obj/item/slime_extract/plague

	mutation_chance = 0

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/dark,
			/mob/living/simple_mob/slime/xenobio/redspace,
			/mob/living/simple_mob/slime/xenobio/dream,
			/mob/living/simple_mob/slime/xenobio/plague
		)

/obj/item/slime_extract/plague
	name = "plague slime extract"
	icon_state = "emerald slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/plague

/transformation/chem/instant/slime/plague_toxin

CAPABILITIES(/transformation/chem/instant/slime/plague_toxin)
	configure(transformation(name = "Slime Living Fire", id = "m_plague_toxin", takes = list(reagent(REAGENT_ID_PHORON, 5)),
		makes = list(reagent(REAGENT_ID_NEUROPHAGENANITES, 30)), holds = subject_is(/obj/item/slime_extract/plague)))


/transformation/chem/instant/slime/virusdish

CAPABILITIES(/transformation/chem/instant/slime/virusdish)
	configure(transformation(name = "Virus dish", id = "m_plague_dish", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/plague),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/virusdish, on_reaction)))

/transformation/chem/instant/slime/virusdish/on_reaction(datum/reagents/holder)
	// new /obj/item/virusdish(get_turf(holder.my_atom))
	..()

/transformation/chem/instant/slime/obj/item/slime_extract/plague_jelly

CAPABILITIES(/transformation/chem/instant/slime/obj/item/slime_extract/plague_jelly)
	configure(transformation(name = "Slime Smoke", id = "m_slimejelly_alt", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_SLIMEJELLY, 30)), holds = subject_is(/obj/item/slime_extract/plague)))


/mob/living/simple_mob/slime/xenobio/oceanic
	desc = "This slime is rather unknown and strange."
	color = "#006666"
	slime_color = "oceanic"
	coretype = /obj/item/slime_extract/oceanic
	rainbow_core_candidate = FALSE //For health and safety
	mutation_chance = 0

	reagent_injected = REAGENT_ID_CARPOTOXIN

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/sepia,
			/mob/living/simple_mob/slime/xenobio/sepia,
			/mob/living/simple_mob/slime/xenobio/sepia,
			/mob/living/simple_mob/slime/xenobio/oceanic
		)
	water_resist = 10 //I heard putting this higher makes them heal.


/mob/living/simple_mob/slime/xenobio/oceanic/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.ocean_aura()
	..()

/mob/living/simple_mob/slime/xenobio/oceanic/proc/ocean_aura()
	for(var/mob/living/L in view(src, 4))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/aura/slime_healingtide, null, src)

/datum/body_effect/aura/slime_healingtide
	name = "Aura Healing Tide"
	desc = "You are filled with an overwhelming energy."

	on_created_text = span_critical("Your body begins to focus on recovering!")
	on_expired_text = span_notice("The healing subsides.")
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 4

	// The negative hurts less in this form
	factors = alist(STAT_METABOLISM_MULT = 0.5, STAT_HEALING_RECEIVED = 1.15)

/obj/item/slime_extract/oceanic
	name = "oceanic slime extract"
	icon_state = "blue slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/oceanic

/transformation/chem/instant/slime/carpfren

CAPABILITIES(/transformation/chem/instant/slime/carpfren)
	configure(transformation(name = "Carp Friend", id = "m_carp_friends", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/oceanic),
		spawns = spawns(/mob/living/simple_mob/animal/space/carp/station, 1)))

/transformation/chem/instant/slime/oceancarp

CAPABILITIES(/transformation/chem/instant/slime/oceancarp)
	configure(transformation(name = "Slime Carptoxi", id = "m_slime_carptox", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)),
		makes = list(reagent(REAGENT_ID_CARPOTOXIN, 30)), holds = subject_is(/obj/item/slime_extract/oceanic)))

/transformation/chem/instant/slime/waterdupe

CAPABILITIES(/transformation/chem/instant/slime/waterdupe)
	configure(transformation(name = "Water Duplication", id = "m_slime_water", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_WATER, 30)), holds = subject_is(/obj/item/slime_extract/oceanic)))

/transformation/chem/instant/slime/oceanboon

CAPABILITIES(/transformation/chem/instant/slime/oceanboon)
	configure(transformation(name = "Carp Boon", id = "m_carp_boon", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/oceanic),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/oceanboon, on_reaction)))

/transformation/chem/instant/slime/oceanboon/on_reaction(datum/reagents/holder)
	for(var/mob/living/L in range(21, holder.my_atom))
		L.apply_body_effect(/datum/body_effect/healingtide, 10 MINUTES, src)
	..()

/transformation/chem/instant/slime/warplague

CAPABILITIES(/transformation/chem/instant/slime/warplague)
	configure(transformation(name = "Nuclear Slime Summon", id = "m_nuclear_slime", takes = list(reagent(REAGENT_ID_MINDBREAKER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/plague),
		spawns = spawns(/mob/living/simple_mob/slime/xenobio/nuclear, 1, tell = span_warning("Infused with slime jelly, the core begins to quiver and grow, and soon a new baby slime emerges from it!"))))
/mob/living/simple_mob/slime/xenobio/nuclear
	desc = "This slime is rather unknown and strange."
	color = "#006600"
	slime_color = "nuclear"
	coretype = /obj/item/slime_extract/nuclear

	rainbow_core_candidate = FALSE //For health and safety

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/sepia,
		/mob/living/simple_mob/slime/xenobio/sepia,
		/mob/living/simple_mob/slime/xenobio/sepia,
		/mob/living/simple_mob/slime/xenobio/nuclear
		)

/mob/living/simple_mob/slime/xenobio/nuclear/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.nuclear_aura()
	..()

/mob/living/simple_mob/slime/xenobio/nuclear/proc/nuclear_aura()
	for(var/mob/living/L in view(src, 4))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/aura/radiationhide, null, src)

/datum/body_effect/aura/radiationhide
	name = "Radiation Hide"
	desc = "Your body defensivly warps."

	on_created_text = span_critical("Your body strangly mutates!")
	on_expired_text = span_notice("Your body returns to normal.")
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 4

	factors = alist(STAT_INCOMING_ALL = 0.8, STAT_INCOMING_GENETIC = 0, STAT_HEALING_RECEIVED = 0.5, STAT_SCALE_MULT_X = 1.2, STAT_SCALE_MULT_Y = 1.2)

/obj/item/slime_extract/nuclear
	name = "nuclear slime extract"
	icon_state = "green slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/nuclear

/transformation/chem/instant/slime/nuclear_radpulse

CAPABILITIES(/transformation/chem/instant/slime/nuclear_radpulse)
	configure(transformation(name = "Slime Radiation Pulse", id = "m_green_radpulse2", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/nuclear),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/nuclear_radpulse, on_reaction)))

/transformation/chem/instant/slime/nuclear_radpulse/on_reaction(datum/reagents/holder)
	log_and_message_admins("Green extract reaction (radiation pulse) has been activated in [get_area(holder.my_atom)].  Last fingerprints: [holder.my_atom.forensic_data?.get_lastprint()]", null)
	play_sfx(holder.my_atom, SFX_EFFECTS_PHASEIN, 0.75)
	holder.my_atom.visible_message(span_danger("\The [holder.my_atom] begins to vibrate violently!"))
	after(holder.my_atom, 5 SECONDS, GLOBAL_PROC_REF(slime_green_pulse), with = list(holder.my_atom))
	..()


/transformation/chem/instant/slime/nuclear_emitter

CAPABILITIES(/transformation/chem/instant/slime/nuclear_emitter)
	configure(transformation(name = "Slime Radiation Emitter", id = "m_green_emitter2", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/green),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/nuclear_emitter, on_reaction)))

/transformation/chem/instant/slime/nuclear_emitter/on_reaction(datum/reagents/holder)
	log_and_message_admins("Green extract reaction (radiation emitter) has been activated in [get_area(holder.my_atom)].  Last fingerprints: [holder.my_atom.forensic_data?.get_lastprint()]", null)
	new /obj/item/slime_irradiator(get_turf(holder.my_atom))
	..()


/transformation/chem/instant/slime/nuclear_radium

CAPABILITIES(/transformation/chem/instant/slime/nuclear_radium)
	configure(transformation(name = "Slime Radium", id = "m_green_radium2", takes = list(reagent(REAGENT_ID_WATER, 5)),
		makes = list(reagent(REAGENT_ID_RADIUM, 30)), holds = subject_is(/obj/item/slime_extract/green)))


/transformation/chem/instant/slime/nuclear_uranium

CAPABILITIES(/transformation/chem/instant/slime/nuclear_uranium)
	configure(transformation(name = "Slime Uranium", id = "m_green_uranium2", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/green),
		spawns = spawns(/obj/item/stack/material/uranium, 1, amount = 10)))
/mob/living/simple_mob/slime/xenobio/dream
	desc = "This slime is rather unknown and strange."
	color = "#FFFFFF"
	slime_color = "dream"
	coretype = /obj/item/slime_extract/dream

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/dark,
			/mob/living/simple_mob/slime/xenobio/redspace,
			/mob/living/simple_mob/slime/xenobio/dream,
			/mob/living/simple_mob/slime/xenobio/plague
		)

/obj/item/slime_extract/dream
	name = "dream slime extract"
	icon_state = "grey slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/dream

/transformation/chem/instant/slime/dreamscale

CAPABILITIES(/transformation/chem/instant/slime/dreamscale)
	configure(transformation(name = "dream scale creation ", id = "m_dreamscale_slime", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/dream),
		spawns = spawns(/obj/item/stack/material/dreamscale, 1, amount = 10)))

/transformation/chem/instant/slime/nightmareslime

CAPABILITIES(/transformation/chem/instant/slime/nightmareslime)
	configure(transformation(name = "Nightmare Slime Summon ", id = "m_nightmare_slime",
		takes = list(reagent(REAGENT_ID_BLOOD, 5), reagent(REAGENT_ID_PHORON, 5), reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/dream),
		spawns = spawns(/mob/living/simple_mob/slime/xenobio/nightmare, 1, tell = span_warning("Infused with slime jelly, the core begins to quiver and grow, and soon a new baby slime emerges from it!"))))
/mob/living/simple_mob/slime/xenobio/nightmare
	desc = "This slime is rather unknown and strange."
	color = "#993366"
	slime_color = "nightmare"
	coretype = /obj/item/slime_extract/nightmare

	rainbow_core_candidate = FALSE //For health and safety

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/nightmare,
			/mob/living/simple_mob/slime/xenobio/nightmare,
			/mob/living/simple_mob/slime/xenobio/nightmare,
			/mob/living/simple_mob/slime/xenobio/nightmare
		)


/mob/living/simple_mob/slime/xenobio/nightmare/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.nightmare_aura()
	..()

/mob/living/simple_mob/slime/xenobio/nightmare/proc/nightmare_aura()
	for(var/mob/living/carbon/L in view(src, 3))
		if(L.stat == DEAD)
			continue
		L.apply_body_effect(/datum/body_effect/aura/dreamarmor, null, src)

/datum/body_effect/aura/dreamarmor
	tick_interval = 2 SECONDS
	name = "dream armor"
	desc = "You are highly resistant to damage."
	stacks = MODIFIER_STACK_FORBID

	mob_overlay_state = "cult_aura"
	factors = alist(STAT_INCOMING_ALL = 0.5)

/datum/body_effect/aura/dreamarmor/on_tick(mob/living/L)
	if(L.stat == DEAD)
		L.end_body_effect(type)
		return

	if(ishuman(L)) // Every limb withers, organic or robotic.
		var/mob/living/carbon/human/H = L
		for(var/obj/item/organ/external/E as anything in H.organs)
			H.injure(INJURY_BLUNT, 2, E.organ_tag, flags = INJURE_SILENT)
			H.injure(INJURY_BURN, 2, E.organ_tag, flags = INJURE_SILENT)
	else
		L.injure(INJURY_BLUNT, 5, flags = INJURE_SILENT)
		L.injure(INJURY_BURN, 5, flags = INJURE_SILENT)

/obj/item/slime_extract/nightmare
	name = "nightmare slime extract"
	icon_state = "oil slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/nightmare

/transformation/chem/instant/slime/nightmarewater

CAPABILITIES(/transformation/chem/instant/slime/nightmarewater)
	configure(transformation(name = "nightmare water", id = "m_nightmare_water", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/nightmare),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/nightmarewater, on_reaction)))

/transformation/chem/instant/slime/nightmarewater/on_reaction(datum/reagents/holder)
	for(var/mob/living/L in range(3, holder.my_atom))
		L.apply_body_effect(/datum/body_effect/faraday, 1 MINUTES, src)
		L.apply_body_effect(/datum/body_effect/blastshield, 1 MINUTES, src)
	..()

/transformation/chem/instant/slime/nightmarejelly

CAPABILITIES(/transformation/chem/instant/slime/nightmarejelly)
	configure(transformation(name = "nightmare jelly", id = "m_nightmare_jelly", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/nightmare),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/nightmarejelly, on_reaction)))

/transformation/chem/instant/slime/nightmarejelly/on_reaction(datum/reagents/holder)
	for(var/mob/living/L in range(14, holder.my_atom))
		L.lingering_poison(2, 3 MINUTES)
	..()

/transformation/chem/instant/slime/nightmareblood

CAPABILITIES(/transformation/chem/instant/slime/nightmareblood)
	configure(transformation(name = "nightmare blood", id = "m_nightmare_blood", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/nightmare),
		spawns = spawns(/obj/item/stack/material/valhollide, 1, amount = 5)))

/transformation/chem/instant/slime/nightmarephoron

CAPABILITIES(/transformation/chem/instant/slime/nightmarephoron)
	configure(transformation(name = "nightmare phoron", id = "m_nightmare_phoron", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/nightmare),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/nightmarephoron, on_reaction)))

/transformation/chem/instant/slime/nightmarephoron/on_reaction(datum/reagents/holder)
	for(var/mob/living/L in range(14, holder.my_atom))
		L.apply_body_effect(/datum/body_effect/berserk_exhaustion, 1 MINUTES, src)
	..()




/transformation/chem/instant/slime/redspace_sound

CAPABILITIES(/transformation/chem/instant/slime/redspace_sound)
	configure(transformation(name = "Slime Sound Creation", id = "m_make_sound", takes = list(reagent(REAGENT_ID_MINDBREAKER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/redspace),
		spawns = spawns(/mob/living/simple_mob/slime/xenobio/sound, 1, tell = span_warning("Infused with the mixture, the core begins to quiver and grow, and soon a new baby slime emerges from it!"))))
/mob/living/simple_mob/slime/xenobio/sound
	desc = "This slime is rather unknown and strange."
	color = "#808080"
	slime_color = "sound"
	coretype = /obj/item/slime_extract/sound

	rainbow_core_candidate = FALSE //For health and safety

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/redspace,
			/mob/living/simple_mob/slime/xenobio/dream,
			/mob/living/simple_mob/slime/xenobio/plague,
			/mob/living/simple_mob/slime/xenobio/sound
		)

/mob/living/simple_mob/slime/xenobio/sound/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.sound_aura()
	..()

/mob/living/simple_mob/slime/xenobio/sound/proc/sound_aura()
	for(var/mob/living/L in view(src, 4))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/aura/soothingsong, null, src)

/datum/body_effect/aura/soothingsong
	name = "Soothing Song"
	desc = "Your body is soothed."

	on_created_text = span_critical("Your mind is put to rest!")
	on_expired_text = span_notice("Your mind functions normally.")
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 4

	factors = alist(STAT_INCOMING_PAIN = 0.8, STAT_DISABLE_DURATION = 0.7)

/obj/item/slime_extract/sound
	name = "sound slime extract"
	icon_state = "silver slime extract"
	slime_type = /mob/living/simple_mob/slime/xenobio/sound

/transformation/chem/instant/slime/soundblood

CAPABILITIES(/transformation/chem/instant/slime/soundblood)
	configure(transformation(name = "sound blood", id = "m_sound_blood", takes = list(reagent(REAGENT_ID_BLOOD, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/sound),
		spawns = spawns(/obj/item/stack/material/quartz, 1, amount = 5)))

/transformation/chem/instant/slime/soundphoron

CAPABILITIES(/transformation/chem/instant/slime/soundphoron)
	configure(transformation(name = "sound phoron", id = "m_sound_phoron", takes = list(reagent(REAGENT_ID_PHORON, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/sound),
		then = TYPE_PROC_REF(/transformation/chem/instant/slime/soundphoron, on_reaction)))

/transformation/chem/instant/slime/soundphoron/on_reaction(datum/reagents/holder)
	for(var/mob/living/L in range(1, holder.my_atom))
		L.apply_body_effect(/datum/body_effect/aura/soothingsong, 10 MINUTES, src)
	..()

/transformation/chem/instant/slime/soundwater

CAPABILITIES(/transformation/chem/instant/slime/soundwater)
	configure(transformation(name = "sound water", id = "m_sound_water", takes = list(reagent(REAGENT_ID_WATER, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/sound),
		spawns = spawns(/mob/living/simple_mob/slime/xenobio/sound, 1, tell = span_warning("Infused with the mixture, the core begins to quiver and grow, and soon a new baby slime emerges from it!"))))

/transformation/chem/instant/slime/soundjelly

CAPABILITIES(/transformation/chem/instant/slime/soundjelly)
	configure(transformation(name = "sound slimejelly", id = "m_sound_slimejelly", takes = list(reagent(REAGENT_ID_SLIMEJELLY, 5)), made = 1,
		holds = subject_is(/obj/item/slime_extract/sound),
		spawns = spawns(/obj/item/stack/material/glass/plastitanium, 1, amount = 5)))
/// The green extract's radiation pulse, five seconds after it starts to vibrate.
/proc/slime_green_pulse(atom/source)
	radiation_pulse(
		source,
		max_range = 7,
		threshold = RAD_MEDIUM_INSULATION,
		chance = 100,
		strength = 30
	)
