//// This is a detatched version of a phasic health analyser for admin use on command
// Mode dictates whether to include specific limb damage
// advscan is the strength of the scan required, 3 being similar to a phasic health analyser.
// showadvscan toggles whether to give additional scan information about chemicals in their body.
// By default this proc is set to it's most powerful scan.

/mob/living/proc/scan_mob(mob/user, mode = 1, advscan = SCANNABLE_SECRETIVE, showadvscan = 1)
	var/mob/living/M = src
	var/dat = ""

	// Start with the cyborg analyser first
	if(isrobot(M))
		var/burn_load = round(M.injury_load(INJURY_CATEGORY_THERMAL))
		var/brute_load = round(M.injury_load(INJURY_CATEGORY_PHYSICAL))
		var/BU = burn_load > 50 	? 	span_bold("[burn_load]") 		: burn_load
		var/BR = brute_load > 50 	? 	span_bold("[brute_load]") 	: brute_load
		user.show_message(span_blue("Analyzing Results for [M]:\n\t Overall Status: [M.stat == DEAD ? "fully disabled" : "[round(M.vitality() * 100)]% functional"]"))
		user.show_message("\t Key: [span_orange("Electronics")]/[span_red("Brute")]", 1)
		user.show_message("\t Damage Specifics: [span_orange("[BU]")] - [span_red("[BR]")]")
		if(M.tod && M.stat == DEAD)
			user.show_message(span_blue("Time of Disable: [M.tod]"))
		var/mob/living/silicon/robot/R = M
		var/obj/item/cell/cell = R.get_cell()
		if(cell)
			var/cell_charge = round(cell.percent())
			var/cell_text
			if(cell_charge > 60)
				cell_text = span_green("[cell_charge]")
			else if (cell_charge > 30)
				cell_text = span_yellow("[cell_charge]")
			else if (cell_charge > 10)
				cell_text = span_orange("[cell_charge]")
			else if (cell_charge > 1)
				cell_text = span_red("[cell_charge]")
			else
				cell_text = span_red(span_bold("[cell_charge]"))
			user.show_message("\t Power Cell Status: [span_blue("[capitalize(cell.name)]")] at [cell_text]% charge")
		var/list/damaged = R.get_faulted_components(TRUE)
		user.show_message(span_blue("Localized Damage:"),1)
		if(length(damaged)>0)
			for(var/datum/robot_component/org as anything in damaged)
				user.show_message(span_blue(text("\t []: [][] - [] - [] - []",	\
				span_blue(capitalize(org.name)),					\
				(org.installed == ROBOT_PART_DESTROYED)	?	"[span_red(span_bold("DESTROYED"))] "					:"",\
				(org.get_wiring_damage() > 0)	?	"[span_orange("[round(org.get_wiring_damage(), 0.1)]")]"	:0,	\
				(org.get_structural_damage() > 0)	?	"[span_red("[round(org.get_structural_damage(), 0.1)]")]"					:0,	\
				(org.toggled)	?	"Toggled ON"	:	"[span_red("Toggled OFF")]",\
				(org.powered)	?	"Power ON"		:	"[span_red("Power OFF")]")),1)
		else
			user.show_message(span_blue("\t Components are OK."),1)
		if(R.emagged && prob(5))
			user.show_message(span_red("\t ERROR: INTERNAL SYSTEMS COMPROMISED"),1)
		user.show_message(span_blue("Operating Temperature: [M.bodytemperature-T0C]&deg;C ([M.bodytemperature*1.8-459.67]&deg;F)"), 1)
		return

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		to_chat(user, span_notice("Analyzing Results for \the [H]:"))
		// Structural / wiring / system afflictions on synthetic parts.
		for(var/datum/affliction/A as anything in H.body?.afflictions)
			if(!(H.body.biology_of(A.location) & BIOLOGY_SYNTHETIC))
				continue
			to_chat(user, "System fault: [span_orange(A.name)][A.location ? " in [A.location]" : ""] ([dq_qualitative_damage_band(A.load_value(), 100)])")
		to_chat(user, "Key: [span_orange("Electronics")]/[span_red("Brute")]")
		to_chat(user, span_notice("External prosthetics:"))
		var/organ_found
		if(H.internal_organs.len)
			for(var/obj/item/organ/external/E in H.organs)
				if(!(E.robotic >= ORGAN_ROBOT))
					continue
				organ_found = 1
				to_chat(user, "[E.name]: [span_red("[round(E.get_trauma())] ")] [span_orange("[round(E.get_burn())]")]")
		if(!organ_found)
			to_chat(user, "No prosthetics located.")
		to_chat(user, "<hr>")
		to_chat(user, span_notice("Internal prosthetics:"))
		organ_found = null
		if(H.internal_organs.len)
			for(var/obj/item/organ/O in H.internal_organs)
				if(!(O.robotic >= ORGAN_ROBOT))
					continue
				organ_found = 1
				to_chat(user, "[O.name]: [span_red("[O.damage]")]")
		if(!organ_found)
			to_chat(user, "No prosthetics located.")

	if(isSynthetic(M))
		return //End here if they're FBP

	//Then do normal health scan
	var/oxy_load = round(M.oxygen_debt())
	var/tox_load = round(M.injury_load(INJURY_CATEGORY_TOXIC))
	var/burn_load = round(M.injury_load(INJURY_CATEGORY_THERMAL))
	var/brute_load = round(M.injury_load(INJURY_CATEGORY_PHYSICAL))
	var/fake_oxy = max(oxy_load, (300 - (tox_load + burn_load + brute_load)))
	var/OX = oxy_load > 50 		? 	span_bold("[oxy_load]") 		: oxy_load
	var/TX = tox_load > 50 		? 	span_bold("[tox_load]")  		: tox_load
	var/BU = burn_load > 50 	? 	span_bold("[burn_load]") 		: burn_load
	var/BR = brute_load > 50 	? 	span_bold("[brute_load]")  		: brute_load
	var/analyzed_results = ""
	if(M.status_flags & FAKEDEATH)
		OX = fake_oxy > 50 			? 	span_bold("[fake_oxy]") 			: fake_oxy
		dat += span_notice("Analyzing Results for [M]:")
		dat += "<br>"
		dat += span_notice("Overall Status: dead")
		dat += "<br>"
	else
		analyzed_results += "Analyzing Results for [M]:\n\t Overall Status: [M.stat == DEAD ? "dead" : "[round(M.vitality() * 100)]% healthy[M.is_critical() ? " (critical)" : ""]"]<br>"
	analyzed_results += "\tKey: [span_cyan("Suffocation")]/[span_green("Toxin")]/[span_orange("Burns")]/[span_red("Brute")]<br>"
	analyzed_results += "\tDamage Specifics: [span_cyan("[OX]")] - [span_green("[TX]")] - [span_orange("[BU]")] - [span_red("[BR]")]<br>"
	analyzed_results +=	"Body Temperature: [M.bodytemperature-T0C]&deg;C ([M.bodytemperature*1.8-459.67]&deg;F)<br>"
	analyzed_results = span_notice(analyzed_results)
	dat += analyzed_results
	if(M.timeofdeath && (M.stat == DEAD || (M.status_flags & FAKEDEATH)))
		dat += 	span_notice("Time of Death: [worldtime2stationtime(M.timeofdeath)]")
		dat += "<br>"
		var/tdelta = round(world.time - M.timeofdeath)
		if(tdelta < (10 MINUTES * 10))
			dat += span_boldnotice("Subject died [DisplayTimeText(tdelta)] ago - resuscitation may be possible!")
			dat += "<br>"
	if(ishuman(M) && mode == 1)
		var/mob/living/carbon/human/H = M
		var/list/damaged = H.get_damaged_organs(1,1)
		dat += 	span_notice("Localized Damage, Brute/Burn:")
		dat += "<br>"
		if(length(damaged)>0)
			for(var/obj/item/organ/external/org in damaged)
				if(org.robotic >= ORGAN_ROBOT)
					continue
				else
					var/trauma = round(org.get_trauma())
					var/burn = round(org.get_burn())
					var/our_damage = "     [capitalize(org.name)]: [(trauma > 0) ? span_warning("[trauma]") : 0]"
					our_damage += "[(org.status & ORGAN_BLEEDING)?span_danger("\[Bleeding\]"):""] - "
					our_damage += "[(burn > 0) ? "[span_orange("[burn]")]" : 0]"
					dat += span_notice(our_damage) + "<br>"
		else
			dat += span_notice("    Limbs are OK.")
			dat += "<br>"
		// This handles genetic side effects and tells you the treatment, if any.
		// These are handled in side_effects.dm
		if(H.genetic_side_effects)
			for(var/datum/genetics/side_effect/side_effect in H.genetic_side_effects)
				var/datum/reagent/Rd = SSchemistry.chemical_reagents[side_effect.antidote_reagent]
				dat += "<br>"
				dat += span_danger("Patient is suffering from [side_effect.name]. ")
				if(Rd)
					dat += span_danger("Treatment: [Rd]<br>")
				else
					dat += "There is no known treatment.<br>"

	OX = oxy_load > 50 ? 	 "[span_cyan(span_bold("Severe oxygen deprivation detected"))]" 			: 	"Subject bloodstream oxygen level normal"
	TX = tox_load > 50 ? 	 "[span_green(span_bold("Dangerous amount of toxins detected"))]" 	: 	"Subject bloodstream toxin level minimal"
	BU = burn_load > 50 ?  "[span_orange(span_bold("Severe burn damage detected"))]" 			:	"Subject burn injury status O.K"
	BR = brute_load > 50 ? "[span_red(span_bold("Severe anatomical damage detected"))]"		 		: 	"Subject brute-force injury status O.K"
	if(M.status_flags & FAKEDEATH)
		OX = fake_oxy > 50 ? 		span_warning("Severe oxygen deprivation detected") 	: 	"Subject bloodstream oxygen level normal"
	dat += "[OX] | [TX] | [BU] | [BR]<br>"
	if(M.radiation)
		if(advscan >= SCANNABLE_DIFFICULT && showadvscan == 1)
			var/severity = ""
			if(M.radiation >= 1500)
				severity = "Lethal"
			else if(M.radiation >= 600)
				severity = "Critical"
			else if(M.radiation >= 400)
				severity = "Severe"
			else if(M.radiation >= 300)
				severity = "Moderate"
			else if(M.radiation >= 100)
				severity = "Low"
			dat += span_warning("[severity] levels of acute radiation sickness detected. [round(M.radiation/50)]Gy. [(severity == "Critical" || severity == "Lethal") ? " Immediate treatment advised." : ""]")
			dat += "<br>"
		else
			dat += span_warning("Acute radiation sickness detected.")
			dat += "<br>"
	if(M.accumulated_rads)
		if(advscan >= SCANNABLE_DIFFICULT && showadvscan == 1)
			var/severity = ""
			if(M.accumulated_rads >= 1500)
				severity = "Critical"
			else if(M.accumulated_rads >= 600)
				severity = "Severe"
			else if(M.accumulated_rads >= 400)
				severity = "Moderate"
			else if(M.accumulated_rads >= 300)
				severity = "Mild"
			else if(M.accumulated_rads >= 100)
				severity = "Low"
			dat += span_warning("[severity] levels of chronic radiation sickness detected. [round(M.accumulated_rads/50)]Gy.")
			dat += "<br>"
		else
			dat += span_warning("Chronic radiation sickness detected.")
			dat += "<br>"
	if(iscarbon(M))
		var/mob/living/carbon/C = M
		if(C.reagents.total_volume)
			var/unknown = 0
			var/reagentdata[0]
			var/unknownreagents[0]
			for(var/datum/reagent/R as anything in C.reagents.reagent_list)
				if(R.scannable && advscan >= R.scannable)
					reagentdata["[R.id]"] = span_notice("\t[round(C.reagents.get_reagent_amount(R.id), 1)]u [R.name][(R.overdose && R.volume > R.overdose) ? " - [span_danger("Overdose")]" : ""]")
					reagentdata["[R.id]"] += "<br>"
				else
					unknown++
					unknownreagents["[R.id]"] = span_notice("\t[round(C.reagents.get_reagent_amount(R.id), 1)]u [R.name][(R.overdose && R.volume > R.overdose) ? " - [span_danger("Overdose")]" : ""]")
					unknownreagents["[R.id]"] += "<br>"
			if(reagentdata.len)
				dat += span_notice("Beneficial reagents detected in subject's blood:")
				dat += "<br>"
				for(var/d in reagentdata)
					dat += reagentdata[d]
			if(unknown)
				dat += span_warning("Warning: Unknown substance[(unknown>1)?"s":""] detected in subject's blood.")
				dat += "<br>"
		if(C.ingested && C.ingested.total_volume)
			var/unknown = 0
			var/stomachreagentdata[0]
			var/stomachunknownreagents[0]
			for(var/datum/reagent/R as anything in C.ingested.reagent_list)
				if(R.scannable && advscan >= R.scannable)
					stomachreagentdata["[R.id]"] = span_notice("\t[round(C.ingested.get_reagent_amount(R.id), 1)]u [R.name][(R.overdose && R.volume > R.overdose) ? " - [span_danger("Overdose")]" : ""]")
					stomachreagentdata["[R.id]"] += "<br>"
					if(!advscan || !showadvscan)
						dat += span_notice("[R.name] found in subject's stomach.")
						dat += "<br>"
				else
					++unknown
					stomachunknownreagents["[R.id]"] = span_notice("\t[round(C.ingested.get_reagent_amount(R.id), 1)]u [R.name][(R.overdose && R.volume > R.overdose) ? " - [span_danger("Overdose")]" : ""]")
					stomachunknownreagents["[R.id]"] += "<br>"
			if(showadvscan == 1)
				dat += span_notice("Beneficial reagents detected in subject's stomach:")
				dat += "<br>"
				for(var/d in stomachreagentdata)
					dat += stomachreagentdata[d]
			if(unknown)
				dat += span_warning("Unknown substance[(unknown > 1)?"s":""] found in subject's stomach.")
				dat += "<br>"
		if(C.touching && C.touching.total_volume)
			var/unknown = 0
			var/touchreagentdata[0]
			var/touchunknownreagents[0]
			for(var/datum/reagent/R as anything in C.touching.reagent_list)
				if(R.scannable && advscan >= R.scannable)
					touchreagentdata["[R.id]"] = span_notice("\t[round(C.touching.get_reagent_amount(R.id), 1)]u [R.name][(R.overdose && R.can_overdose_touch && R.volume > R.overdose) ? " - [span_danger("Overdose")]" : ""]")
					touchreagentdata["[R.id]"] += "<br>"
					if(!advscan || !showadvscan)
						dat += span_notice("[R.name] found in subject's dermis.")
						dat += "<br>"
				else
					++unknown
					touchunknownreagents["[R.id]"] = span_notice("\t[round(C.ingested.get_reagent_amount(R.id), 1)]u [R.name][(R.overdose && R.can_overdose_touch && R.volume > R.overdose) ? " - [span_danger("Overdose")]" : ""]")
					touchunknownreagents["[R.id]"] += "<br>"
			if(showadvscan == 1)
				dat += span_notice("Beneficial reagents detected in subject's dermis:")
				dat += "<br>"
				for(var/d in touchreagentdata)
					dat += touchreagentdata[d]
			if(unknown)
				dat += span_warning("Unknown substance[(unknown > 1)?"s":""] found in subject's dermis.")
				dat += "<br>"
		if(C.IsInfected())
			for (var/datum/disease/virus in C.GetViruses())
				if(virus.visibility_flags & HIDDEN_SCANNER || virus.visibility_flags & HIDDEN_PANDEMIC)
					continue
				dat += span_alert(span_bold("Warning: [virus.form] detected in subject's blood."))
				dat += "<br>"
	if (M.injury_load(INJURY_CATEGORY_GENETIC))
		dat += span_warning("Subject appears to have been imperfectly cloned.")
		dat += "<br>"
//	if (M.reagents && M.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE))
//		user.show_message(span_notice("Bloodstream Analysis located [M.reagents:get_reagent_amount(REAGENT_ID_INAPROVALINE)] units of rejuvenation chemicals."))
	if (M.has_brain_worms())
		dat += span_warning("Subject suffering from aberrant brain activity. Recommend further scanning.")
		dat += "<br>"
	else if (M.is_brain_dead() || !M.has_brain())
		dat += span_warning("Subject is brain dead.")
		dat += "<br>"
	else if (M.injury_load(INJURY_CATEGORY_NEURAL) >= 60)
		dat += span_warning("Critical brain damage detected. Subject is at risk of brain death.")
		dat += "<br>"
	else if (M.injury_load(INJURY_CATEGORY_NEURAL) >= 25)
		dat += span_warning("Severe brain damage detected. Subject likely to have a traumatic brain injury.")
		dat += "<br>"
	else if (M.injury_load(INJURY_CATEGORY_NEURAL) >= 10)
		dat += span_warning("Significant brain damage detected. Subject may have had a concussion.")
		dat += "<br>"
	else if (M.injury_load(INJURY_CATEGORY_NEURAL) >= 1)
		dat += span_warning("Minor brain damage detected.")
		dat += "<br>"
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		// Addictions
		if(H.get_addiction_to_reagent(REAGENT_ID_ASUSTENANCE) > 0)
			dat += span_warning("Biologically unstable, requires [REAGENT_ASUSTENANCE] to function properly.")
			dat += "<br>"
		for(var/addic in H.get_all_addictions())
			if(H.get_addiction_to_reagent(addic) > 0 && (advscan >= 2 || H.get_addiction_to_reagent(addic) <= 120)) // high enough scanner upgrade detects addiction even if not almost withdrawling
				var/datum/reagent/R = SSchemistry.chemical_reagents[addic]
				if(R.id == REAGENT_ID_ASUSTENANCE)
					continue
				if(advscan >= 1)
					// Shows multiple
					if(advscan >= 2 && H.get_addiction_to_reagent(addic) <= 80)
						dat += span_warning("Experiencing withdrawls from [R.name], [REAGENT_INAPROVALINE] treatment recomended.")
						dat += "<br>"
					else
						dat += span_warning("Chemical dependance detected: [R.name].")
						dat += "<br>"
				else
					// Shows single
					dat += span_warning("Chemical dependance detected.")
					dat += "<br>"
					break
		// Appendix
		for(var/obj/item/organ/internal/appendix/a in H.internal_organs)
			var/severity = ""
			if(a.inflamed > 3)
				severity = "Severe"
			else if(a.inflamed > 2)
				severity = "Moderate"
			else if(a.inflamed >= 1)
				severity = "Mild"
			if(severity)
				dat += span_warning("[severity] inflammation detected in subject [a.name].")
				dat += "<br>"
		if(HUSK in H.mutations)
			dat += span_danger("Anatomical structure lost, resuscitation not possible!")
			dat += "<br>"
		// Infections, fractures, and IB
		var/basic_fracture = 0	// If it's a basic scanner
		var/basic_ib = 0		// If it's a basic scanner
		var/fracture_dat = ""	// All the fractures
		var/infection_dat = ""	// All the infections
		var/ib_dat = ""			// All the IB
		var/int_damage_acc = 0  // For internal organs
		for(var/obj/item/organ/internal/i in H.internal_organs)
			if(!i || i.robotic >= ORGAN_ROBOT || istype(i, /obj/item/organ/internal/brain))
				continue 		// not there or robotic or brain which is handled separately
			if(i.damage || i.status & ORGAN_DEAD)
				int_damage_acc += (i.damage + ((i.status & ORGAN_DEAD) ? 30 : 0))
				if(advscan >= SCANNABLE_DIFFICULT && showadvscan == 1)
					if(advscan >= SCANNABLE_SECRETIVE)
						var/dam_adj
						if(i.damage >= i.min_broken_damage || i.status & ORGAN_DEAD)
							dam_adj = "Severe"
						else if(i.damage >= i.min_bruised_damage)
							dam_adj = "Moderate"
						else
							dam_adj = "Mild"
						dat += span_warning("[dam_adj] damage detected to subject's [i.name].")
						dat += "<br>"
					else
						dat += span_warning("Damage detected to subject's [i.name].")
						dat += "<br>"
		if(int_damage_acc >= 1 && (advscan < SCANNABLE_DIFFICULT || !showadvscan))
			dat += span_warning("Damage detected to subject's internal organs.")
			dat += "<br>"
		for(var/obj/item/organ/external/e in H.organs)
			if(!e)
				continue
			// Broken limbs
			if(e.status & ORGAN_BROKEN)
				if((e.name in list(BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG, BP_HEAD, BP_TORSO, BP_GROIN)) && (!e.splinted))
					fracture_dat += span_warning("Unsecured fracture in subject [e.name]. Splinting recommended for transport.")
					fracture_dat += "<br>"
				else if(advscan >= SCANNABLE_ADVANCED && showadvscan == 1)
					fracture_dat += span_warning("Bone fractures detected in subject [e.name].")
					fracture_dat += "<br>"
				else
					basic_fracture = 1
			// Infections
			if(e.has_infected_wound())
				dat += span_warning("Infected wound detected in subject [e.name]. Disinfection recommended.")
				dat += "<br>"
			// IB
			if(length(dq_limb_internal_bleeds(e)))
				if(advscan >= SCANNABLE_ADVANCED && showadvscan == 1)
					ib_dat += span_warning("Internal bleeding detected in subject [e.name].")
					ib_dat += "<br>"
				else
					basic_ib = 1
		if(basic_fracture)
			fracture_dat += span_warning("Bone fractures detected. Advanced scanner required for location.")
			fracture_dat += "<br>"
		if(basic_ib)
			ib_dat += span_warning("Internal bleeding detected. Advanced scanner required for location.")
			ib_dat += "<br>"
		dat += fracture_dat
		dat += infection_dat
		dat += ib_dat

		// Blood level
		if(H.vessel)
			var/blood_volume = H.vessel.get_reagent_amount(REAGENT_ID_BLOOD)
			var/blood_percent =  round((blood_volume / H.species.blood_volume)*100)
			var/blood_type = H.dna.b_type
			var/blood_reagent = H.species.blood_reagents
			if(blood_volume <= H.species.blood_volume*H.species.blood_level_danger)
				dat += span_danger(span_italics("Warning: Blood Level CRITICAL: [blood_percent]% [blood_volume]cl. Type: [blood_type]. Basis: [blood_reagent]."))
				dat += "<br>"
			else if(blood_volume <= H.species.blood_volume*H.species.blood_level_warning)
				dat += span_danger(span_italics("Warning: Blood Level VERY LOW: [blood_percent]% [blood_volume]cl. Type: [blood_type]. Basis: [blood_reagent]."))
				dat += "<br>"
			else if(blood_volume <= H.species.blood_volume*H.species.blood_level_safe)
				dat += span_danger("Warning: Blood Level LOW: [blood_percent]% [blood_volume]cl. Type: [blood_type]. Basis: [blood_reagent].")
				dat += "<br>"
			else
				dat += span_notice("Blood Level Normal: [blood_percent]% [blood_volume]cl. Type: [blood_type]. Basis: [blood_reagent].")
				dat += "<br>"
		dat += span_notice("Subject's pulse: [H.pulse == PULSE_THREADY || H.pulse == PULSE_NONE ? span_red(H.get_pulse(GETPULSE_TOOL) + " bpm") : span_blue(H.get_pulse(GETPULSE_TOOL) + " bpm")].") // VORE Edit: Missed a linebreak here.
		dat += "<br>"
		var/datum/component/xenochimera/xc = H.get_xenochimera_component()
		if(xc)
			if(H.stat == DEAD && xc.revive_ready == REVIVING_READY && !H.hasnutriment())
				dat += span_danger("WARNING: Protein levels low. Subject incapable of reconstitution.")
			else if(xc.revive_ready == REVIVING_NOW)
				dat += span_warning("Subject is undergoing form reconstruction. Estimated time to finish is in: [round((xc.revive_finished - world.time) / 10)] seconds.")
			else if(xc.revive_ready == REVIVING_DONE)
				dat += span_notice("Subject is ready to hatch. Transfer to dark room for holding with food available.")
			else if(H.stat == DEAD)
				dat+= span_danger("WARNING: Defib will cause extreme pain and set subject feral. Sedation recommended prior to defibrillation.")
			else // If they bop them and they're not dead or reviving, give 'em a little notice.
				dat += span_notice("Subject is a Xenochimera. Treat accordingly.")

		// GM custom afflictions
		for(var/datum/affliction/custom/A as anything in dq_custom_afflictions_of(H))
			if(advscan < A.advscan)
				continue
			dat += span_danger("Warning: [A.name] detected in [A.location].<br>")
			if(advscan >= A.advscan_cure)
				dat += span_notice("[A.cure_hint()]<br>")

	user.show_message(dat, 1)
