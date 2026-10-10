
//moved these here from code/defines/obj/weapon.dm
//please preference put stuff where it's easy to find - C

/obj/item/autopsy_scanner
	name = "biopsy scanner"
	desc = "Extracts information on wounds."
	icon = 'icons/obj/autopsy_scanner.dmi'
	icon_state = ""
	item_state = "autopsy_scanner"
	w_class = ITEMSIZE_SMALL
	var/list/datum/autopsy_data_scanner/wdata
	var/list/datum/autopsy_data_scanner/chemtraces
	var/target_name = null
	var/timeofdeath = null
	drop_sound = SFX_ITEMS_DROP_DEVICE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE

CAPABILITIES(/obj/item/autopsy_scanner)
	owns_many(nameof(chemtraces))
	owns_many(nameof(wdata))
	op("print_data_effect", menu(), label("Print Data"), needs(req_adjacent(), req_capable(), req_bool(PROC_REF(can_print_data_holds), because = PROC_REF(can_print_data_refusal))), then(PROC_REF(print_data_effect)))

/datum/autopsy_data_scanner
	var/weapon = null // this is the DEFINITE weapon type that was used
	var/list/organs_scanned	// this maps a number of scanned organs to
										// the wounds to those organs with this data's weapon type
	var/organ_names = ""

CAPABILITIES(/datum/autopsy_data_scanner)
	owns_many(nameof(organs_scanned))

/datum/autopsy_data
	var/weapon = null
	var/pretend_weapon = null
	var/damage = 0
	var/hits = 0
	EXPIRY_DECLARE(time_inflicted)

/datum/autopsy_data/proc/copy()
	var/datum/autopsy_data/W = new()
	W.weapon = weapon
	W.pretend_weapon = pretend_weapon
	W.damage = damage
	W.hits = hits
	W.time_inflicted = time_inflicted
	return W

/obj/item/autopsy_scanner/proc/add_data(obj/item/organ/external/O)
	if(!LAZYLEN(O.autopsy_data) && !LAZYLEN(O.trace_chemicals)) return

	for(var/V in O.autopsy_data)
		var/datum/autopsy_data/W = O.autopsy_data[V]

		if(!W.pretend_weapon)
			W.pretend_weapon = W.weapon

		var/datum/autopsy_data_scanner/D = LAZYACCESS(wdata, V)
		if(!D)
			D = new()
			D.weapon = W.weapon
			rel_add(src, nameof(wdata), D, V)

		if(!LAZYACCESS(D.organs_scanned, O.name))
			if(D.organ_names == "")
				D.organ_names = O.name
			else
				D.organ_names += ", [O.name]"

		rel_add(D, nameof(D.organs_scanned), W.copy(), O.name)

	for(var/V in O.trace_chemicals)
		if(O.trace_chemicals[V] > 0 && !LAZYFIND(chemtraces, V))
			rel_add(src, nameof(chemtraces), V)

/// Requirement: only a conscious human can print the data.
/obj/item/autopsy_scanner/proc/can_print_data(mob/user, atom/target, obj/item/held)
	if(user.stat || !ishuman(user))
		return "no"
	return TRUE

/// Requirement (was REQ_* can_print_data): the legacy check answers TRUE to pass.
/obj/item/autopsy_scanner/proc/can_print_data_holds(datum/act/op/A)
	var/answer = can_print_data(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_print_data_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/autopsy_scanner/proc/can_print_data_refusal(datum/act/op/A)
	var/answer = can_print_data(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/item/autopsy_scanner/proc/print_data_effect(datum/act/op/A)
	var/mob/user = A.actor
	var/scan_data = ""

	if(timeofdeath)
		scan_data += span_bold("Time of death:") + " [worldtime2stationtime(timeofdeath)]<br><br>"

	var/n = 1
	for(var/wdata_idx in wdata)
		var/datum/autopsy_data_scanner/D = LAZYACCESS(wdata, wdata_idx)
		var/total_hits = 0
		var/total_score = 0
		var/list/weapon_chances = list() // maps weapon names to a score
		var/age = 0

		for(var/wound_idx in D.organs_scanned)
			var/datum/autopsy_data/W = LAZYACCESS(D.organs_scanned, wound_idx)
			total_hits += W.hits

			var/wname = W.pretend_weapon

			if(wname in weapon_chances) weapon_chances[wname] += W.damage
			else weapon_chances[wname] = max(W.damage, 1)
			total_score+=W.damage


			var/wound_age = W.time_inflicted
			age = max(age, wound_age)

		var/damage_desc

		var/damaging_weapon = (total_score != 0)

		// total score happens to be the total damage
		switch(total_score)
			if(0)
				damage_desc = "Unknown"
			if(1 to 5)
				damage_desc = span_green("negligible")
			if(5 to 15)
				damage_desc = span_green("light")
			if(15 to 30)
				damage_desc = span_orange("moderate")
			if(30 to 1000)
				damage_desc = span_red("severe")

		if(!total_score) total_score = length(D.organs_scanned)

		scan_data += span_bold("Weapon #[n]") + "<br>"
		if(damaging_weapon)
			scan_data += "Severity: [damage_desc]<br>"
			scan_data += "Hits by weapon: [total_hits]<br>"
		scan_data += "Approximate time of wound infliction: [worldtime2stationtime(age)]<br>"
		scan_data += "Affected limbs: [D.organ_names]<br>"
		scan_data += "Possible weapons:<br>"
		for(var/weapon_name in weapon_chances)
			scan_data += "\t[100*weapon_chances[weapon_name]/total_score]% [weapon_name]<br>"

		scan_data += "<br>"

		n++

	if(length(chemtraces))
		scan_data += span_bold("Trace Chemicals: ") + "<br>"
		for(var/chemID in chemtraces)
			scan_data += chemID
			scan_data += "<br>"

	for(var/mob/O in viewers(user))
		O.show_message(span_notice("\The [src] rattles and prints out a sheet of paper."), 1)

	after(src, 1 SECOND, PROC_REF(print_report), with = list(user, scan_data))

/obj/item/autopsy_scanner/proc/print_report(mob/usr_mob, scan_data)
	if(!usr_mob)
		return
	var/obj/item/paper/P = new(usr_mob.loc)
	P.name = "Autopsy Data ([target_name])"
	P.set_info("<tt>[scan_data]</tt>")
	P.icon_state = "paper_words"

	if(istype(usr_mob, /mob/living/carbon))
		usr_mob.put_in_hands(P)

/obj/item/autopsy_scanner/use_on_patient(mob/living/carbon/human/M, mob/living/user, stance = I_HURT)
	if(!istype(M))
		return 0

	if (stance == I_HELP)
		return ..()

	if(target_name != M.name)
		target_name = M.name
		rel_clear(src, nameof(wdata))
		rel_set(src, nameof(chemtraces), list())
		src.timeofdeath = null
		to_chat(user, span_notice("A new patient has been registered. Purging data for previous patient."))

	src.timeofdeath = M.timeofdeath

	var/obj/item/organ/external/S = M.get_organ(user.zone_sel.selecting)
	if(!S)
		to_chat(user, span_warning("You can't scan this body part."))
		return
	if(!S.open)
		to_chat(user, span_warning("You have to cut [S] open first!"))
		return
	act_message(user, M, others = span_infoplain(span_bold("%U%") + " scans the wounds on %T%'s [S.name] with [src]"))

	src.add_data(S)

	return 1


/// Old object verbs.
