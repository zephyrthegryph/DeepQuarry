/obj/item/storage/box/bloodpacks
	starts_with = list(
		/obj/item/reagent_containers/blood/empty = 7,
	)
	name = "blood packs bags"
	desc = "This box contains blood packs."
	icon_state = "sterile"

/obj/item/reagent_containers/blood
	name = "IV pack"
	var/base_name = " "
	desc = "Holds liquids used for transfusion."
	var/base_desc = " "
	icon = 'icons/obj/bloodpack.dmi'
	icon_state = "empty"
	item_state = "bloodpack_empty"
	drop_sound = SFX_ITEMS_DROP_FOOD
	pickup_sound = SFX_ITEMS_PICKUP_FOOD
	volume = 200
	var/label_text = ""

	var/blood_type = null
	var/reag_id = REAGENT_ID_BLOOD
	/// Species and colour of stock blood (blood_incompatible() reads the species).
	var/blood_species = SPECIES_HUMAN
	var/blood_colour = COLOR_BLOOD_HUMAN

/obj/item/reagent_containers/blood/Initialize(mapload)
	. = ..()
	base_name = name
	base_desc = desc
	if(blood_type != null)
		label_text = "[blood_type]"
		update_iv_label()
		// B17: stock packs are human blood; without "species" they matched every species.
		reagents.add_reagent(reag_id, 200, list("donor"=null,"viruses"=null,"species"=blood_species,"blood_colour"=blood_colour,"blood_DNA"=null,"blood_type"=blood_type,"resistances"=null,"trace_chem"=null,"changeling"=FALSE))

/// A pack shows how full it is: it follows the level its holder tracks.
/obj/item/reagent_containers/blood/draw(datum/look/look)
	..()
	look.watch(reagents)
	var/percent = volume ? round((reagents.total_volume / volume) * 100) : 0
	if(percent >= 0 && percent <= 9)
		look.state("empty")
		look.held_state("bloodpack_empty")
	else if(percent >= 10 && percent <= 50)
		look.state("half")
		look.held_state("bloodpack_half")
	else if(percent >= 51 && percent < INFINITY)
		look.state("full")
		look.held_state("bloodpack_full")

// A blood pack is a sealed holder of its volume (a syringe draws from it; an IV drip and a stand have their own ways in). A pen labels it (up to fifty
// characters; the name shows ten); in a hostile stance, using it in hand drinks a tenth of it, a feeding for the one who lives on blood.
CAPABILITIES(/obj/item/reagent_containers/blood)
	reagent_container(
		volume = nameof(volume),
		needle = TRUE,
		sealed = TRUE,
		settable = FALSE,
		shows_contents = FALSE,
		transfer_default = nameof(amount_per_transfer_from_this))
	op("label", inputs(item(/obj/item/pen), item(/obj/item/flashlight/pen)), label("Label it"),
		asks(/datum/prompt/text, fields = list("question" = "Enter a label for it:")), then(PROC_REF(label_applied)))
	op("drink", in_hand(), stance(I_HURT), label("Drink"), then(PROC_REF(drunk)))

/// The label a pen wrote (the old rules: fifty characters at most, a long one is told so).
/obj/item/reagent_containers/blood/proc/label_applied(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/mob/user = A.actor
	var/tmp_label = sanitizeSafe(R?.value, MAX_NAME_LEN)
	if(length(tmp_label) > 50)
		to_chat(user, span_notice("The label can be at most 50 characters long."))
	else if(length(tmp_label) > 10)
		to_chat(user, span_notice("You set the label."))
		label_text = tmp_label
		update_iv_label()
	else
		to_chat(user, span_notice("You set the label to \"[tmp_label]\"."))
		label_text = tmp_label
		update_iv_label()
	return OP_OK

/obj/item/reagent_containers/blood/proc/update_iv_label()
	if(label_text == "")
		name = base_name
	else if(length(label_text) > 10)
		var/short_label_text = copytext(label_text, 1, 11)
		name = "[base_name] ([short_label_text]...)"
	else
		name = "[base_name] ([label_text])"
	desc = "[base_desc] It is labeled \"[label_text]\"."

/obj/item/reagent_containers/blood/APlus
	blood_type = "A+"

/obj/item/reagent_containers/blood/AMinus
	blood_type = "A-"

/obj/item/reagent_containers/blood/BPlus
	blood_type = "B+"

/obj/item/reagent_containers/blood/BMinus
	blood_type = "B-"

/obj/item/reagent_containers/blood/OPlus
	blood_type = "O+"

/obj/item/reagent_containers/blood/OMinus
	blood_type = "O-"

/obj/item/reagent_containers/blood/synthplas
	blood_type = "O-"
	reag_id = REAGENT_ID_SYNTHBLOOD_DILUTE

/obj/item/reagent_containers/blood/synthblood
	blood_type = "O-"
	reag_id = REAGENT_ID_SYNTHBLOOD

/obj/item/reagent_containers/blood/empty
	name = "Empty BloodPack"
	desc = "Seems pretty useless... Maybe if there were a way to fill it?"
	icon_state = "empty"
	item_state = "bloodpack_empty"

/obj/item/reagent_containers/blood/random_bloodsucker
	name = "Ration BloodPack"
	desc = "A standard issue BloodPack Ration given to crew that require blood to be sustained!"

CAPABILITIES(/obj/item/reagent_containers/blood/random_bloodsucker)
	rolls(nameof(blood_type), pick_one(list("A+", "A-", "B+", "B-", "O-", "O+", "AB+", "AB-")))

/// Drunk from in a hostile stance: a tenth of it, if it is blood.
/obj/item/reagent_containers/blood/proc/drunk(datum/act/op/A)
	var/mob/living/user = A.actor
	if(reagents.total_volume && volume)
		var/remove_volume = volume * 0.1 //10% of what the bloodpack can hold.
		var/reagent_to_remove = reagents.get_master_reagent_id()
		switch(reagents.get_master_reagent_id())
			if(REAGENT_ID_BLOOD)
				user.show_message(span_warning("You sink your fangs into \the [src] and suck the blood out of it!"))
				act_message(user, src, others = span_red("%U% sinks their fangs into %T% and drains it!"))
				user.adjust_nutrition(remove_volume*5)
				reagents.remove_reagent(reagent_to_remove, remove_volume)
			else
				user.show_message(span_warning("You take a look at \the [src] and notice that it is not filled with blood!"))
	else
		user.show_message(span_warning("You take a look at \the [src] and notice it has nothing in it!"))
	return OP_OK

/obj/item/reagent_containers/blood/prelabeled
	name = "IV Pack"
	desc = "Holds liquids used for transfusion. This one's label seems to be hardprinted."

/obj/item/reagent_containers/blood/prelabeled/update_iv_label()
	return

/obj/item/reagent_containers/blood/prelabeled/APlus
	name = "IV Pack (A+)"
	desc = "Holds liquids used for transfusion. This one's label seems to be hardprinted. This one is labeled A+"
	blood_type = "A+"

/obj/item/reagent_containers/blood/prelabeled/AMinus
	name = "IV Pack (A-)"
	desc = "Holds liquids used for transfusion. This one's label seems to be hardprinted. This one is labeled A_"
	blood_type = "A-"

/obj/item/reagent_containers/blood/prelabeled/BPlus
	name = "IV Pack (B+)"
	desc = "Holds liquids used for transfusion. This one's label seems to be hardprinted. This one is labeled B+"
	blood_type = "B+"

/obj/item/reagent_containers/blood/prelabeled/BMinus
	name = "IV Pack (B-)"
	desc = "Holds liquids used for transfusion. This one's label seems to be hardprinted. This one is labeled B-"
	blood_type = "B-"

/obj/item/reagent_containers/blood/prelabeled/OPlus
	name = "IV Pack (O+)"
	desc = "Holds liquids used for transfusion. This one's label seems to be hardprinted. This one is labeled O+"
	blood_type = "O+"

/obj/item/reagent_containers/blood/prelabeled/OMinus
	name = "IV Pack (O-)"
	desc = "Holds liquids used for transfusion. This one's label seems to be hardprinted. This one is labeled O-"
	blood_type = "O-"
