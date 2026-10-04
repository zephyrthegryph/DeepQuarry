MATERIAL_MIX(/obj/item/slime_scanner, list(MAT_STEEL = 30,MAT_GLASS = 20))
/obj/item/slime_scanner
	name = "slime scanner"
	icon = 'icons/obj/device.dmi'
	icon_state = "xenobio"
	item_state = "xenobio"
	w_class = ITEMSIZE_SMALL
	throwforce = 0
	throw_speed = 3
	throw_range = 7
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

CAPABILITIES(/obj/item/slime_scanner)
	op("scan_slime", at_target(/mob/living), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Scan slime"),
		needs(req_adjacent(), req(/mob/living/simple_mob/slime/xenobio, of = ON_TARGET, because = PROC_REF(scan_refusal))), then(PROC_REF(slime_scanned)))

/obj/item/slime_scanner/proc/scan_refusal(datum/act/op/A)
	return span_infoplain(span_bold("This device can only scan lab-grown slimes!"))

/obj/item/slime_scanner/proc/slime_scanned(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/simple_mob/slime/xenobio/S = A.target
	user.show_message("Slime scan results:<br>[S.slime_color] [S.is_adult ? "adult" : "baby"] slime<br>Health: [round(S.vitality() * 100)]%<br>Mutation Probability: [S.mutation_chance]")

	var/list/mutations = list()
	for(var/potential_color in S.slime_mutation)
		var/mob/living/simple_mob/slime/xenobio/slime = potential_color
		mutations.Add(initial(slime.slime_color))
	user.show_message("Potental to mutate into [english_list(mutations)] colors.<br>Extract potential: [S.cores]<br>Nutrition: [S.nutrition]/[S.max_nutrition]")

	if (S.nutrition < S.get_starve_nutrition())
		user.show_message(span_warning("Warning: Subject is starving!"))
	else if (S.nutrition < S.get_hunger_nutrition())
		user.show_message(span_warning("Warning: Subject is hungry."))
	user.show_message("Electric change strength: [S.power_charge]")

	//resentment/rabid moved to /datum/slime_state on the slime mob.
	if(S.slime_state)
		if(S.slime_state.resentment)
			user.show_message(span_warning("Warning: Subject is harboring resentment."))
		if(S.slime_state.rabid)
			user.show_message(span_danger("Subject is enraged and extremely dangerous!"))
	if(S.harmless)
		user.show_message("Subject has been pacified.")
	if(S.unity)
		user.show_message("Subject is friendly to other slime colors.")

	user.show_message("Growth progress: [S.amount_grown]/10")
	return OP_OK
