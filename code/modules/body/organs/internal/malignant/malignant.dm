// malignant organs! Develops randomly from radiation exposure and events!
/obj/item/organ/internal/malignant
	organ_tag = "malignant" // gets a random number after, to allow multiple organs!
	icon = 'icons/obj/surgery_op.dmi'
	var/validBPspawns = list(BP_GROIN, BP_TORSO, BP_HEAD, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_FOOT, BP_R_FOOT, BP_L_LEG, BP_R_LEG) // copy of BP_ALL
	var/surgeryAllowedSites = list(BP_GROIN, BP_TORSO, BP_HEAD, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_FOOT, BP_R_FOOT, BP_L_LEG, BP_R_LEG) // everything except engineered uses a BP_ALL copy

	var/cooldown = 0
	var/cooldownmin = 0
	var/cooldownmax = 0

CAPABILITIES(/obj/item/organ/internal/malignant)
	param(nameof(force_location), pos = 2)
	param(nameof(forcetag), pos = 3)

/// Where the growth is forced to grow and its forced tag (its constructor params).
/obj/item/organ/internal/malignant/var/force_location
/obj/item/organ/internal/malignant/var/forcetag

// ALLOW(init/INSTANCE_STATE): a growth is tagged and picks an organic limb to grow in (or the one it is forced to) before its parents' init
/obj/item/organ/internal/malignant/Initialize(mapload, internal)
	organ_tag = "[initial(organ_tag)]_[rand(1,9999)]"
	if(forcetag)
		organ_tag = forcetag
	if(!istype(src,/obj/item/organ/internal/malignant/engineered))
		// choose a random site for us to grow in before calling parent
		var/i = 0
		if(!force_location)
			while(++i < 10)
				// done here, because New() does all the setup for placing the organ...
				// attempt to select a valid exterior organ that isn't synthetic!
				if(isliving(loc))
					parent_organ = pick(validBPspawns)
					var/mob/living/L = loc
					var/obj/item/organ/checklimb = L.organs_by_name[parent_organ]
					if(checklimb)
						// valid limb, check if organic!
						if(checklimb.status == 0 && !checklimb.is_robotic())
							return ..(mapload, internal)
		else
			parent_organ = force_location
			return ..(mapload, internal)
		// invalid, spawn as dead...
		set_status(ORGAN_DEAD)
	else
		// engineered ones don't do all of the above
		if(force_location)
			parent_organ = force_location
	return ..(mapload, internal)

/mob/living/carbon/human/proc/random_malignant_organ( allowtumors = TRUE, allowparasites = TRUE, allowengineered = TRUE)
	// get a list of valid malignant organs and spawn one
	var/list/paths = list()
	if(allowtumors)
		paths += subtypesof(/obj/item/organ/internal/malignant/tumor)
	if(allowparasites)
		paths += subtypesof(/obj/item/organ/internal/malignant/parasite)
	if(allowengineered)
		paths += subtypesof(/obj/item/organ/internal/malignant/engineered)
		paths -= /obj/item/organ/internal/malignant/engineered/chemorgan // Don't use this one
	return malignant_organ_spawn(pick(paths)) // place in body

/mob/living/carbon/human/proc/malignant_organ_spawn(type_path)
	if(!type_path)
		return FALSE
	if(is_dead())
		return FALSE
	if(HAS_SYNTHETIC_BIOLOGY(src))
		return FALSE
	if(!species)
		return FALSE
	if(!species.can_host_malignant)
		return FALSE
	if(is_changeling(src))
		return FALSE

	var/obj/item/organ/internal/malignant/neworgan = new type_path( src, TRUE)
	if(neworgan.status == 0) // healthy new organ spawned... Otherwise this is a failure...
		return TRUE

	// welp, clean up.
	spent(neworgan)
	return FALSE



/obj/item/organ/internal/malignant/tumor
	name = "tumor"
	icon_state = "tumor"

	var/stage = 1
	var/stage_progress = 0



/obj/item/organ/internal/malignant/parasite
	name = "parasite"
	icon_state = "parasite"
	dead_icon = "parasite-dead"

	validBPspawns = list(BP_GROIN, BP_TORSO, BP_HEAD) // unlike tumors, we like certain other places!
	can_reject = 0

	var/feedchance = 1 	// fixed chance that parasite will feed this loop
	var/growth = 1 		// some parasites grow! the feedmod vars get multiplied by it as it does!
	var/feedmodmin = 1
	var/feedmodmax = 2

/obj/item/organ/internal/malignant/parasite/organ_tick(cycles)
	. = ..()

	if(cooldown > 0)
		cooldown--
		return

	if(!owner)
		return

	if(prob(feedchance))
		cooldown = rand(cooldownmin,cooldownmax)
		if(feed())
			growth++

/obj/item/organ/internal/malignant/parasite/proc/feed()
	// perform actions based on the parasite
	if(feedmodmax > 0)
		if(owner.nutrition > 0)
			owner.adjust_nutrition(-rand(growth * feedmodmin, growth * feedmodmax))
		else
			owner.remove_blood(1 + rand( growth * feedmodmin, growth * feedmodmax))
	// by default, don't grow. Other parasites might thought!
	return FALSE


/obj/item/organ/internal/malignant/engineered
	name = "engineered"
	icon_state = "engineered"
	dead_icon = "engineered-dead"
	can_reject = 0
	surgeryAllowedSites = list(BP_GROIN, BP_TORSO) // Lets keep these a little more restricted, due to size and complexity
	supply_conversion_value = 100

/obj/item/organ/internal/malignant/engineered/proc/update_degeneration(degradechance, intensity)
	if(degradechance == 0)
		return FALSE
	if(prob(degradechance))
		apply_lesion_damage(intensity, /datum/affliction/lesion/necrosis, TRUE)
		add_autopsy_data("Programmed degeneration", intensity)
	if(prob(damage * 2))
		return TRUE // do handle_sideeffects proc
	return FALSE

/obj/item/organ/internal/malignant/engineered/proc/handle_sideeffects(base_mult)
	if(damage < min_bruised_damage)
		// skip any major effects if under bruise damage
		return
	else
		if(prob(45))
			owner.status_adjust(STAT_WEAKENED, 3 * base_mult)
		if(prob(75))
			owner.status_adjust(STAT_CONFUSED, 4 * base_mult)
		var/obj/item/organ/external/O = owner.organs_by_name[parent_organ]
		if(damage >= min_broken_damage)
			owner.custom_pain(span_warning("You feel a painful sensation in your [O.name]."),damage,TRUE)
			owner.status_adjust(STAT_BLINDED, 6 * base_mult)
			owner.injure(INJURY_TOXIN, 4 * base_mult, flags = INJURE_SILENT)
		else
			owner.custom_pain(span_warning("You feel a strange sensation in your [O.name]."),damage / 10,TRUE)

/****************************************************
				Tumor varients
		these eventually kill you in some strange unique way.
****************************************************/

// cancer! *party blower*! Causes various bad symptoms, and eventually internally bleeds you to death.
/obj/item/organ/internal/malignant/tumor/cancer
	name = "tumor"
	cooldownmin = 15
	cooldownmax = 25

/obj/item/organ/internal/malignant/tumor/cancer/organ_tick(cycles)
	. = ..()

	if(cooldown > 0)
		cooldown--
		return

	if(!owner)
		return

	if(++stage_progress > 300)
		++stage
		stage_progress = rand(100,200)

	if(stage == 1)
		if(prob(1))
			owner.status_at_least(STAT_WEAKENED, 2)
			cooldown = rand(cooldownmin,cooldownmax)
	if(stage > 1)
		if(prob(1))
			owner.status_at_least(STAT_WEAKENED, 3)
			owner.injure(INJURY_TOXIN, 3, flags = INJURE_SILENT)
			owner.adjust_nutrition(-rand(1,5))
			cooldown = rand(cooldownmin,cooldownmax)
	if(stage > 2)
		if(prob(1))
			switch(parent_organ)
				if(BP_GROIN)
					owner.vomit()
				if(BP_HEAD)
					if(prob(30))
						owner.vomit()
					else if(prob(30))
						owner.status_adjust(STAT_DIZZY, 90)
					else
						owner.status_at_least(STAT_CONFUSED, 20)
			owner.adjust_nutrition(-rand(1,5))
			cooldown = rand(cooldownmin,cooldownmax)
	if(stage > 3)
		if(prob(1))
			var/obj/item/organ/external/bodypart = owner.get_organ(parent_organ)
			bodypart?.add_wound(new /datum/affliction/wound/internal_bleeding(bodypart, 2))
			bodypart?.update_damages()
			owner.status_at_least(STAT_WEAKENED, 10)
			owner.injure(INJURY_TOXIN, 20, flags = INJURE_SILENT)
			owner.adjust_nutrition(-rand(1,5))
			cooldown = rand(cooldownmin,cooldownmax)


// WHERE SOIL. Simple toxin damage that makes you throwup and lose nutrition sometimes
/obj/item/organ/internal/malignant/tumor/potato
	name = "mimetic potato"
	icon_state = "potato"
	validBPspawns = list(BP_GROIN, BP_TORSO)
	cooldownmin = 15
	cooldownmax = 35
	supply_conversion_value = 10

/obj/item/organ/internal/malignant/tumor/potato/organ_tick(cycles)
	. = ..()

	if(cooldown > 0)
		cooldown--
		return

	if(prob(3))
		owner.injure(INJURY_TOXIN, 2, flags = INJURE_SILENT)
		owner.adjust_nutrition(-rand(1,5))

	if(prob(2))
		owner.vomit()
		cooldown = rand(cooldownmin,cooldownmax)

// A knife cuts the mimetic potato into sticks; five lengths of cable make it a battery.
CAPABILITIES(/obj/item/organ/internal/malignant/tumor/potato)
	op("cut", item(/obj/item/material/knife), label("Cut"), priority(above("butcher")), then(PROC_REF(potato_cut)))
	op("wire", item(/obj/item/stack/cable_coil), label("Wire"), when(PROC_REF(enough_cable)), then(PROC_REF(potato_wired)))

/obj/item/organ/internal/malignant/tumor/potato/proc/potato_cut(datum/act/op/A)
	new /obj/item/reagent_containers/food/snacks/rawsticks(get_turf(src))
	to_chat(A.actor, span_notice("You cut the mimetic potato."))
	consume(src, A.actor)

/obj/item/organ/internal/malignant/tumor/potato/proc/enough_cable(datum/act/op/A)
	var/obj/item/stack/cable_coil/C = A.held
	return istype(C) && C.get_amount() >= 5

/obj/item/organ/internal/malignant/tumor/potato/proc/potato_wired(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/cable_coil/C = A.held
	if(!C.use(5))
		return
	//TODO: generalize this.
	to_chat(user, span_notice("You add some cable to the [src.name] and slide it inside the battery casing."))
	var/obj/item/cell/potato/pocell = new /obj/item/cell/potato(get_turf(user))
	if(src.loc == user && ishuman(user))
		user.put_in_hands(pocell)
	pocell.maxcharge = 2000 // same as potato
	pocell.charge = pocell.maxcharge
	consume(src, user)



/* Disabled gib tumors
// pinata makes you eventually explode into candy
/obj/item/organ/internal/malignant/tumor/pinata
	name = "pinata gland"
	icon_state = "pinata"

/obj/item/organ/internal/malignant/tumor/pinata/organ_tick(cycles)
	. = ..()

	if(stage_progress == 0)
		stage_progress = rand(10,60)
	stage_progress++

	if(cooldown > 0)
		cooldown--
		return

	if(stage_progress > 350)
		pop()
		return

	if(!owner)
		return

	if(prob(2))
		if(prob(30))
			owner.vomit()
		else if(prob(30))
			owner.status_adjust(STAT_DIZZY, 20)
		else
			owner.status_at_least(STAT_CONFUSED, 30)

	if(prob(2))
		var/obj/item/organ/external/O = owner.organs_by_name[parent_organ]
		if(stage_progress > 200)
			owner.custom_pain(span_warning("You feel bloated. The pain in your [O.name] is agonizing."),20,TRUE)
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "winces slightly.", check_stat = TRUE)
		else if(stage_progress > 100)
			owner.custom_pain(span_warning("You feel a pressure inside your [O.name]."),5,TRUE)
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "winces painfully.", check_stat = TRUE)
		else
			owner.custom_pain(span_danger("The pressure inside your [O.name] hurts."),1,TRUE)
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "winces painfully.", check_stat = TRUE)

// Anything that punctures pops it.
CAPABILITIES(/obj/item/organ/internal/malignant/tumor/pinata)
	op("pop", item(/obj/item), label("Pop"), priority(above("butcher")), when(PROC_REF(punctured_by)), then(PROC_REF(popped)))

/obj/item/organ/internal/malignant/tumor/pinata/proc/punctured_by(datum/act/op/A)
	return can_puncture(A.held)

/obj/item/organ/internal/malignant/tumor/pinata/proc/popped(datum/act/op/A)
	pop()

/obj/item/organ/internal/malignant/tumor/pinata/proc/pop()
	// place a ton of candy at location, then delete organ!
	var/count = rand(20,30)
	while(count-- > 0)
		var/picker = pick(/obj/item/clothing/mask/chewable/candy/gum,/obj/item/clothing/mask/chewable/candy/lolli,/obj/item/reagent_containers/food/snacks/candy/gummy,/obj/item/reagent_containers/food/snacks/candy_corn)
		new picker(loc)

	var/turf/T = loc
	if(owner)
		// SURPRISE!
		play_sfx(owner, SFX_ITEMS_CONFETTI, 1.5, vary = TRUE)
		play_sfx(src, SFX_EFFECTS_SNAP)
		owner.gib()
		T = owner.loc
	else
		// only the organ pops!
		play_sfx(src, SFX_ITEMS_CONFETTI, 1.5, vary = TRUE)
		play_sfx(src, SFX_EFFECTS_SNAP)

	// YAYYYYY
	if(!turf_clear(T))
		T = get_turf(src)
	new /obj/effect/decal/cleanable/confetti(T)
	spent(src)
*/


// Teleports you randomly, until it gets you killed
/obj/item/organ/internal/malignant/tumor/bluespace
	name = "bluespace tumor"
	icon_state = "bluetumor"
	validBPspawns = list(BP_GROIN, BP_TORSO)
	cooldownmin = 25
	cooldownmax = 65
	supply_conversion_value = 50

/obj/item/organ/internal/malignant/tumor/bluespace/organ_tick(cycles)
	. = ..()

	if(cooldown > 0)
		cooldown--
		return

	if(!owner)
		return

	if(stage_progress == 0)
		stage_progress = rand(10,60)
	stage_progress++

	if(stage_progress > 300 && stage < 6)
		stage++
		stage_progress = 0

	if(prob(stage * 2))
		var/outer_teleport_radius = stage * 2
		var/inner_teleport_radius = stage / 2

		var/list/turfs = list()
		if(inner_teleport_radius > 0)
			for(var/turf/T in orange(owner,outer_teleport_radius))
				if(get_dist(owner,T) >= inner_teleport_radius)
					turfs |= T

		if(turfs.len)
			// Moves the mob, causes sparks.
			fx_sparks(get_turf(owner), 3)
			var/turf/picked = get_turf(pick(turfs))                      // Just in case...
			owner.forceMove(picked) // And teleport them to the chosen location.
		cooldown = rand(cooldownmin,cooldownmax)


// Get you drunk constantly until liver failure
/obj/item/organ/internal/malignant/tumor/beerbelly
	name = "beerbelly"
	icon_state = "beerbelly"
	validBPspawns = list(BP_GROIN)
	cooldownmin = 25
	cooldownmax = 95
	supply_conversion_value = 50

/obj/item/organ/internal/malignant/tumor/beerbelly/organ_tick(cycles)
	. = ..()

	if(!owner)
		return

	if(cooldown > 0)
		cooldown--
		return

	if(stage_progress == 0)
		stage_progress = rand(10,60)
	stage_progress++

	if(stage_progress > 350 && stage < 10)
		stage++
		stage_progress = 0

	if(prob(12))
		owner.bloodstr.add_reagent( "ethanol", stage * 2)
		cooldown = rand(cooldownmin,cooldownmax)

/* Disable gib tumors
// Prints money until you explode
/obj/item/organ/internal/malignant/tumor/moneyorgan
	name = "crypto-cache"
	icon_state = "crypto"
	cooldownmin = 15
	cooldownmax = 25
	var/thalers = 0
	supply_conversion_value = 25

/obj/item/organ/internal/malignant/tumor/moneyorgan/organ_tick(cycles)
	. = ..()

	if(!owner)
		return

	if(cooldown > 0)
		cooldown--
		return

	stage_progress++
	if(stage_progress > 150 && stage < 100)
		stage++
		stage_progress = 0

	if(prob(6))
		thalers += stage
		supply_conversion_value = initial(supply_conversion_value) + ((thalers * SSsupply.points_per_money))

	if(prob(2))
		var/obj/item/organ/external/O = owner.organs_by_name[parent_organ]
		if(thalers < 100)
			pass()
		else if(thalers < 500)
			owner.custom_pain(span_warning("You feel bloated."),1,TRUE)
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "winces slightly.", check_stat = TRUE)
		else if(thalers < 1000)
			owner.custom_pain(span_warning("You feel a pressure inside your [O.name]."),6,TRUE)
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "winces painfully.", check_stat = TRUE)
			if(prob(30))
				owner.vomit()
			else if(prob(30))
				owner.status_adjust(STAT_DIZZY, 10)
			else
				owner.status_at_least(STAT_CONFUSED, 15)
		else if(thalers < 5000)
			owner.custom_pain(span_danger("The pressure inside your [O.name] hurts."),15,TRUE)
			owner.automatic_custom_emote(VISIBLE_MESSAGE, "winces painfully.", check_stat = TRUE)
			owner.status_at_least(STAT_WEAKENED, 3)
			if(prob(30))
				owner.status_at_least(STAT_STUNNED, 10)
				owner.status_at_least(STAT_PARALYZED, 4)
			if(prob(30))
				owner.vomit()
			else if(prob(30))
				owner.status_adjust(STAT_DIZZY, 20)
			else
				owner.status_at_least(STAT_CONFUSED, 30)
		else
			pop()
		cooldown = rand(cooldownmin,cooldownmax)

// Anything that punctures pops it.
CAPABILITIES(/obj/item/organ/internal/malignant/tumor/moneyorgan)
	op("pop", item(/obj/item), label("Pop"), priority(above("butcher")), when(PROC_REF(punctured_by)), then(PROC_REF(popped)))

/obj/item/organ/internal/malignant/tumor/moneyorgan/proc/punctured_by(datum/act/op/A)
	return can_puncture(A.held)

/obj/item/organ/internal/malignant/tumor/moneyorgan/proc/popped(datum/act/op/A)
	pop()

/obj/item/organ/internal/malignant/tumor/moneyorgan/proc/pop()
	if(owner)
		owner.gib() //Kaboom!

	play_sfx(src, SFX_EFFECTS_SNAP)

	// place a ton of money at location, then delete organ!
	var/turf/T = get_turf(src)
	while(thalers > 1000)
		thalers -= 1000
		spawn_money(1000, T)
	while(thalers > 500)
		thalers -= 500
		spawn_money(500, T)
	while(thalers > 50)
		thalers -= 50
		spawn_money(50, T)
	while(thalers > 5)
		thalers -= 5
		spawn_money(5, T)
	while(thalers > 1)
		thalers -= 1
		spawn_money(1, T)

	spent(src)
*/


/****************************************************
				Parasite varients
		these produce something into your bloodstream.
		consuming nutrition, blood instead if starving
****************************************************/

// Makes all pain go away, gets greedy for food!
/obj/item/organ/internal/malignant/parasite/painleech
	name = "suffering-sucker"
	feedchance = 4
	feedmodmin = 6
	feedmodmax = 11
	cooldownmin = 20
	cooldownmax = 50

/obj/item/organ/internal/malignant/parasite/painleech/feed()
	..()
	owner.apply_body_effect(growth >= 5 ? /datum/body_effect/numbness/deep : /datum/body_effect/numbness, 3 SECONDS)
	return prob(10) && growth < 10


// honks and tells you jokes in your head
/obj/item/organ/internal/malignant/parasite/honker
	name = "honkworm"
	feedchance = 4
	feedmodmin = 2
	feedmodmax = 3
	cooldownmin = 30
	cooldownmax = 60

/obj/item/organ/internal/malignant/parasite/honker/feed()
	..()
	if(prob(80))
		var/sound = SFX_MISC_SADTROMBONE_MIX
		playsound(owner, sound, 50, 1)
	else
		// obnoxious, terrible jokes that'll get you punched by a vox
		var/jokelist = list("honk", \
							"hehe", \
							"Don't worry, my jokes have the same opinion about you!", \
							"Wowie, was that yours or the space asshole's?",
							"Space lube the airlock, engineers love it!", \
							"What does a vox choir sound like? ... Sorry I can't hear you.", \
							"How many teshari does it take to screw in a lightbulb? However many it takes to fit on the ladder.", \
							"Why does security wear red? So your blood stains won't get noticed!", \
							"I got some space wind for ya!", \
							"Honk ya mother!", \
							"Nice medbay! Now where's the survivors, Doc?", \
							"What's that borgi? The captain fell down the well!? Quickly, to the bar!")
		owner.say((prob(40) ? ";" : "") + "[pick(jokelist)]")
	return prob(5) && growth < 3


// Makes you high periodically
/obj/item/organ/internal/malignant/parasite/gethigh
	name = "woggler"
	feedchance = 4
	feedmodmin = 6
	feedmodmax = 11
	cooldownmin = 10
	cooldownmax = 40

/obj/item/organ/internal/malignant/parasite/gethigh/feed()
	..()
	owner.status_at_least(STAT_DRUGGED, 10 + (growth * 20))
	return prob(6) && growth < 5


/****************************************************
				Engineered varients
	specialized organs, made to be surgically grafted into people.
	Will find lots of use with abductors in the future!
****************************************************/

// Basic lattice, needs to grow in a host for a bit
/obj/item/organ/internal/malignant/engineered/lattice
	name = "organ lattice"
	icon_state = "lattice"
	desc = "A cellular framework made for engineering organs, it needs to grow before it can be mutated."
	var/growth = 0 		// grows until it hits trigger
	var/growth_trigger = 1
	var/prepared = FALSE
	var/chem_target = null
	supply_conversion_value = 0

CAPABILITIES(/obj/item/organ/internal/malignant/engineered/lattice)
	rolls(nameof(growth_trigger), range_of(150, 200))

/obj/item/organ/internal/malignant/engineered/lattice/organ_tick(cycles)
	. = ..()
	if(cooldown > 0)
		cooldown--
		return
	if(!owner)
		return
	if(chem_target)
		// finished, ready to TRANSFORM
		if(owner.radiation > 20)
			growth++
			owner.adjust_nutrition(-rand(1,3))
		if(owner.nutrition > 20)
			if(growth > growth_trigger)
				// spawn new organ, delete us
				var/newpath = get_mutation_result(chem_target)
				if(newpath)
					var/ourowner = owner
					var/ourloc = parent_organ
					var/ourtag = organ_tag
					spent(src)
					new newpath(ourowner, TRUE, ourloc, ourtag)
			cooldown = rand(2,5)
		else
			apply_lesion_damage(1, /datum/affliction/lesion/necrosis, TRUE)
			add_autopsy_data("Apoptotic training cells", 3)
			cooldown = rand(5,10)

	else if(!prepared)
		owner.adjust_nutrition(-rand(1,3))
		if(owner.nutrition > 20)
			growth++
		if(growth > growth_trigger)
			name = "proto-organ"
			icon_state = "lattice-grown"
			desc = "A half grown proto-organ ready for chemical injection."
			prepared = TRUE
			growth = 0
			update_icon()
		cooldown = rand(2,6)

/obj/item/organ/internal/malignant/engineered/lattice/proc/get_mutation_result(reagent)
	var/newpath = null
	switch(reagent)
		if(REAGENT_ID_PHORON)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/phoron
		if(REAGENT_ID_TRICORDRAZINE, REAGENT_ID_TRICORLIDAZE)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/tricord
		if(REAGENT_ID_TRAMADOL)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/tramadol
		if(REAGENT_ID_ANTITOXIN)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/dylovene
		if(REAGENT_ID_CITALOPRAM)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/citalopram
		if(REAGENT_ID_BICARIDINE, REAGENT_ID_BICARIDAZE)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/bicaridine
		if(REAGENT_ID_DERMALINE, REAGENT_ID_DERMALAZE)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/dermaline
		if(REAGENT_ID_KELOTANE)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/kelotane
		if(REAGENT_ID_DEXALIN, REAGENT_ID_DEXALINP)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/dexalin
		if(REAGENT_ID_HYPERZINE)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/hyperzine
		if(REAGENT_ID_SPACEACILLIN)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/spaceacillin
		if(REAGENT_ID_INAPROVALINE, REAGENT_ID_INAPROVALAZE)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/inaprovaline
		if(REAGENT_ID_BLISS)
			newpath = /obj/item/organ/internal/malignant/engineered/chemorgan/bliss
		if(REAGENT_ID_ETHANOL)
			newpath = /obj/item/organ/internal/malignant/tumor/beerbelly
		if(REAGENT_POTATOJUICE)
			newpath = /obj/item/organ/internal/malignant/tumor/potato

	return newpath

/obj/item/organ/internal/malignant/engineered/lattice/proc/make_mutoid(reagent)
	if(!prepared)
		return FALSE
	if(chem_target)
		return FALSE
	if(!get_mutation_result(reagent))
		return FALSE
	// BEGIN MUTATION PROCESS
	chem_target = reagent
	name = "mutoid"
	icon_state = "crypto" // TEMP TODO: "lattice-mutated"
	desc = "A fully grown mutoid ready for radiation training."
	growth = 0
	growth_trigger = rand(160,210) // we will quickly start dying now unless trained
	update_icon()
	return TRUE

// Chemical dispensing organs, USES SUB TYPES
/obj/item/organ/internal/malignant/engineered/chemorgan
	name = "chem organ DO NOT USE THIS"
	var/chemid = null
	var/deg_chance = 0.1
	var/deg_intensity = 1
	var/side_effect_multiplier = 1

/obj/item/organ/internal/malignant/engineered/chemorgan/organ_tick(cycles)
	. = ..()
	if(cooldown > 0)
		cooldown--
		return
	if(!owner)
		return
	if(!chemid)
		return
	if(prob(15))
		// stacked rng to lower the damage over the round
		if(update_degeneration( deg_chance, deg_intensity))
			handle_sideeffects(side_effect_multiplier)
	else
		// process the chems!
		if(owner.bloodstr.get_reagent_amount(chemid) < 5)
			if(prob(10))
				owner.adjust_nutrition(-1) // num num
			owner.bloodstr.add_reagent(chemid,rand(5,10))
			cooldown = rand(5,10)

/obj/item/organ/internal/malignant/engineered/chemorgan/phoron
	name = "phoroketic gland"
	icon_state = "chem_phoron"
	chemid = REAGENT_ID_PHORON

/obj/item/organ/internal/malignant/engineered/chemorgan/tricord
	name = "trioketic gland"
	icon_state = "chem_tricord"
	chemid = REAGENT_ID_TRICORDRAZINE

/obj/item/organ/internal/malignant/engineered/chemorgan/tramadol
	name = "tramoketic gland"
	icon_state = "chem_tramadol"
	chemid = REAGENT_ID_TRAMADOL
	deg_chance = 0.25
	deg_intensity = 2
	side_effect_multiplier = 1

/obj/item/organ/internal/malignant/engineered/chemorgan/dylovene
	name = "dylovetic gland"
	icon_state = "chem_dylo"
	chemid = REAGENT_ID_ANTITOXIN

/obj/item/organ/internal/malignant/engineered/chemorgan/citalopram
	name = "citometic gland"
	icon_state = "chem_cita"
	chemid = REAGENT_ID_CITALOPRAM

/obj/item/organ/internal/malignant/engineered/chemorgan/bicaridine
	name = "bicordic gland"
	icon_state = "chem_bicar"
	chemid = REAGENT_ID_BICARIDINE

/obj/item/organ/internal/malignant/engineered/chemorgan/dermaline
	name = "dermalic gland"
	icon_state = "chem_derma"
	chemid = REAGENT_ID_DERMALINE

/obj/item/organ/internal/malignant/engineered/chemorgan/kelotane
	name = "kelovetic gland"
	icon_state = "chem_kelo"
	chemid = REAGENT_ID_KELOTANE

/obj/item/organ/internal/malignant/engineered/chemorgan/dexalin
	name = "dexalic gland"
	icon_state = "chem_dexa"
	chemid = REAGENT_ID_DEXALIN
	deg_chance = 0.5
	deg_intensity = 1
	side_effect_multiplier = 2

/obj/item/organ/internal/malignant/engineered/chemorgan/hyperzine
	name = "hypalic gland"
	icon_state = "chem_hyper"
	chemid = REAGENT_ID_HYPERZINE

/obj/item/organ/internal/malignant/engineered/chemorgan/spaceacillin
	name = "spaceacilic gland"
	icon_state = "chem_cillin"
	chemid = REAGENT_ID_SPACEACILLIN

/obj/item/organ/internal/malignant/engineered/chemorgan/inaprovaline
	name = "inaprovic gland"
	icon_state = "chem_inapro"
	chemid = REAGENT_ID_INAPROVALINE

/obj/item/organ/internal/malignant/engineered/chemorgan/bliss
	name = "euphorian"
	icon_state = "chem_bliss"
	chemid = REAGENT_ID_BLISS
	deg_chance = 1
	deg_intensity = 3
	side_effect_multiplier = 2

// This organ has work every organ_tick(), so the body's organ clock stays running for it.
/obj/item/organ/internal/malignant/life_step_idle()
	return FALSE

