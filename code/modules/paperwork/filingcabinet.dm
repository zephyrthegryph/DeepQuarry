/* Filing cabinets!
 * Contains:
 *		Filing Cabinets
 *		Security Record Cabinets
 *		Medical Record Cabinets
 */


/*
 * Filing Cabinets
 */
/obj/structure/filingcabinet
	name = "filing cabinet"
	desc = "A large cabinet with drawers."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "filingcabinet"
	density = TRUE
	anchored = TRUE

/obj/structure/filingcabinet/chestdrawer
	name = "chest drawer"
	icon_state = "chestdrawer"

/obj/structure/filingcabinet/filingcabinet	//not changing the path to avoid unecessary map issues, but please don't name stuff like this in the future -Pete
	icon_state = "tallcabinet"


/obj/structure/filingcabinet/Initialize(mapload)
	for(var/obj/item/I in contents_of(loc))
		if(istype(I, /obj/item/paper) || istype(I, /obj/item/folder) || istype(I, /obj/item/photo) || istype(I, /obj/item/paper_bundle))
			I.forceMove(src)
	. = ..()
	make_climbable()

/// Old attackby.
/obj/structure/filingcabinet/proc/interaction_item(mob/user, obj/item/P, datum/interaction/interaction)
	if(istype(P, /obj/item/paper) || istype(P, /obj/item/folder) || istype(P, /obj/item/photo) || istype(P, /obj/item/paper_bundle))
		to_chat(user, span_notice("You put [P] in [src]."))
		user.drop_item()
		P.forceMove(src)
		open_animation()
		SStgui.update_uis(src)
	else
		to_chat(user, span_notice("You can't put [P] in [src]!"))
	return INTERACTION_HANDLED_PASS

/obj/structure/filingcabinet/wrench_act(mob/user, obj/item/tool)
	playsound(src, tool.usesound, 50, TRUE)
	anchored = !anchored
	to_chat(user, span_notice("You [anchored ? "wrench" : "unwrench"] \the [src]."))
	return ITEM_INTERACT_SUCCESS

/obj/structure/filingcabinet/screwdriver_act(mob/user, obj/item/tool)
	use_tool(user, tool, src, delay = 1 SECOND, volume = 50, message_self = "You begin taking the [name] apart.", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user, tool))
	return ITEM_INTERACT_SUCCESS

/obj/structure/filingcabinet/proc/screwdriver_act_tool_done(mob/user, obj/item/tool)
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_notice("You take the [name] apart."))
	new /obj/item/stack/material/steel(loc, 4)
	for(var/obj/item/I in contents)
		I.forceMove(loc)
	qdel(src)
	return ITEM_INTERACT_SUCCESS

DECLARE_INTERACTIONS(/obj/structure/filingcabinet, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_TK(null, PROC_REF(interaction_tk)), \
)

/// Old attack_hand.
/obj/structure/filingcabinet/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(contents_count(src) <= 0)
		to_chat(user, span_notice("\The [src] is empty."))
		return TRUE

	tgui_interact(user)
	return TRUE

/// Old attack_tk: rummage in an anchored cabinet at range.
/obj/structure/filingcabinet/proc/interaction_tk(mob/user, obj/item/held, datum/interaction/interaction)
	if(!anchored)
		return FALSE
	attack_self_tk(user)
	return TRUE

/obj/structure/filingcabinet/attack_self_tk(mob/user)
	if(contents_count(src))
		if(prob(40 + contents_count(src) * 5))
			var/obj/item/I = pick(contents)
			I.forceMove(loc)
			if(prob(25))
				step_rand(I)
			to_chat(user, span_notice("You pull \a [I] out of [src] at random."))
			return
	to_chat(user, span_notice("You find nothing in [src]."))

/obj/structure/filingcabinet/tgui_state(mob/user)
	return GLOB.tgui_physical_state

/obj/structure/filingcabinet/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FileCabinet", name)
		ui.set_autoupdate(FALSE)
		ui.open()

/obj/structure/filingcabinet/tgui_data(mob/user)
	var/list/data = list()

	data["cabinet_name"] = "[name]"
	data["contents"] = list()
	data["contents_ref"] = list()
	FOR_REAL_CONTENTS(var/obj/item/content, src)
		data["contents"] += "[content]"
		data["contents_ref"] += "[REF(content)]"

	return data

/obj/structure/filingcabinet/tgui_act(action, params)
	. = ..()
	if(.)
		return

	switch(action)
		if("remove_object")
			var/obj/item/content = locate_within(src, params["ref"])
			if(istype(content) && (content.loc == src) && usr.Adjacent(src))
				usr.put_in_hands(content)
				open_animation()
				SStgui.update_uis(src)

/obj/structure/filingcabinet/proc/open_animation()
	flick("[initial(icon_state)]-open",src)
	playsound(src, 'sound/bureaucracy/filingcabinet.ogg', 50, 1)
	om_after(src, 2 SECONDS, TYPE_PROC_REF(/atom, set_icon_state), initial(icon_state))

/*
 * Security Record Cabinets
 */
/obj/structure/filingcabinet/security
	var/virgin = 1

/obj/structure/filingcabinet/security/proc/populate()
	if(virgin)
		for(var/datum/data/record/G in GLOB.data_core.general)
			var/datum/data/record/S
			for(var/datum/data/record/R in GLOB.data_core.security)
				if((R.fields["name"] == G.fields["name"] || R.fields["id"] == G.fields["id"]))
					S = R
					break
			var/obj/item/paper/P = new /obj/item/paper(src)
			P.info = "<CENTER>" + span_bold("Security Record") + "</CENTER><BR>"
			P.info += "Name: [G.fields["name"]] ID: [G.fields["id"]]<BR>\nSex: [G.fields["sex"]]<BR>\nAge: [G.fields["age"]]<BR>\nFingerprint: [G.fields["fingerprint"]]<BR>\nPhysical Status: [G.fields["p_stat"]]<BR>\nMental Status: [G.fields["m_stat"]]<BR>"
			P.info += "<BR>\n<CENTER>" + span_bold("Security Data") + "</CENTER><BR>\nCriminal Status: [S?.fields["criminal"]]<BR>\n<BR>\nMinor Crimes: [S?.fields["mi_crim"]]<BR>\nDetails: [S?.fields["mi_crim_d"]]<BR>\n<BR>\nMajor Crimes: [S?.fields["ma_crim"]]<BR>\nDetails: [S?.fields["ma_crim_d"]]<BR>\n<BR>\nImportant Notes:<BR>\n\t[S?.fields["notes"]]<BR>\n<BR>\n<CENTER>" + span_bold("Comments/Log") + "</CENTER><BR>"
			var/counter = 1
			while(S?.fields["com_[counter]"])
				P.info += "[S?.fields["com_[counter]"]]<BR>"
				counter++
			P.info += "</TT>"
			P.name = "Security Record ([G.fields["name"]])"
			virgin = 0	//tabbing here is correct- it's possible for people to try and use it
						//before the records have been generated, so we do this inside the loop.

EXTEND_INTERACTIONS(/obj/structure/filingcabinet/security, \
	INTERACT_HAND(null, PROC_REF(security_interaction_hand)), \
	INTERACT_TK(null, PROC_REF(security_interaction_tk)), \
)

/// Old attack_hand.
/obj/structure/filingcabinet/security/proc/security_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	populate()
	return FALSE

/// Old attack_tk: fill the records first, then the base cabinet's telekinetic rummage.
/obj/structure/filingcabinet/security/proc/security_interaction_tk(mob/user, obj/item/held, datum/interaction/interaction)
	populate()
	return FALSE

/*
 * Medical Record Cabinets
 */
/obj/structure/filingcabinet/medical
	var/virgin = 1

/obj/structure/filingcabinet/medical/proc/populate()
	if(virgin)
		for(var/datum/data/record/G in GLOB.data_core.general)
			var/datum/data/record/M
			for(var/datum/data/record/R in GLOB.data_core.medical)
				if((R.fields["name"] == G.fields["name"] || R.fields["id"] == G.fields["id"]))
					M = R
					break
			if(M)
				var/obj/item/paper/P = new /obj/item/paper(src)
				P.info = "<CENTER>" + span_bold("Medical Record") + "</CENTER><BR>"
				P.info += "Name: [G.fields["name"]] ID: [G.fields["id"]]<BR>\nSex: [G.fields["sex"]]<BR>\nAge: [G.fields["age"]]<BR>\nFingerprint: [G.fields["fingerprint"]]<BR>\nPhysical Status: [G.fields["p_stat"]]<BR>\nMental Status: [G.fields["m_stat"]]<BR>"

				P.info += "<BR>\n<CENTER>" + span_bold("Medical Data") + "</CENTER><BR>\nBlood Type: [M.fields["b_type"]]<BR>\nDNA: [M.fields["b_dna"]]<BR>\n<BR>\nMinor Disabilities: [M.fields["mi_dis"]]<BR>\nDetails: [M.fields["mi_dis_d"]]<BR>\n<BR>\nMajor Disabilities: [M.fields["ma_dis"]]<BR>\nDetails: [M.fields["ma_dis_d"]]<BR>\n<BR>\nAllergies: [M.fields["alg"]]<BR>\nDetails: [M.fields["alg_d"]]<BR>\n<BR>\nCurrent Diseases: [M.fields["cdi"]] (per disease info placed in log/comment section)<BR>\nDetails: [M.fields["cdi_d"]]<BR>\n<BR>\nImportant Notes:<BR>\n\t[M.fields["notes"]]<BR>\n<BR>\n<CENTER>" + span_bold("Comments/Log") + "</CENTER><BR>"
				var/counter = 1
				while(M.fields["com_[counter]"])
					P.info += "[M.fields["com_[counter]"]]<BR>"
					counter++
				P.info += "</TT>"
				P.name = "Medical Record ([G.fields["name"]])"
			virgin = 0	//tabbing here is correct- it's possible for people to try and use it
						//before the records have been generated, so we do this inside the loop.

EXTEND_INTERACTIONS(/obj/structure/filingcabinet/medical, \
	INTERACT_HAND(null, PROC_REF(medical_interaction_hand)), \
	INTERACT_TK(null, PROC_REF(medical_interaction_tk)), \
)

/// Old attack_hand.
/obj/structure/filingcabinet/medical/proc/medical_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	populate()
	return FALSE

/// Old attack_tk: fill the records first, then the base cabinet's telekinetic rummage.
/obj/structure/filingcabinet/medical/proc/medical_interaction_tk(mob/user, obj/item/held, datum/interaction/interaction)
	populate()
	return FALSE
