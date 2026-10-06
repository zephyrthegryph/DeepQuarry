/*
 * Library Public Computer
 * Complete recode of this into a search engine for recipes and reagents
 */
/obj/machinery/librarywikicomp
	name = "datacore computer"
	icon = 'icons/obj/library.dmi'
	icon_state = "computer"
	anchored = TRUE
	density = TRUE

	desc = "Used for research, I swear!"

	VAR_PRIVATE/doc_title = "Click a search entry!"
	VAR_PRIVATE/doc_body = ""
	VAR_PRIVATE/searchmode = null
	VAR_PRIVATE/sub_category = null //sublists for food menu
	VAR_PRIVATE/crash = FALSE
	VAR_PRIVATE/just_donated = FALSE
	VAR_PRIVATE/datum/internal_wiki/page/P

/obj/machinery/librarywikicomp/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	if(crash)
		act_message(user, src, MSG_SELF("You try to smack some sense into %T%."), MSG_OTHERS("%U% performs percussive maintenance on %T%."))
		if(prob(10))
			crash = FALSE
	if(!crash)
		tgui_interact(user)
		play_sfx(src, SFX_KEYBOARD) // into console
	return TRUE

/obj/machinery/librarywikicomp/allow_pai_interaction()
	return TRUE

CAPABILITIES(/obj/machinery/librarywikicomp)
	interface("PublicLibraryWiki")
	without("ui_open")
	op("closesearch", ui_act("closesearch"), then(PROC_REF(ui_act_closesearch)))
	op("swapsearch", ui_act("swapsearch", arg("data", schema_text(4096))), then(PROC_REF(ui_act_swapsearch)))
	op("crash", ui_act("crash"), then(PROC_REF(ui_act_crash)))
	op("print", ui_act("print"), then(PROC_REF(ui_act_print)))
	op("setsubcat", ui_act("setsubcat", arg("data")), then(PROC_REF(ui_act_setsubcat)))
	op("search", ui_act("search", arg("data", schema_text(4096))), then(PROC_REF(ui_act_search)))
	op("donate", ui_act("donate", arg("donate", num())), asks(/datum/prompt/number, fields = list("question" = "Enter pin code", "title" = "Donation", "timeout" = 0), step = "pin", when = PROC_REF(donation_needs_pin)), then(PROC_REF(ui_act_donate)))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/librarywikicomp/ui_opening(mob/user, datum/tgui/ui)
	just_donated = FALSE


/obj/machinery/librarywikicomp/tgui_close(mob/user)
	. = ..()
	rel_clear(src, nameof(P))
	sub_category= null
	searchmode = null

/// /obj/machinery/librarywikicomp's window data.
/obj/machinery/librarywikicomp/ui_data(datum/act/eval/A)
	var/data = list()
	if(SSinternal_wiki)
		data["crash"] = crash
		data["botany_data"] = null
		data["material_data"] = null
		data["particle_data"] = null
		data["catalog_data"] = null
		data["ore_data"] = null
		data["virus_data"] = null
		data["gene_data"] = null
		data["sub_categories"] = null
		data["donated"] = SSinternal_wiki.get_donation_current()
		data["goal"] = SSinternal_wiki.get_donation_goal()
		data["has_donated"] = just_donated
		if(!crash)
			// search page
			data["errorText"] = ""
			data["searchmode"] = searchmode
			// get searches
			switch(searchmode)
				if("Food Recipes")
					data["sub_categories"] = SSinternal_wiki.get_appliances()
					data["search"] = list()
					if(sub_category)
						data["search"] = SSinternal_wiki.get_searchcache_food(sub_category)
					if(P)
						data["food_data"] = P.get_data()

				if("Drink Recipes")
					data["search"] = SSinternal_wiki.get_searchcache_drink()
					if(P)
						data["drink_data"] = P.get_data()

				if("Chemistry")
					data["search"] = SSinternal_wiki.get_searchcache_chem()
					if(P)
						data["chemistry_data"] = P.get_data()

				if("Botany")
					data["search"] = SSinternal_wiki.get_searchcache_seed()
					if(P)
						data["botany_data"] = P.get_data()

				if("Catalogs")
					data["sub_categories"] = SSinternal_wiki.get_catalogs()
					data["search"] = list()
					if(sub_category)
						data["search"] = SSinternal_wiki.get_searchcache_catalog(sub_category)
						if(P)
							data["catalog_data"] = P.get_data()

				if("Materials")
					data["search"] = SSinternal_wiki.get_searchcache_material()
					if(P)
						data["material_data"] = P.get_data()

				if("Particle Physics")
					data["search"] = SSinternal_wiki.get_searchcache_particle()
					if(P)
						data["particle_data"] = P.get_data()

				if("Ores")
					data["search"] = SSinternal_wiki.get_searchcache_ore()
					if(P)
						data["ore_data"] = P.get_data()

				if("Viruses")
					data["search"] = SSinternal_wiki.get_searchcache_viruses()
					if(P)
						data["virus_data"] = P.get_data()

				if("Genes")
					data["search"] = SSinternal_wiki.get_searchcache_genes()
					if(P)
						data["gene_data"] = P.get_data()

				else
					data["search"] = list()

			// display message
			data["print"] = (doc_body && length(doc_body) > 0)
		else
			// intentional TGUI crash, amazingly awful
			data["searchmode"] = "Error"
			data["search"] = null
	else
		data["errorText"] = "Database unreachable."
	return data

/obj/machinery/librarywikicomp/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	play_sfx(src, SFX_KEYBOARD) // into console
	return TRUE

/obj/machinery/librarywikicomp/proc/ui_act_closesearch(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!crash)
		rel_clear(src, nameof(/obj/machinery/librarywikicomp::P))
		searchmode = null
		sub_category = null
		doc_title = "Click a search entry!"
		doc_body = ""
	. = TRUE

/obj/machinery/librarywikicomp/proc/ui_act_swapsearch(datum/act/op/A, data)
	if(!ui_gate(A))
		return FALSE
	if(!crash)
		var/new_mode = data
		if(searchmode == new_mode)
			return FALSE
		rel_clear(src, nameof(/obj/machinery/librarywikicomp::P))
		doc_title = null
		doc_body = null
		searchmode = new_mode
	. = TRUE

/obj/machinery/librarywikicomp/proc/ui_act_crash(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	// intentional TGUI crash, amazingly awful
	if((A.authority & AUTH_REMOTE_ACCESS) && user.client) // a silicon's remote press
		user.client.create_fake_ad_popup_multiple(/atom/movable/screen/popup/default, rand(4,10))
	if(!crash)
		crash = TRUE
		// crashes till it fixes itself
		after(src, rand(100 SECONDS, 400 SECONDS), PROC_REF(uncrash))
	. = TRUE

/obj/machinery/librarywikicomp/proc/ui_act_print(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!crash && doc_title && doc_body)
		visible_message(span_notice("[src] rattles and prints out a sheet of paper."))

		var/obj/item/paper/paper = new /obj/item/paper(loc)
		paper.name = doc_title
		paper.info = doc_body
	. = TRUE

/obj/machinery/librarywikicomp/proc/ui_act_setsubcat(datum/act/op/A, data)
	if(!ui_gate(A))
		return FALSE
	if(!crash)
		var/new_subcat = data
		if(sub_category == new_subcat)
			return FALSE
		rel_clear(src, nameof(/obj/machinery/librarywikicomp::P))
		doc_title = null
		doc_body = null
		sub_category = new_subcat
	. = TRUE
// final search

/obj/machinery/librarywikicomp/proc/ui_act_search(datum/act/op/A, data)
	if(!ui_gate(A))
		return FALSE
	if(!crash)
		var/search = data
		var/datum/internal_wiki/page/new_page = null
		if(searchmode == "Food Recipes")
			new_page = SSinternal_wiki.get_page_food(search)
		if(searchmode == "Drink Recipes")
			new_page = SSinternal_wiki.get_page_drink(search)
		if(searchmode == "Chemistry")
			new_page = SSinternal_wiki.get_page_chem(search)
		if(searchmode == "Botany")
			new_page = SSinternal_wiki.get_page_seed(search)
		if(searchmode == "Catalogs")
			new_page = SSinternal_wiki.get_page_catalog(search)
		if(searchmode == "Materials")
			new_page = SSinternal_wiki.get_page_material(search)
		if(searchmode == "Particle Physics")
			new_page = SSinternal_wiki.get_page_particle(search)
		if(searchmode == "Ores")
			new_page = SSinternal_wiki.get_page_ore(search)
		if(searchmode == "Viruses")
			new_page = SSinternal_wiki.get_page_virus(search)
		if(searchmode == "Genes")
			new_page = SSinternal_wiki.get_page_gene(search)

		if(new_page == P)
			return FALSE

		rel_set(src, nameof(/obj/machinery/librarywikicomp::P), new_page)

		if(P)
			doc_title = P.title
			doc_body = P.get_print()
		else
			doc_title = "Error"
			doc_body = "Invalid data."
	. = TRUE
// Support the wiki

/obj/machinery/librarywikicomp/proc/ui_act_donate(datum/act/op/A, donate)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	if(!ui_gate(A))
		return FALSE
	if(!crash)
		var/amount = donate
		var/mob/living/carbon/human/H = user
		if(!ishuman(H) || !H.IsAdvancedToolUser(TRUE))
			to_chat(user,"Donating to Bingle.exo is Byond your comprehension!")
		else if(amount)
			var/obj/item/card/id/card = H.GetIdCard()
			var/pin
			if(id_card_needs_pin(card))
				pin = A.step_value("pin")
				if(isnull(pin))
					return TRUE
			pay_donation(card, user, amount, ui, pin)
	. = TRUE

/// The pin question opens for a human's donation while the terminal works (the handler uses the pin only for a card that needs one).
/obj/machinery/librarywikicomp/proc/donation_needs_pin(datum/act/op/A)
	return !crash && ishuman(A.actor) && A.args["donate"] // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens

/obj/machinery/librarywikicomp/proc/pay_donation(obj/item/card/id/I, mob/user, amount, datum/tgui/ui, pin)
	act_message(user, src, others = span_info("%U% swipes a card through %T%."))
	play_sfx(src, SFX_MACHINES_ID_SWIPE)
	if(SSinternal_wiki.pay_with_card(I, user, src, amount, pin))
		play_sfx(src, SFX_MACHINES_PING, vary = TRUE)
		just_donated = TRUE
		SStgui.update_user_uis(user, ui)

// mapper varient for dorms and residences
/obj/machinery/librarywikicomp/personal
	name = "personal datacore computer"
	desc = "Have you Bingled THAT today?"

/// after() target: the prank crash fixes itself.
/obj/machinery/librarywikicomp/proc/uncrash()
	crash = FALSE
