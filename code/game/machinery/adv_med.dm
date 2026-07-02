// Pretty much everything here is stolen from the dna scanner FYI

/obj/machinery/bodyscanner
	var/mob/living/carbon/human/occupant
	var/locked
	name = "Body Scanner"
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "body_scanner_0"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	flags = REMOTEVIEW_ON_ENTER
	circuit = /obj/item/circuitboard/body_scanner
	use_power = USE_POWER_IDLE
	idle_power_usage = 60
	active_power_usage = 10000	//10 kW. It's a big all-body scanner.
	light_color = "#00FF00"
	var/obj/machinery/body_scanconsole/console
	var/printing_text = null
	var/scan_level = SCANNABLE_DIFFICULT //By default, we start with level 2 scanning level.

/obj/machinery/bodyscanner/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/bodyscanner/RefreshParts()
	scan_level = SCANNABLE_DIFFICULT
	for(var/obj/item/stock_parts/scanning_module/P in component_parts)
		scan_level += max(0, (P.rating - 2)) //We require T3 parts or higher to actually increase our scan level.

/obj/machinery/bodyscanner/Destroy()
	if(console)
		console.scanner = null
	return ..()

/obj/machinery/bodyscanner/power_change()
	..()
	if(!(stat & (BROKEN|NOPOWER)))
		set_light(2)
	else
		set_light(0)

/obj/machinery/bodyscanner/attackby(obj/item/G, user as mob)
	if(istype(G, /obj/item/grab))
		var/obj/item/grab/H = G
		if(panel_open)
			to_chat(user, span_notice("Close the maintenance panel first."))
			return
		if(!ismob(H.affecting))
			return
		if(!ishuman(H.affecting))
			to_chat(user, span_warning("\The [src] is not designed for that organism!"))
			return
		if(occupant)
			to_chat(user, span_notice("\The [src] is already occupied!"))
			return
		if(H.affecting.has_buckled_mobs())
			to_chat(user, span_warning("\The [H.affecting] has other entities attached to it. Remove them first."))
			return
		var/mob/M = H.affecting
		if(M.abiotic())
			to_chat(user, span_notice("Subject cannot have abiotic items on."))
			return
		M.forceMove(src)
		occupant = M
		update_icon()
		playsound(src, 'sound/machines/medbayscanner1.ogg', 50) // Beepboop you're being scanned. <3
		add_fingerprint(user)
		qdel(G)
		SStgui.update_uis(src)
	if(!occupant)
		if(default_deconstruction_screwdriver(user, G))
			return
		if(default_deconstruction_crowbar(user, G))
			return

/obj/machinery/bodyscanner/MouseDrop_T(mob/living/carbon/human/O, mob/user as mob)
	if(!istype(O))
		return 0 //not a mob
	if(user.incapacitated())
		return 0 //user shouldn't be doing things
	if(O.anchored)
		return 0 //mob is anchored???
	if(get_dist(user, src) > 1 || get_dist(user, O) > 1)
		return 0 //doesn't use adjacent() to allow for non-GLOB.cardinal (fuck my life)
	if(!ishuman(user) && !isrobot(user))
		return 0 //not a borg or human
	if(panel_open)
		to_chat(user, span_notice("Close the maintenance panel first."))
		return 0 //panel open
	if(occupant)
		to_chat(user, span_notice("\The [src] is already occupied."))
		return 0 //occupied

	if(O.buckled)
		return 0
	if(O.abiotic())
		to_chat(user, span_notice("Subject cannot have abiotic items on."))
		return 0
	if(O.has_buckled_mobs())
		to_chat(user, span_warning("\The [O] has other entities attached to it. Remove them first."))
		return

	if(O == user)
		visible_message("[user] climbs into \the [src].")
	else
		visible_message("[user] puts [O] into the body scanner.")

	O.forceMove(src)
	occupant = O
	update_icon()
	playsound(src, 'sound/machines/medbayscanner1.ogg', 50) // Beepboop you're being scanned. <3
	add_fingerprint(user)
	SStgui.update_uis(src)

/obj/machinery/bodyscanner/relaymove(mob/user as mob)
	if(user.incapacitated())
		return 0 //maybe they should be able to get out with cuffs, but whatever
	go_out()

/obj/machinery/bodyscanner/verb/eject()
	set src in oview(1)
	set category = "Object"
	set name = "Eject Body Scanner"

	if(usr.incapacitated())
		return
	go_out()
	add_fingerprint(usr)

/obj/machinery/bodyscanner/proc/go_out()
	if ((!(occupant) || src.locked))
		return
	occupant.forceMove(get_turf(src))
	occupant = null
	update_icon() // icon_state = "body_scanner_1" // Health display for consoles with light and such.
	SStgui.update_uis(src)
	return

/obj/machinery/bodyscanner/ex_act(severity)
	switch(severity)
		if(1.0)
			for(var/atom/movable/A as mob|obj in src)
				A.forceMove(get_turf(src))
				ex_act(severity)
				//Foreach goto(35)
			//SN src = null
			qdel(src)
			return
		if(2.0)
			if (prob(50))
				for(var/atom/movable/A as mob|obj in src)
					A.forceMove(get_turf(src))
					ex_act(severity)
					//Foreach goto(108)
				//SN src = null
				qdel(src)
				return
		if(3.0)
			if (prob(25))
				for(var/atom/movable/A as mob|obj in src)
					A.forceMove(get_turf(src))
					ex_act(severity)
					//Foreach goto(181)
				//SN src = null
				qdel(src)
				return
	return

/obj/machinery/bodyscanner/tgui_host(mob/user)
	if(user == occupant)
		return src
	return console ? console : src

/obj/machinery/bodyscanner/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "BodyScanner", "Body Scanner")
		ui.open()

/obj/machinery/bodyscanner/tgui_data(mob/user)
	// qualitative scanner output. The old block dumped exact
	// damage numbers and the full medical_issue catalog; the new builder
	// returns qualitative bands plus DQ scanner-audience findings.
	// Implementation lives in code/modules/medical/bodyscanner/.
	return dq_build_tgui_data()

/obj/machinery/bodyscanner/tgui_act(action, params)
	if(..())
		return TRUE

	. = TRUE
	switch(action)
		if("ejectify")
			eject()
		if("print_p")
			var/atom/target = console ? console : src
			visible_message(span_notice("[target] rattles and prints out a sheet of paper."))
			playsound(src, 'sound/machines/printer.ogg', 50, 1)
			var/obj/item/paper/P = new /obj/item/paper(get_turf(target))
			var/name = occupant ? occupant.name : "Unknown"
			P.info = "<CENTER>" + span_bold("Body Scan - [name]") + "</CENTER><BR>"
			P.info += span_bold("Time of scan:") + " [stationtime2text()]<br><br>"
			P.info += "[generate_printing_text()]"
			P.info += "<br><br>" + span_bold("Notes:") + "<br>"
			P.name = "Body Scan - [name] ([stationtime2text()])"
		else
			return FALSE

/obj/machinery/bodyscanner/proc/generate_printing_text()
	var/dat = ""

	dat = span_blue(span_bold("Occupant Statistics:")) + "<br>" //Blah obvious
	if(istype(occupant)) //is there REALLY someone in there?
		var/has_withdrawl = ""
		if(ishuman(occupant))
			var/mob/living/carbon/human/H = occupant
			var/speciestext = H.species.name
			if(H.custom_species)
				if(H.species.name == SPECIES_CUSTOM)
					// Fully custom species
					speciestext = "[H.custom_species]"
					dat += span_blue("Sapient Species: [speciestext]") + "<BR>"
				else
					speciestext = "[H.custom_species] \[Similar biology to [H.species.name]\]"
					dat += span_blue("Sapient Species: [speciestext]") + "<BR>"
			for(var/addic in H.get_all_addictions())
				if(H.get_addiction_to_reagent(addic) > 0 && H.get_addiction_to_reagent(addic) < 80)
					var/datum/reagent/R = SSchemistry.chemical_reagents[addic]
					has_withdrawl = R.name
					break
		var/t1
		switch(occupant.stat) // obvious, see what their status is
			if(0)
				t1 = "Conscious"
			if(1)
				t1 = "Unconscious"
			else
				t1 = "*dead*"
		var/health_text = "\tHealth %: [(occupant.health / occupant.getMaxHealth())*100], ([t1])"
		//var/fake_oxy = max(occupant.getOxyLoss(), (300 - (occupant.getFireLoss() + occupant.getBruteLoss())))
		var/fake_death = FALSE
		if(occupant.status_flags & FAKEDEATH)
			t1 = "*dead*"
			health_text = "\tHealth %: -100, ([t1])"
			fake_death = TRUE
			dat += (span_red(health_text))
			dat += "<br>"
		else
			dat += (occupant.health > (occupant.getMaxHealth() / 2) ? span_blue(health_text) : span_red(health_text))
			dat += "<br>"

		if(occupant.IsInfected())
			for(var/datum/disease/D in occupant.GetViruses())
				if(D.visibility_flags & HIDDEN_SCANNER)
					continue
				else
					dat += span_red("Disease detected in blood stream.") + "<BR>"

		var/damage_string = null
		damage_string = "\t-Brute Damage %: [occupant.getBruteLoss()]"
		dat += (occupant.getBruteLoss() < 60 ? span_blue(damage_string) : span_red(damage_string)) + "<br>"
		damage_string = "\t-Respiratory Damage %: [occupant.getOxyLoss()]"
		/* //Alternative oxygen based fakedeath
		if(fake_death)
			damage_string = "\t-Respiratory Damage %: [fake_oxy]"
			dat += (span_red(damage_string)) + "<br>"
		else*/
		dat += (occupant.getOxyLoss() < 60 ? span_blue(damage_string) : span_red(damage_string)) + "<br>"

		if(fake_death)
			damage_string = "\t-Toxin Content %: 0"
			dat += span_blue(damage_string) + "<br>"
		else
			damage_string = "\t-Toxin Content %: [occupant.getToxLoss()]"
			dat += (occupant.getToxLoss() < 60 ? span_blue(damage_string) : span_red(damage_string)) + "<br>"

		damage_string = "\t-Burn Severity %: [occupant.getFireLoss()]"
		dat += (occupant.getFireLoss() < 60 ? span_blue(damage_string) : span_red(damage_string)) + "<br>"

		damage_string = "\tRadiation Level %: [occupant.radiation]"
		dat += (occupant.radiation < 10 ? span_blue(damage_string) : span_red(damage_string)) + "<br>"

		damage_string = "\tGenetic Tissue Damage %: [occupant.getCloneLoss()]"
		dat += (occupant.getCloneLoss() < 1 ? span_blue(damage_string) : span_red(damage_string)) + "<br>"

		if(fake_death)
			damage_string = "\tApprox. Brain Damage %: 100"
			dat += (span_red(damage_string)) + "<br>"
		else
			damage_string = "\tApprox. Brain Damage %: [occupant.getBrainLoss()]"
			dat += (occupant.getBrainLoss() < 1 ? span_blue(damage_string) : span_red(damage_string)) + "<br>"

		var/occupant_paralysis = occupant.paralysis
		var/paralysis_duration = round(occupant.paralysis * 0.25)
		if(fake_death)
			occupant_paralysis = 0
			paralysis_duration = 0

		dat += "Paralysis Summary %: [occupant_paralysis] ([paralysis_duration] seconds left!)<br>"
		dat += "Body Temperature: [occupant.bodytemperature-T0C]&deg;C ([occupant.bodytemperature*1.8-459.67]&deg;F)<br>"

		if(ishuman(occupant))
			var/mob/living/carbon/human/H = occupant
			var/list/allergen_list = assembly_allergy_list(H.species.allergens, H.species.medallergens)
			if(length(allergen_list))
				dat += "Allergens: [english_list(allergen_list)]<BR>"

		dat += "<hr>"

		if(occupant.has_brain_worms())
			dat += "Large growth detected in frontal lobe, possibly cancerous. Surgical removal is recommended.<br>"

		if(occupant.vessel)
			var/blood_volume = round(occupant.vessel.get_reagent_amount(REAGENT_ID_BLOOD))
			var/blood_max = occupant.species.blood_volume
			var/blood_percent =  blood_volume / blood_max
			blood_percent *= 100

			damage_string = "\tBlood Level %: [blood_percent] ([blood_volume] units)"
			dat += (blood_volume > 448 ? span_blue(damage_string) : span_red(damage_string)) + "<br>"

		if(occupant.reagents)
			for(var/datum/reagent/R in occupant.reagents.reagent_list)
				if(!R.scannable && !(scan_level >= 8)) //Requires minimum of 2 T3 and 1 T2 scanning module, or 2 T4 scanning modules.
					continue
				dat += "Reagent: [R.name], Amount: [R.volume]<br>"

		if(occupant.ingested)
			for(var/datum/reagent/R in occupant.ingested.reagent_list)
				if(!R.scannable && !(scan_level >= 8)) //Requires minimum of 2 T3 and 1 T2 scanning module, or 2 T4 scanning modules.
					continue
				dat += "Stomach: [R.name], Amount: [R.volume]<br>"

		dat += "<hr><table border='1'>"
		dat += "<tr>"
		dat += "<th>Organ</th>"
		dat += "<th>Burn Damage</th>"
		dat += "<th>Brute Damage</th>"
		dat += "<th>Other Wounds</th>"
		dat += "</tr>"

		for(var/obj/item/organ/external/e in occupant.organs)
			dat += "<tr>"
			var/AN = ""
			var/open = ""
			var/infected = ""
			var/robot = ""
			var/imp = ""
			var/bled = ""
			var/splint = ""
			var/internal_bleeding = ""
			var/lung_ruptured = ""
			var/o_dead = ""
			var/mi = ""
			for(var/datum/wound/W in e.wounds) if(W.internal)
				internal_bleeding = "<br>Internal bleeding"
				break
			if(istype(e, /obj/item/organ/external/chest) && occupant.is_lung_ruptured())
				lung_ruptured = "Lung ruptured:"
			if(e.splinted)
				splint = "Splinted:"
			if(e.status & ORGAN_BLEEDING)
				bled = "Bleeding:"
			if(e.status & ORGAN_BROKEN)
				AN = "[e.broken_description]:"
			if(e.robotic >= ORGAN_ROBOT)
				robot = "Prosthetic:"
			if(e.status & ORGAN_DEAD)
				o_dead = "Necrotic:"
			if(e.open)
				open = "Open:"
			switch (e.germ_level)
				if (INFECTION_LEVEL_ONE to INFECTION_LEVEL_ONE + 200)
					infected = "Mild Infection:"
				if (INFECTION_LEVEL_ONE + 200 to INFECTION_LEVEL_ONE + 300)
					infected = "Mild Infection+:"
				if (INFECTION_LEVEL_ONE + 300 to INFECTION_LEVEL_ONE + 400)
					infected = "Mild Infection++:"
				if (INFECTION_LEVEL_TWO to INFECTION_LEVEL_TWO + 200)
					infected = "Acute Infection:"
				if (INFECTION_LEVEL_TWO + 200 to INFECTION_LEVEL_TWO + 300)
					infected = "Acute Infection+:"
				if (INFECTION_LEVEL_TWO + 300 to INFECTION_LEVEL_THREE - 50)
					infected = "Acute Infection++:"
				if (INFECTION_LEVEL_THREE -49 to INFINITY)
					infected = "Gangrene Detected:"

			var/unknown_body = 0
			for(var/obj/item/implant/I as anything in e.implants)
				var/obj/item/nif/N = I // NIFs
				if(istype(I) && I.known_implant)
					imp += "[I] implanted:"
				else if(istype(N) && N.known_implant) // NIFs
					imp += "[N] implanted:"
				else
					unknown_body++

			for(var/datum/medical_issue/MI in e.medical_issues)
				mi += "[MI.name] detected:"

			if(unknown_body)
				imp += "Unknown body present:"
			if(!AN && !open && !infected && !imp && !mi)
				AN = "None:"
			if(!(e.status & ORGAN_DESTROYED))
				dat += "<td>[e.name]</td><td>[e.burn_dam]</td><td>[e.brute_dam]</td><td>[robot][bled][AN][splint][open][infected][imp][mi][internal_bleeding][lung_ruptured][o_dead]</td>"
			else
				dat += "<td>[e.name]</td><td>-</td><td>-</td><td>Not Found</td>"
			dat += "</tr>"
		var/hasMalignants = "" // malignant organs
		for(var/obj/item/organ/i in occupant.internal_organs)
			var/mech = ""
			var/i_dead = ""
			var/mi = ""
			if(i.status & ORGAN_ASSISTED)
				mech = "Assisted:"
			if(i.robotic >= ORGAN_ROBOT)
				mech = "Mechanical:"
			if(i.status & ORGAN_DEAD)
				i_dead = "Necrotic"
			var/infection = "None"
			switch (i.germ_level)
				if (INFECTION_LEVEL_ONE to INFECTION_LEVEL_ONE + 200)
					infection = "Mild Infection"
				if (INFECTION_LEVEL_ONE + 200 to INFECTION_LEVEL_ONE + 300)
					infection = "Mild Infection+"
				if (INFECTION_LEVEL_ONE + 300 to INFECTION_LEVEL_ONE + 400)
					infection = "Mild Infection++"
				if (INFECTION_LEVEL_TWO to INFECTION_LEVEL_TWO + 200)
					infection = "Acute Infection"
				if (INFECTION_LEVEL_TWO + 200 to INFECTION_LEVEL_TWO + 300)
					infection = "Acute Infection+"
				if (INFECTION_LEVEL_TWO + 300 to INFECTION_LEVEL_THREE - 50)
					infection = "Acute Infection++"
				if (INFECTION_LEVEL_THREE -49 to INFINITY)
					infection = "Necrosis Detected"

			if(istype(i, /obj/item/organ/internal/appendix))
				var/obj/item/organ/internal/appendix/A = i
				if(A.inflamed)
					infection = "Inflammation detected!"
			for(var/datum/medical_issue/MI in i.medical_issues)
				mi += "[MI.name] detected:"

			// begin - malignant organs
			if(istype(i, /obj/item/organ/internal/malignant))
				var/obj/item/organ/external/ORG = occupant.organs_by_name[i.parent_organ]
				hasMalignants += span_red(" -[ORG.name]") + "<BR>"
			// end

			dat += "<tr>"
			if(fake_death && istype(i, /obj/item/organ/internal/brain))
				dat += "<td>[i.name]</td><td>N/A</td><td>200</td><td>[infection]:[mi][mech][i_dead]</td><td></td>"
			else if(fake_death && istype(i, /obj/item/organ/internal/lungs))
				dat += "<td>[i.name]</td><td>N/A</td><td>25</td><td>[infection]:[mi][mech][i_dead]</td><td></td>"
			else
				dat += "<td>[i.name]</td><td>N/A</td><td>[i.damage]</td><td>[infection]:[mi][mech][i_dead]</td><td></td>"
			dat += "</tr>"
		for(var/organ_tag in occupant.species.has_organ) //Check to see if we are missing any organs
			var/organData[0]
			var/obj/item/organ/O = occupant.species.has_organ[organ_tag]
			var/name = initial(O.name)
			organData["name"] = name
			O = occupant.internal_organs_by_name[organ_tag]
			if(!O) // Missing organ
				dat += "<tr>"
				dat += "<td>[name]</td><td>N/A</td><td>NA</td><td>MISSING</td><td></td>"
				dat += "</tr>"
		dat += "</table>"
		if(occupant.sdisabilities & BLIND)
			dat += span_red("Cataracts detected.") + "<BR>"
		if(occupant.disabilities & NEARSIGHTED)
			dat += span_red("Retinal misalignment detected.") + "<BR>"
		// begin - malignant organs
		if(hasMalignants != "")
			dat += span_red("Unknown anatomy detected!") + "<BR>[hasMalignants]"
		// end
		if(has_withdrawl != "")
			dat += span_red("Experiencing withdrawal symptoms!") + "<BR>[has_withdrawl]"
		if(HUSK in occupant.mutations) // VOREstation edit
			dat += span_red("Anatomical structure lost, resuscitation not possible!") + "<BR>"
	else
		dat += "\The [src] is empty."

	return dat

//Body Scan Console
/obj/machinery/body_scanconsole
	var/obj/machinery/bodyscanner/scanner
	var/delete
	var/temphtml
	name = "Body Scanner Console"
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "body_scannerconsole"
	dir = 8
	density = FALSE
	anchored = TRUE
	unacidable = TRUE
	circuit = /obj/item/circuitboard/scanner_console
	var/printing = null

/obj/machinery/body_scanconsole/Initialize(mapload)
	. = ..()
	findscanner()

/obj/machinery/body_scanconsole/Destroy()
	if(scanner)
		scanner.console = null
	return ..()

/obj/machinery/body_scanconsole/attackby(obj/item/I, mob/user)
	if(computer_deconstruction_screwdriver(user, I))
		return
	else if(istype(I, /obj/item/multitool)) //Did you want to link it?
		var/obj/item/multitool/P = I
		if(P.connectable)
			if(istype(P.connectable, /obj/machinery/bodyscanner))
				var/obj/machinery/bodyscanner/C = P.connectable
				scanner = C
				C.console = src
				to_chat(user, span_warning(" You link the [src] to the [P.connectable]!"))
		else
			to_chat(user, span_warning(" You store the [src] in the [P]'s buffer!"))
			P.connectable = src
		return
	else
		return attack_hand(user)

/obj/machinery/body_scanconsole/power_change()
	update_icon()

/obj/machinery/body_scanconsole/ex_act(severity)
	switch(severity)
		if(1.0)
			//SN src = null
			qdel(src)
			return
		if(2.0)
			if (prob(50))
				//SN src = null
				qdel(src)
				return
	return

/obj/machinery/body_scanconsole/proc/findscanner()
	spawn(5)
		var/obj/machinery/bodyscanner/bodyscannernew = null
		// Loop through every direction
		for(dir in list(NORTH, EAST, SOUTH, WEST)) // Loop through every direction
			bodyscannernew = locate(/obj/machinery/bodyscanner, get_step(src, dir)) // Try to find a scanner in that direction
			if(bodyscannernew)
				scanner = bodyscannernew
				bodyscannernew.console = src
				set_dir(get_dir(src, bodyscannernew))
				return
		return

/obj/machinery/body_scanconsole/attack_ai(user as mob)
	return attack_hand(user)

/obj/machinery/body_scanconsole/attack_ghost(user as mob)
	return attack_hand(user)

/obj/machinery/body_scanconsole/attack_hand(user as mob)
	if(stat & (NOPOWER|BROKEN))
		return

	if(!scanner)
		findscanner()
		if(!scanner)
			to_chat(user, span_notice("Scanner not found!"))
			return

	if(scanner.panel_open)
		to_chat(user, span_notice("Close the maintenance panel first."))
		return

	if(scanner)
		return scanner.tgui_interact(user)


// === merged from adv_med_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/bodyscanner
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "scanner_open"

/obj/machinery/body_scanconsole
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "scanner_terminal_off"
	density = TRUE

/obj/machinery/bodyscanner/proc/get_vored_occupant_data(list/incoming, mob/living/carbon/human/H)
	var/humanprey = 0
	var/livingprey = 0
	var/objectprey = 0

	for(var/obj/belly/B as anything in H.vore_organs)
		for(var/C in B)
			if(ishuman(C))
				humanprey++
			else if(isliving(C))
				livingprey++
			else
				objectprey++

	incoming["livingPrey"] = livingprey
	incoming["humanPrey"] = humanprey
	incoming["objectPrey"] = objectprey
	incoming["weight"] = H.weight

	return incoming

/obj/machinery/bodyscanner/update_icon()
	cut_overlays()

	if(!occupant)
		icon_state = "scanner_open"
		set_light(0)
		if(console)
			console.update_icon(0)
		return

	// base image
	icon_state = "new_scanner_off"

	// Determine gradient state
	var/state
	var/scan = TRUE
	var/h_ratio = occupant.health / occupant.getMaxHealth()
	if(occupant.status_flags & FAKEDEATH)
		h_ratio = -1 //shows up dead
	if(console)
		console.update_icon(h_ratio)

	if(stat & (NOPOWER|BROKEN))
		state = "gradient_gray"
		scan = FALSE
		set_light(0)
	else
		switch(h_ratio)
			if(1.000)
				state = "gradient_green"
				set_light(l_range = 1.5, l_power = 2, l_color = COLOR_LIME)
			if(0.001 to 0.999)
				state = "gradient_yellow"
				set_light(l_range = 1.5, l_power = 2, l_color = COLOR_YELLOW)
			else
				state = "gradient_red"
				set_light(l_range = 1.5, l_power = 2, l_color = COLOR_RED)

	// First, we render the occupant
	var/image/occ = image(occupant)
	occ.dir = SOUTH
	var/matrix/M = matrix()
	M.Turn(dir == EAST ? 90 : -90)
	occ.transform = M
	occ.plane = plane
	occ.layer = layer + 0.1
	occ.filters = list(
		filter("type" = "alpha", "icon" = icon(icon, "alpha_mask", dir = dir == EAST ? EAST : WEST)),
		filter("type" = "color", "color" = "#000000")
	)
	add_overlay(occ)

	if(scan)
		// Second, we render the scan beam
		var/image/scan_beam = image(icon(icon, "scan_beam"))
		scan_beam.plane = plane
		scan_beam.layer = layer + 0.2
		add_overlay(scan_beam)

	if(state)
		// Third, we tint everything
		var/image/gradient = image(icon(icon, state))
		gradient.plane = plane
		gradient.layer = layer + 0.3
		add_overlay(gradient)


/obj/machinery/body_scanconsole/update_icon(h_ratio)
	if(stat & (NOPOWER|BROKEN))
		icon_state = "scanner_terminal_off"
		set_light(0)
	else
		if(scanner)
			if(h_ratio)
				switch(h_ratio)
					if(1.000)
						icon_state = "scanner_terminal_green"
						set_light(l_range = 1.5, l_power = 2, l_color = COLOR_LIME)
					if(-0.999 to 0.000)
						icon_state = "scanner_terminal_red"
						set_light(l_range = 1.5, l_power = 2, l_color = COLOR_RED)
					else
						icon_state = "scanner_terminal_dead"
						set_light(l_range = 1.5, l_power = 2, l_color = COLOR_RED)
			else
				icon_state = "scanner_terminal_blue"
				set_light(l_range = 1.5, l_power = 2, l_color = COLOR_BLUE)
		else
			icon_state = "scanner_terminal_off"
			set_light(0)
