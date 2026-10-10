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


CAPABILITIES(/obj/structure/filingcabinet)
	climb()
	op("interaction_hand", hand(), ungated(), needs(req(PROC_REF(has_files), because = MSG(filingcabinet/empty))), then(PROC_REF(interaction_hand)))
	op("interaction_item", item(/obj/item), then(PROC_REF(interaction_item)))
	op("interaction_tk", tk(), then(PROC_REF(interaction_tk)))
	interface("FileCabinet", state = nameof(GLOB.tgui_physical_state))
	without("ui_open")
	op("remove_object", ui_act("remove_object", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_remove_object)))

// ALLOW(init/INSTANCE_STATE): gathers the papers the map placed on its tile
/obj/structure/filingcabinet/Initialize(mapload)
	for(var/obj/item/I in contents_of(loc))
		if(istype(I, /obj/item/paper) || istype(I, /obj/item/folder) || istype(I, /obj/item/photo) || istype(I, /obj/item/paper_bundle))
			I.forceMove(src)
	. = ..()

/// Old attackby.
/obj/structure/filingcabinet/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/P = A.held
	if(istype(P, /obj/item/paper) || istype(P, /obj/item/folder) || istype(P, /obj/item/photo) || istype(P, /obj/item/paper_bundle))
		if(!own_bring_in(src, nameof(contents), P, null, user, TRUE, null, FALSE))
			return OP_PASS
		to_chat(user, span_notice("You put [P] in [src]."))
		open_animation()
		SStgui.update_uis(src)
	else
		to_chat(user, span_notice("You can't put [P] in [src]!"))
	return OP_PASS

/obj/structure/filingcabinet/wrench_act(mob/user, obj/item/tool)
	playsound(src, tool.usesound, 50, TRUE)
	set_anchored(!anchored)
	to_chat(user, span_notice("You [anchored ? "wrench" : "unwrench"] \the [src]."))
	return ITEM_INTERACT_SUCCESS

/obj/structure/filingcabinet/screwdriver_act(mob/user, obj/item/tool)
	use_tool(user, tool, src, delay = 1 SECOND, volume = 50, start_self = "You begin taking the [name] apart.", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user, tool))
	return ITEM_INTERACT_SUCCESS

/obj/structure/filingcabinet/proc/screwdriver_act_tool_done(mob/user, obj/item/tool)
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_notice("You take the [name] apart."))
	new /obj/item/stack/material/steel(loc, 4)
	for(var/obj/item/I in contents)
		I.forceMove(loc)
	destroyed(src, user, "deconstructed")
	return ITEM_INTERACT_SUCCESS

MSG_DEF_SELF(filingcabinet/empty, "It's empty.")

/// Requirement: the cabinet holds something to browse.
/obj/structure/filingcabinet/proc/has_files(datum/act/op/A)
	return (length(contents) > 0) ? null : MSG(filingcabinet/empty) // ALLOW(reads, spatial): what the cabinet holds is read when it is opened, never cached; a plain count of its own contents

/// Old attack_hand.
/obj/structure/filingcabinet/proc/interaction_hand(datum/act/op/A)
	tgui_interact(A.actor)
	return TRUE

/// Old attack_tk: rummage in an anchored cabinet at range.
/obj/structure/filingcabinet/proc/interaction_tk(datum/act/op/A)
	if(!anchored)
		return OP_DECLINE
	attack_self_tk(A.actor)
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

/// /obj/structure/filingcabinet's window data.
/obj/structure/filingcabinet/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["cabinet_name"] = "[name]"
	data["contents"] = list()
	data["contents_ref"] = list()
	FOR_REAL_CONTENTS(var/obj/item/content, src)
		data["contents"] += "[content]"
		data["contents_ref"] += "[REF(content)]"

	return data

/obj/structure/filingcabinet/proc/ui_act_remove_object(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!isnull(ref) && !(ref in contents_of(src)))
		return FALSE
	var/obj/item/content = ref
	if(istype(content) && (content.loc == src) && user.Adjacent(src))
		user.put_in_hands(content)
		open_animation()
		SStgui.update_uis(src)

/obj/structure/filingcabinet/proc/open_animation()
	flick("[initial(icon_state)]-open",src)
	play_sfx(src, SFX_BUREAUCRACY_FILINGCABINET)
	after(src, 2 SECONDS, TYPE_PROC_REF(/atom, set_icon_state), with = list(initial(icon_state)))

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
			P.set_info("<CENTER>" + span_bold("Security Record") + "</CENTER><BR>")
			P.set_info(P.info + ("Name: [G.fields["name"]] ID: [G.fields["id"]]<BR>\nSex: [G.fields["sex"]]<BR>\nAge: [G.fields["age"]]<BR>\nFingerprint: [G.fields["fingerprint"]]<BR>\nPhysical Status: [G.fields["p_stat"]]<BR>\nMental Status: [G.fields["m_stat"]]<BR>"))
			P.set_info(P.info + ("<BR>\n<CENTER>" + span_bold("Security Data") + "</CENTER><BR>\nCriminal Status: [S?.fields["criminal"]]<BR>\n<BR>\nMinor Crimes: [S?.fields["mi_crim"]]<BR>\nDetails: [S?.fields["mi_crim_d"]]<BR>\n<BR>\nMajor Crimes: [S?.fields["ma_crim"]]<BR>\nDetails: [S?.fields["ma_crim_d"]]<BR>\n<BR>\nImportant Notes:<BR>\n\t[S?.fields["notes"]]<BR>\n<BR>\n<CENTER>" + span_bold("Comments/Log") + "</CENTER><BR>"))
			var/counter = 1
			while(S?.fields["com_[counter]"])
				P.set_info(P.info + ("[S?.fields["com_[counter]"]]<BR>"))
				counter++
			P.set_info(P.info + ("</TT>"))
			P.name = "Security Record ([G.fields["name"]])"
			virgin = 0	//tabbing here is correct- it's possible for people to try and use it
						//before the records have been generated, so we do this inside the loop.

// The records are written the first time the cabinet is opened, then the cabinet's own hand and telekinetic use follow.
CAPABILITIES(/obj/structure/filingcabinet/security)
	op("interaction_hand", hand(), ungated(), then(PROC_REF(security_interaction_hand)))
	op("interaction_tk", tk(), then(PROC_REF(security_interaction_tk)))

/// Old attack_hand: fill the records, then the cabinet's own use (its "It's empty." stays the base requirement's, asked of the filled cabinet).
/obj/structure/filingcabinet/security/proc/security_interaction_hand(datum/act/op/A)
	populate()
	if(!isnull(has_files(A)))
		to_chat(A.actor, span_warning("It's empty."))
		return OP_OK
	return interaction_hand(A)

/// Old attack_tk: fill the records first, then the base cabinet's telekinetic rummage.
/obj/structure/filingcabinet/security/proc/security_interaction_tk(datum/act/op/A)
	populate()
	return interaction_tk(A)

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
				P.set_info("<CENTER>" + span_bold("Medical Record") + "</CENTER><BR>")
				P.set_info(P.info + ("Name: [G.fields["name"]] ID: [G.fields["id"]]<BR>\nSex: [G.fields["sex"]]<BR>\nAge: [G.fields["age"]]<BR>\nFingerprint: [G.fields["fingerprint"]]<BR>\nPhysical Status: [G.fields["p_stat"]]<BR>\nMental Status: [G.fields["m_stat"]]<BR>"))

				P.set_info(P.info + ("<BR>\n<CENTER>" + span_bold("Medical Data") + "</CENTER><BR>\nBlood Type: [M.fields["b_type"]]<BR>\nDNA: [M.fields["b_dna"]]<BR>\n<BR>\nMinor Disabilities: [M.fields["mi_dis"]]<BR>\nDetails: [M.fields["mi_dis_d"]]<BR>\n<BR>\nMajor Disabilities: [M.fields["ma_dis"]]<BR>\nDetails: [M.fields["ma_dis_d"]]<BR>\n<BR>\nAllergies: [M.fields["alg"]]<BR>\nDetails: [M.fields["alg_d"]]<BR>\n<BR>\nCurrent Diseases: [M.fields["cdi"]] (per disease info placed in log/comment section)<BR>\nDetails: [M.fields["cdi_d"]]<BR>\n<BR>\nImportant Notes:<BR>\n\t[M.fields["notes"]]<BR>\n<BR>\n<CENTER>" + span_bold("Comments/Log") + "</CENTER><BR>"))
				var/counter = 1
				while(M.fields["com_[counter]"])
					P.set_info(P.info + ("[M.fields["com_[counter]"]]<BR>"))
					counter++
				P.set_info(P.info + ("</TT>"))
				P.name = "Medical Record ([G.fields["name"]])"
			virgin = 0	//tabbing here is correct- it's possible for people to try and use it
						//before the records have been generated, so we do this inside the loop.

// The records are written the first time the cabinet is opened, then the cabinet's own hand and telekinetic use follow.
CAPABILITIES(/obj/structure/filingcabinet/medical)
	op("interaction_hand", hand(), ungated(), then(PROC_REF(medical_interaction_hand)))
	op("interaction_tk", tk(), then(PROC_REF(medical_interaction_tk)))

/// Old attack_hand: fill the records, then the cabinet's own use (its "It's empty." stays the base requirement's, asked of the filled cabinet).
/obj/structure/filingcabinet/medical/proc/medical_interaction_hand(datum/act/op/A)
	populate()
	if(!isnull(has_files(A)))
		to_chat(A.actor, span_warning("It's empty."))
		return OP_OK
	return interaction_hand(A)

/// Old attack_tk: fill the records first, then the base cabinet's telekinetic rummage.
/obj/structure/filingcabinet/medical/proc/medical_interaction_tk(datum/act/op/A)
	populate()
	return interaction_tk(A)
