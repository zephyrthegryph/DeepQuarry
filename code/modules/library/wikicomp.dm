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

/obj/machinery/librarywikicomp/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/wikicomp_open_ui,
	)
	..()

/// Old attack_hand: `if(..()) return; ` then percussive maintenance / open the interface.
/datum/interaction/machine_hand/wikicomp_open_ui
	id = "wikicomp_open_ui"
	name = "Use"
	effect = /obj/machinery/librarywikicomp/proc/interaction_open_ui_impl

/obj/machinery/librarywikicomp/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	if(crash)
		user.visible_message("[user] performs percussive maintenance on \the [src].", "You try to smack some sense into \the [src].")
		if(prob(10))
			crash = FALSE
	if(!crash)
		tgui_interact(user)
		play_sfx(src, SFX_KEYBOARD) // into console
	return TRUE

/obj/machinery/librarywikicomp/allow_pai_interaction()
	return TRUE

DECLARE_UI(/obj/machinery/librarywikicomp, "PublicLibraryWiki")

/obj/machinery/librarywikicomp/ui_opening(mob/user, datum/tgui/ui)
	just_donated = FALSE


/obj/machinery/librarywikicomp/tgui_close(mob/user)
	. = ..()
	P = null
	sub_category= null
	searchmode = null

/obj/machinery/librarywikicomp/tgui_data(mob/user)
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

/obj/machinery/librarywikicomp/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	play_sfx(src, SFX_KEYBOARD) // into console
	return TRUE

UI_ACT(/obj/machinery/librarywikicomp, "closesearch", ui_act_closesearch)
UI_ACT_PROC(/obj/machinery/librarywikicomp, ui_act_closesearch)
	if(!crash)
		P = null
		searchmode = null
		sub_category = null
		doc_title = "Click a search entry!"
		doc_body = ""
	. = TRUE

UI_ACT(/obj/machinery/librarywikicomp, "swapsearch", ui_act_swapsearch, UI_ARG_VALUE("data"))
UI_ACT_PROC(/obj/machinery/librarywikicomp, ui_act_swapsearch)
	if(!crash)
		var/new_mode = params["data"]
		if(searchmode == new_mode)
			return FALSE
		P = null
		doc_title = null
		doc_body = null
		searchmode = new_mode
	. = TRUE

UI_ACT(/obj/machinery/librarywikicomp, "crash", ui_act_crash)
UI_ACT_PROC(/obj/machinery/librarywikicomp, ui_act_crash)
	// intentional TGUI crash, amazingly awful
	if(issilicon(ui.user) && ui.user.client)
		ui.user.client.create_fake_ad_popup_multiple(/atom/movable/screen/popup/default, rand(4,10))
	if(!crash)
		crash = TRUE
		// crashes till it fixes itself
		om_after(src, rand(1000, 4000), PROC_REF(uncrash))
	. = TRUE

UI_ACT(/obj/machinery/librarywikicomp, "print", ui_act_print)
UI_ACT_PROC(/obj/machinery/librarywikicomp, ui_act_print)
	if(!crash && doc_title && doc_body)
		visible_message(span_notice("[src] rattles and prints out a sheet of paper."))

		var/obj/item/paper/paper = new /obj/item/paper(loc)
		paper.name = doc_title
		paper.info = doc_body
	. = TRUE

UI_ACT(/obj/machinery/librarywikicomp, "setsubcat", ui_act_setsubcat, UI_ARG_VALUE("data"))
UI_ACT_PROC(/obj/machinery/librarywikicomp, ui_act_setsubcat)
	if(!crash)
		var/new_subcat = params["data"]
		if(sub_category == new_subcat)
			return FALSE
		P = null
		doc_title = null
		doc_body = null
		sub_category = new_subcat
	. = TRUE
// final search

UI_ACT(/obj/machinery/librarywikicomp, "search", ui_act_search, UI_ARG_VALUE("data"))
UI_ACT_PROC(/obj/machinery/librarywikicomp, ui_act_search)
	if(!crash)
		var/search = params["data"]
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

		P = new_page

		if(P)
			doc_title = P.title
			doc_body = P.get_print()
		else
			doc_title = "Error"
			doc_body = "Invalid data."
	. = TRUE
// Support the wiki

UI_ACT(/obj/machinery/librarywikicomp, "donate", ui_act_donate, UI_ARG_VALUE("donate"))
UI_ACT_PROC(/obj/machinery/librarywikicomp, ui_act_donate)
	if(!crash)
		var/amount = params["donate"]
		var/mob/living/carbon/human/H = ui.user
		if(!ishuman(H) || !H.IsAdvancedToolUser(TRUE))
			to_chat(ui.user,"Donating to Bingle.exo is Byond your comprehension!")
		else if(amount)
			var/obj/item/card/id/card = H.GetIdCard()
			var/pin
			if(id_card_needs_pin(card))
				pin = act_ask(ui.user, action, params, ui, "pin", /datum/om/prompt/number, message = "Enter pin code", title = "Donation")
				if(isnull(pin))
					return TRUE
			pay_donation(card, ui.user, amount, ui, pin)
	. = TRUE

/obj/machinery/librarywikicomp/proc/pay_donation(obj/item/card/id/I, mob/user, amount, datum/tgui/ui, pin)
	visible_message(span_info("[user] swipes a card through [src]."))
	play_sfx(src, SFX_MACHINES_ID_SWIPE)
	if(SSinternal_wiki.pay_with_card(I, user, src, amount, pin))
		play_sfx(src, SFX_MACHINES_PING, vary = TRUE)
		just_donated = TRUE
		SStgui.update_user_uis(user, ui)

// mapper varient for dorms and residences
/obj/machinery/librarywikicomp/personal
	name = "personal datacore computer"
	desc = "Have you Bingled THAT today?"

/// om_after() target: the prank crash fixes itself.
/obj/machinery/librarywikicomp/proc/uncrash()
	crash = FALSE
