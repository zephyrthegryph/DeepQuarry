#define BLOOD_MINIMUM_STOP_PROCESS 2.1 // Define to avoid hitting 0 blood.
/****************************************************
				BLOOD SYSTEM
****************************************************/
//Blood levels. These are percentages based on the species blood_volume var.
//Retained for archival/reference purposes - KK
/*
BLOOD_VOLUME_SAFE =    85
BLOOD_VOLUME_OKAY =    75
BLOOD_VOLUME_BAD =     60
BLOOD_VOLUME_SURVIVE = 40
*/

/mob/living/carbon/human/var/datum/reagents/vessel // Container for blood and BLOOD ONLY. Do not transfer other chems here.
/mob/living/carbon/human/var/var/pale = 0          // Should affect how mob sprite is drawn, but currently doesn't.


/***Initializes blood vessels
 * Called code/modules/mob/living/carbon/human/human.dm#L1259 set_species procedure with 0 args
 * Also called by inject_blood as fallback with amt = injected_amount
 * MUST be followed by calling fixblood() allways.
***/
/mob/living/carbon/human/proc/make_blood(amt = 0)

	if(vessel)
		return

	if(species.flags & NO_BLOOD)
		return

	rel_set(src, nameof(vessel), new/datum/reagents(species.blood_volume))
	rel_set(vessel, nameof(vessel.my_atom), src)

	if(!should_have_organ(O_HEART)) //We want the var for safety but we can do without the actual blood.
		return

	if(!amt)
		vessel.add_reagent(REAGENT_ID_BLOOD,species.blood_volume)
	else
		vessel.add_reagent(REAGENT_ID_BLOOD, clamp(amt, 1, species.blood_volume))


//Resets blood data
/mob/living/carbon/human/proc/fixblood()
	for(var/datum/reagent/blood/B in vessel.reagent_list)
		if(B.id == REAGENT_ID_BLOOD)
			B.data = list(	"donor"=src,"viruses"=null,"species"=species.name,"blood_DNA"=dna.unique_enzymes,"blood_colour"= species.get_blood_colour(src),"blood_type"=dna.b_type,	\
							"resistances"=null,"trace_chem"=null, "virus2" = null, REAGENT_ID_ANTIBODIES = list(), "blood_name" = species.get_blood_name(src))

			if(HAS_SYNTHETIC_BIOLOGY(src))
				B.data["species"] = "synthetic"

			var/changeling_blood = (!isnull(mind) && is_changeling(mind)) || species?.ambulant_blood || has_trait(src, TRAIT_REDSPACE_CORRUPTED)
			B.data["changeling"] = changeling_blood
			B.color = B.data["blood_colour"]
			B.name = B.data["blood_name"]

//Makes a blood drop, leaking amt units of blood from the mob
/mob/living/carbon/human/proc/drip(amt)
	if(remove_blood(amt))
		blood_splatter(src,src)

/mob/living/carbon/human/proc/remove_blood(amt)
	if(!should_have_organ(O_HEART)) //TODO: Make drips come from the reagents instead.
		return 0

	if(!amt)
		return 0

	//CHOMNPAdd Start, deathbringers for example delete those before the fire damage is calculated
	if(!vessel)
		return 0

	var/current_blood = vessel.get_reagent_amount(REAGENT_ID_BLOOD)
	if(current_blood < BLOOD_MINIMUM_STOP_PROCESS)
		return 0 //We stop processing under 3 units of blood because apparently weird shit can make it overflowrandomly.

	if(amt > current_blood)
		amt = current_blood - 2	// Bit of a safety net; it's impossible to add blood if there's not blood already in the vessel.

	return vessel.remove_reagent(REAGENT_ID_BLOOD,amt)

/****************************************************
				BLOOD TRANSFERS
****************************************************/

//Gets blood from mob to the container, preserving all data in it.
/mob/living/carbon/proc/take_blood(obj/item/reagent_containers/container, amount)

	var/datum/reagent/B = get_blood(container.reagents)
	// B3: blood already in the container that isn't ours (another donor, a stock pack) is never
	// relabelled as ours: refuse to draw rather than mix two donors under one label.
	if(B && B.data?["donor"] != src)
		return null
	if(!B)
		B = new /datum/reagent/blood
	rel_set(B, nameof(B.holder), container.reagents)
	B.volume += amount

	//set reagent data
	B.data["donor"] = src // ALLOW(ownership): reagent data is a plain payload dict shared with the chemistry code; donor is read back as a nullable mob
	if(!B.data["viruses"])
		B.data["viruses"] = list()

	for(var/datum/affliction/contagion/D in get_contagions())
		B.data["viruses"] |= D.Copy()

	if(!B.data["resistances"])
		B.data["resistances"] = list()

	if(B.data["resistances"])
		B.data["resistances"] |= get_contagion_immunities()
	B.data["blood_DNA"] = copytext(src.dna.unique_enzymes,1,0)
	B.data["blood_type"] = copytext(src.dna.b_type,1,0)
	var/changeling_blood = (!isnull(mind) && is_changeling(mind)) || species?.ambulant_blood || has_trait(src, TRAIT_REDSPACE_CORRUPTED)
	B.data["changeling"] = changeling_blood

	// Putting this here due to return shenanigans.
	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		var/drawn_colour = H.species.get_blood_colour(H)
		B.data["blood_colour"] = drawn_colour
		B.color = B.data["blood_colour"]
		// B17: drawn blood carries its species, as the vessel's does (fixblood()), so
		// blood_incompatible() can refuse a cross-species transfusion.
		var/datum/reagent/blood/own = H.vessel ? get_blood(H.vessel) : null
		B.data["species"] = own?.data?["species"] || H.species.name

	var/list/temp_chem = list()
	for(var/datum/reagent/R in src.reagents.reagent_list)
		temp_chem += R.id
		temp_chem[R.id] = R.volume
	B.data["trace_chem"] = list2params(temp_chem)
	return B

//For humans, blood does not appear from blue, it comes from vessels.
/mob/living/carbon/human/take_blood(obj/item/reagent_containers/container, amount)

	if(!should_have_organ(O_HEART))
		return null

	if(vessel.get_reagent_amount(REAGENT_ID_BLOOD) < max(amount, BLOOD_MINIMUM_STOP_PROCESS))
		return null

	. = ..()
	if(.) // B3: a refused draw takes nothing from the vessel
		remove_blood(amount) // Removes blood if human

//Transfers blood from container ot vessels
/mob/living/carbon/proc/inject_blood(datum/reagent/blood/injected, amount)
	if (!injected || !istype(injected))
		return
	var/list/sniffles = injected.data["viruses"]
	for(var/ID in sniffles)
		var/datum/affliction/contagion/D = ID
		if(D.spread_flags & (DISEASE_SPREAD_SPECIAL | DISEASE_SPREAD_NON_CONTAGIOUS)) // Special/Non-Contagious stay in the blood, but they won't spread
			continue
		force_contagion(D)
	if (injected.data["resistances"] && prob(5))
		antibodies |= injected.data["resistances"]
	if (injected.data[REAGENT_ID_ANTIBODIES] && prob(5))
		antibodies |= injected.data[REAGENT_ID_ANTIBODIES]
	var/list/chems = list()
	chems = params2list(injected.data["trace_chem"])
	for(var/C in chems)
		src.reagents.add_reagent(C, (text2num(chems[C]) / species.blood_volume) * amount)//adds trace chemicals to owner's blood
	reagents.update_total()

//Transfers blood from reagents to vessel, respecting blood types compatability.
/mob/living/carbon/human/inject_blood(datum/reagent/blood/injected, amount)

	if(!should_have_organ(O_HEART))
		reagents.add_reagent(REAGENT_ID_BLOOD, amount, injected.data)
		reagents.update_total()
		return

	var/datum/reagent/blood/our = get_blood(vessel)

	if (!injected)
		return
	if(!our)
		log_runtime("[src] has no blood reagent, proceeding with fallback reinitialization.")
		rel_clear(src, nameof(vessel))
		make_blood(amount)
		if(!vessel)
			log_runtime("Failed to re-initialize blood datums on [src]!")
			return
		if(vessel.total_volume < species.blood_volume)
			vessel.add_reagent(REAGENT_ID_BLOOD, species.blood_volume - vessel.total_volume)
		else if(vessel.total_volume > species.blood_volume)
			vessel.maximum_volume = species.blood_volume
		fixblood()
		our = get_blood(vessel)
		if(!our)
			log_runtime("Failed to re-initialize blood datums on [src]!")
			return
	if((is_changeling(src) || has_trait(src, TRAIT_REDSPACE_CORRUPTED))) //Changelings don't reject blood!
		vessel.add_reagent(REAGENT_ID_BLOOD, amount, injected.data)
		vessel.update_total()
	else if(blood_incompatible(injected.data["blood_type"],our.data["blood_type"],injected.data["species"],our.data["species"]) )
		reagents.add_reagent(REAGENT_ID_TOXIN,amount * 0.5)
		reagents.update_total()
	else
		vessel.add_reagent(REAGENT_ID_BLOOD, amount, injected.data)
		vessel.update_total()
	..()

//Gets human's own blood.
/mob/living/carbon/proc/get_blood(datum/reagents/container)
	var/datum/reagent/blood/res = locate_in_list(container.reagent_list, /datum/reagent/blood) //Grab some blood
	if(res) // Make sure there's some blood at all
		if(res.data["donor"] != src) //If it's not theirs, then we look for theirs
			for(var/datum/reagent/blood/D in container.reagent_list)
				if(D.data["donor"] == src)
					return D
	return res

/proc/blood_incompatible(donor,receiver,donor_species,receiver_species)
	if(!donor || !receiver) return 0

	if(donor_species && receiver_species)
		if(donor_species != receiver_species)
			return 1

	var/donor_antigen = copytext(donor,1,length(donor))
	var/receiver_antigen = copytext(receiver,1,length(receiver))
	var/donor_rh = (findtext(donor,"+")>0)
	var/receiver_rh = (findtext(receiver,"+")>0)

	if(donor_rh && !receiver_rh) return 1
	switch(receiver_antigen)
		if("A")
			if(donor_antigen != "A" && donor_antigen != "O") return 1
		if("B")
			if(donor_antigen != "B" && donor_antigen != "O") return 1
		if("O")
			if(donor_antigen != "O") return 1
		//AB is a universal receiver.
	return 0

/proc/blood_splatter(target,datum/reagent/blood/source,large)

	// We're not going to splatter at all because we're in something and that's silly.
	if(istype(source,/atom/movable))
		var/atom/movable/A = source
		if(!isturf(A.loc))
			return
	var/obj/effect/decal/cleanable/blood/B
	var/decal_type = /obj/effect/decal/cleanable/blood/splatter
	var/turf/T = get_turf(target)
	var/synth = 0

	if(ishuman(source))
		var/mob/living/carbon/human/M = source
		if(HAS_SYNTHETIC_BIOLOGY(M)) synth = 1
		source = M.get_blood(M.vessel)

	//Someone fed us a weird source. Let's log it.
	if(source && !istype(source, /datum/reagent/blood))
		log_runtime("A blood splatter was made using non-blood datum [source]!")
		source = null //Clear the source since it's invalid. Fallback to non-source behavior.

	// Are we dripping or splattering?
	var/list/drips = list()
	// Only a certain number of drips (or one large splatter) can be on a given turf.
	for(var/obj/effect/decal/cleanable/blood/drip/drop in contents_of(T))
		drips |= drop.drips
		consume(drop)
	if(!large && drips.len < 3)
		decal_type = /obj/effect/decal/cleanable/blood/drip

	// Find a blood decal or create a new one.
	B = locate_within(T, decal_type)
	if(!B)
		B = new decal_type(T)

	var/obj/effect/decal/cleanable/blood/drip/drop = B
	if(istype(drop) && drips && drips.len && !large)
		drop.add_overlay(drips)
		LAZYOR(drop.drips, drips)

	// If there's no data to copy, call it quits here.
	if(!istype(source))
		return B

	// Update appearance.
	if(source.data["blood_colour"])
		B.set_basecolor(source.data["blood_colour"])
		B.set_synthblood(synth)

	if(source.data["blood_name"])
		B.name = source.data["blood_name"]

	// Update blood information.
	if(source.data["blood_DNA"])
		var/list/new_data = list()
		if(source.data["blood_type"])
			new_data[source.data["blood_DNA"]] = source.data["blood_type"]
		else
			new_data[source.data["blood_DNA"]] = "O+"
		B.init_forensic_data().merge_blooddna(null,new_data)

	// Update virus information.
	// Each holder owns its own contagion copies: never alias the reagent's list or its members.
	for(var/datum/affliction/contagion/D in source.data["viruses"])
		rel_add(B, nameof(B.viruses), D.Copy())

	dq_set_fluorescent(B, 0)
	B.invisibility = INVISIBILITY_NONE
	return B

#undef BLOOD_MINIMUM_STOP_PROCESS
