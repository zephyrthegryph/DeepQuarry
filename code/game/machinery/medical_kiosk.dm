#define BROKEN_BONES 0x1
#define INTERNAL_BLEEDING 0x2
#define EXTERNAL_BLEEDING 0x4
#define SERIOUS_EXTERNAL_DAMAGE 0x8
#define SERIOUS_INTERNAL_DAMAGE 0x10
#define ACUTE_RADIATION_DOSE 0x20
#define CHRONIC_RADIATION_DOSE 0x40
#define TOXIN_DAMAGE 0x80
#define OXY_DAMAGE 0x100
#define HUSKED_BODY 0x200
#define INFECTION 0x400
#define VIRUS 0x800
#define INTERNAL_DAMAGE 0x1000
#define CLONE_DAMAGE 0x2000
#define ORGAN_DISLOCATED 0x4000
#define ALCOHOL_POISONING 0x8000
#define BLOODLOSS 0x10000
#define WEIRD_ORGANS 0x20000 // malignant

/obj/machinery/medical_kiosk
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 40
	name = "medical kiosk"
	desc = "A helpful kiosk for finding out whatever is wrong with you."
	icon = 'icons/obj/machines/medical_kiosk.dmi'
	icon_state = "kiosk_off"
	idle_power_usage = 5
	bubble_icon = "medical"
	active_power_usage = 200
	circuit = /obj/item/circuitboard/medical_kiosk
	anchored = TRUE
	density = TRUE

	var/mob/living/active_user
	var/db_key

	//These are the variables that control 'When we were
	COOLDOWN_DECLARE(dispense_cooldown_until)
	var/dispense_cooldown = 1 MINUTE //If abused, this can be decreased. The machine gives chems and supplies that are easily and readily available, barring tramadol. If someone intentionally breaks their arm to rob the machines of their tramadol to fuel their addiction, that's a gameplay feature.

	/// This determines if the kiosk can dispense or not. Edit the below line to FALSE if you don't want them to do such.
	var/can_dispense = TRUE


/obj/machinery/medical_kiosk/proc/appearance_awake()
	return (operable() && active_user()) ? 1 : 0

APPEARANCE_TEMPLATE(/obj/machinery/medical_kiosk, "kiosk{appearance_awake?:_off}")
DECLARE_APPEARANCE(/obj/machinery/medical_kiosk, "panel_open", list("1" = list(APPEARANCE_ICON_STATE = "kiosk_open")))

EXTEND_INTERACTIONS(/obj/machinery/medical_kiosk, \
	INTERACT_HAND(null, PROC_REF(medical_kiosk_interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(medical_kiosk_interaction_item)), \
)

/// Old attack_hand.
/obj/machinery/medical_kiosk/proc/medical_kiosk_interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(istype(user) && Adjacent(user))
		if(!operable() || panel_open)
			to_chat(user, span_warning("\The [src] seems to be nonfunctional..."))
		else if(active_user() && active_user() != user)
			to_chat(user, span_warning("Another patient has begin using this machine. Please wait for them to finish, or their session to time out."))
		else
			start_using(user)
	return TRUE

/// Old attackby.
/obj/machinery/medical_kiosk/proc/medical_kiosk_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	return default_part_replacement(user, O) ? TRUE : FALSE

/obj/machinery/medical_kiosk/proc/wake_lock(mob/living/user)
	rel_set(src, nameof(active_user), user)
	update_icon()
	set_use_power(USE_POWER_ACTIVE)

/obj/machinery/medical_kiosk/proc/suspend()
	rel_clear(src, nameof(active_user))
	update_icon()
	set_use_power(USE_POWER_IDLE)

/obj/machinery/medical_kiosk/proc/start_using(mob/living/user)
	// Out of standby
	wake_lock(user)

	// User requests service
	act_message(user, src, MSG_SELF("You wake %T%."), MSG_OTHERS(span_bold("%U%") + " wakes %T%."))
	open_request(src, /datum/prompt/choice, PROC_REF(service_chosen), valid = PROC_REF(kiosk_ready), answerer = user, title = "[src]", question = "What service would you like?", choices = list("Health Scan", "Backup Scan", "Cancel"), buttons = TRUE, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 10 SECONDS)
	return TRUE

/// Re-checked on the answer: the kiosk still works and its panel is shut.
/obj/machinery/medical_kiosk/proc/kiosk_ready(datum/request/R)
	return operable() && !panel_open

/// A cancel, a timeout or a failed re-check (moved away, kiosk broken or opened) suspends the kiosk.
/obj/machinery/medical_kiosk/proc/service_chosen(datum/act/request/A)
	if(!A.answer || A.answer.value == "Cancel")
		suspend()
		return
	var/mob/living/user = A.request.answerer
	var/choice = A.answer.value

	// Service begins, delay
	act_message(src, user, others = span_bold("%U%") + " scans %T% thoroughly!")
	flick("kiosk_active", src)
	task_start(/datum/task/timed/medical_kiosk_start_using, user, src, receiver = src, choice = choice)
	return TRUE

/datum/task/timed/medical_kiosk_start_using
	duration = 5 SECONDS
	complete_proc = /obj/machinery/medical_kiosk/proc/start_using_timed_done
	cancel_proc = /obj/machinery/medical_kiosk/proc/start_using_timed_failed
	var/choice

/obj/machinery/medical_kiosk/proc/start_using_timed_done(datum/task/timed/medical_kiosk_start_using/task)
	var/mob/living/user = task.actor
	var/choice = task.choice
	if(!operable())
		return

	// Service completes
	switch(choice)
		if("Health Scan")
			var/health_report = medical_scan(user)
			to_chat(user, span_boldnotice("Health report results:")+health_report)
		if("Backup Scan")
			if(!our_db())
				to_chat(user, span_notice(span_bold("Backup scan results:")) + "<br>DATABASE ERROR!")
			else
				var/scan_report = do_backup_scan(user)
				to_chat(user, span_notice(span_bold("Backup scan results:"))+scan_report)

	// Standby
	suspend()

/obj/machinery/medical_kiosk/proc/start_using_timed_failed(datum/task/timed/medical_kiosk_start_using/task)
	suspend()
	return

/obj/machinery/medical_kiosk/proc/medical_scan(mob/living/user)
	var/datum/diagnosis/diag = istype(user) ? user.diagnose(/datum/diagnostic_profile/automation/kiosk) : null
	if(!diag)
		return "<br>" + span_warning("Unable to perform diagnosis on this type of life form.")
	// The kiosk's sensors read organic tissue only (its profile's biology).
	if(!(user.body.biology_of(null) & diag.profile.biology))
		return "<br>" + span_warning("Unable to perform diagnosis on synthetic life forms.")

	var/problems = 0
	for(var/obj/item/organ/external/E in user.organs)
		if(E.is_fractured())
			problems |= BROKEN_BONES
		if(E.status & (ORGAN_DEAD|ORGAN_DESTROYED))
			problems |= SERIOUS_EXTERNAL_DAMAGE
		if(E.status & ORGAN_BLEEDING)
			problems |= EXTERNAL_BLEEDING
		if(E.dislocated == 1)
			problems |= ORGAN_DISLOCATED
		// Internal bleeds don't set ORGAN_BLEEDING; external bleeding is caught above.
		if(length(dq_limb_internal_bleeds(E)))
			problems |= INTERNAL_BLEEDING

	for(var/obj/item/organ/internal/I in user.internal_organ_list())
		if(I.is_fractured() || (I.status & (ORGAN_DEAD|ORGAN_DESTROYED)))
			problems |= SERIOUS_INTERNAL_DAMAGE
		if(I.status & ORGAN_BLEEDING)
			problems |= INTERNAL_BLEEDING
		if(I.damage)
			problems |= INTERNAL_DAMAGE
		// begin- malignants
		if(istype(I,/obj/item/organ/internal/malignant))
			problems |= WEIRD_ORGANS
		// end

	// Infections are findings of the kiosk's diagnosis, not raw germ counts.
	if(diag.has_finding_for(/datum/affliction/wound_infection))
		problems |= INFECTION

	if(user.has_mutation(HUSK))
		problems |= HUSKED_BODY

	// The kiosk's own triage sensors: what the detected conditions respond to.
	var/list/demand = user.body?.treatment_demand(diag.profile)
	if(demand?[TREAT_ANTITOXIN])
		problems |= TOXIN_DAMAGE
	var/saturation = user.body?.oxygenation()
	if(!isnull(saturation) && saturation < 93)
		problems |= OXY_DAMAGE
	if(user.radiation > 0)
		problems |= ACUTE_RADIATION_DOSE
	if(user.accumulated_rads > 0)
		problems |= CHRONIC_RADIATION_DOSE
	for(var/tag in list(TREAT_TISSUE_REPAIR, TREAT_BURN_CARE))
		if(_dq_band_rank(demand?[tag]) >= _dq_band_rank(DIAG_BAND_SEVERE))
			problems |= SERIOUS_EXTERNAL_DAMAGE
	if(demand?[TREAT_GENETIC_REPAIR])
		problems |= CLONE_DAMAGE

	var/is_drunk = FALSE //Just so we don't have to do another ishuman() check down there in !problems
	if(ishuman(user))
		var/mob/living/carbon/human/our_user = user
		if(our_user.has_known_contagion())
			problems |= VIRUS
		if(our_user.factor(BF_HEPATOTOXICITY))
			problems |= ALCOHOL_POISONING
		if(our_user.factor(BF_INTOXICATION))
			is_drunk = TRUE
		if(our_user.vessel.total_volume < (our_user.vessel.maximum_volume*0.95)) //Bloodloss. Only happens at below 95% blood.
			problems |= BLOODLOSS

	if(!problems) //Minor stuff that we really don't care much about, but can be annoying! So let's tell people how to fix it. But only if they don't  have a health crisis going on!
		var/minor_problems = ""
		if(user.has_status(STAT_HALLUCINATING))
			minor_problems += "<br>" + span_warning("Brain activity suggesting severe mental inhibitions detected - medical assistance recommended.")
		if(user.has_status(STAT_DROWSY) || user.has_status(STAT_SLEEPING))
			minor_problems += "<br>" + span_warning("Mild mental inhibitions detected - drinking coffee can improve symptoms and stimulate nervous system.")
		if(is_drunk)
			minor_problems += "<br>" + span_warning("Ethanol intoxication detected - suggest close observation to alleviate risk of injury.")
		if(user.current_pain())
			minor_problems += "<br>" + span_warning("Mild concussion detected - advising bed rest until feeling better.")
		if(user.has_status(STAT_JITTERY) || user.has_status(STAT_DIZZY))
			minor_problems += "<br>" + span_warning("Neurological symptoms detected - advising bed rest until feeling better.") //Resting fixes dizziness and jitteryness!
		else
			minor_problems += "<br>" + span_notice("No anatomical issues detected.")
			return minor_problems

	var/problem_text = ""

	//Dispensing vars! This ensures you don't get FLOODED with too many things and accidentally OD becuase the machine gave it to you!
	var/able_to_dispense = TRUE

	/// This determines if the kiosk has already selected one of the chems to dispense. This prevents ODs. Swap these to TRUE if you want to disable kiosks from giving out speicfic chems.
	var/paracetamol_given = FALSE
	var/tramadol_given = FALSE
	var/inaprovaline_given = FALSE
	var/medication_dispensed = FALSE

	if(!can_dispense || (!COOLDOWN_FINISHED(src, dispense_cooldown_until)))
		able_to_dispense = FALSE

	//Let's do this list from 'most severe' to 'least severe'

	if(problems & INTERNAL_BLEEDING) //Will kill you quick and you NEED medical treatment.
		problem_text += "<br>" + span_bolddanger("SEVERITY: 'LETHAL' - Internal bleeding detected - seek medical attention immediately!")
		if(able_to_dispense)
			medication_dispensed = TRUE
			new /obj/item/reagent_containers/pill/small_blood_restoration(src.loc)
	//If you aren't able to use iron...Well, sorry!

	if(problems & INFECTION) //Will kill you quick and you NEED medical treatment.
		problem_text += "<br>" + span_bolddanger("SEVERITY: 'LETHAL' - Infection detected - see a medical professional immediately!")
	//Nothin. Get to medical! Technically COULD give spaceacillin, but this is only meant to help you get TO medical, not REPLACE medical.

	if(problems & EXTERNAL_BLEEDING)
		problem_text += "<br>" + span_warning("SEVERITY: 'SEVERE' - External bleeding detected - advising pressure with cloth and bandaging or direct pressure until medical staff can assist.")
		if(able_to_dispense)
			medication_dispensed = TRUE
			var/obj/item/stack/medical/bruise_pack/BP = new /obj/item/stack/medical/bruise_pack(src.loc)
			BP.set_amount(1, TRUE)
			BP.max_amount = 1

	if(problems & SERIOUS_EXTERNAL_DAMAGE)
		problem_text += "<br>" + span_danger("SEVERITY: 'SEVERE' - Severe external damage detected - seek medical attention immediately!")
		if(able_to_dispense)
			medication_dispensed = TRUE
			var/obj/item/stack/medical/bruise_pack/BP = new /obj/item/stack/medical/bruise_pack(src.loc)
			BP.set_amount(1, TRUE)
			BP.max_amount = 1
			var/obj/item/stack/medical/ointment/ointment = new /obj/item/stack/medical/ointment(src.loc)
			ointment.set_amount(1, TRUE)
			ointment.max_amount = 1
			if(!paracetamol_given)
				new /obj/item/reagent_containers/pill/small_paracetamol(src.loc)
				paracetamol_given = TRUE

	if(problems & ALCOHOL_POISONING)
		problem_text += "<br>" + span_danger("SEVERITY: 'SEVERE' - Severe alcohol poisoning detected - seek medical attention immediately!")
	//We could be nice and give a pill of ethylredoxrazine, but remember, this is meant to stabilize until they get medical attention, not fix them!
	//And given that alcohol poisoning will ALWAYS cause liver damage, it means the internal damage below this will /always/ proc. So we put it above it!

	if(problems & SERIOUS_INTERNAL_DAMAGE)
		problem_text += "<br>" + span_danger("SEVERITY: 'SEVERE' - Severe internal damage detected - seek medical attention immediately!")
		if(able_to_dispense && !paracetamol_given)
			medication_dispensed = TRUE
			new /obj/item/reagent_containers/pill/small_paracetamol(src.loc)
	else if(problems & INTERNAL_DAMAGE) //This isn't TOO major. All internal damage (as long as it's not severe, which would trigger 'SERIOUS_INTERNAL_DAMAGE') is survivable and not lethal, but is annoying. (ex: Lung damage causing you to constantly cough up blood)
		problem_text += "<br>" + span_warning("SEVERITY: 'MODERATE' - Internal damage detected - seek out medical attention at soonest convinence, or urgently if severe symptoms are occurring.")

	if(problems & BROKEN_BONES)
		problem_text += "<br>" + span_warning("SEVERITY: 'MODERATE' - Broken bones detected - see a medical professional and move as little as possible.")
		if(able_to_dispense && !tramadol_given)
			medication_dispensed = TRUE
			new /obj/item/reagent_containers/pill/small_tramadol(src.loc)
			tramadol_given = TRUE

	if(problems & BLOODLOSS)
		problem_text += "<br>" + span_warning("SEVERITY: 'MODERATE' - Indeterminate amount of blood loss detected. If symptoms are severe, please seek medical attention.")
		if(able_to_dispense)
			medication_dispensed = TRUE
			new /obj/item/reagent_containers/pill/small_blood_restoration(src.loc)

	if(problems & VIRUS)
		problem_text += "<br>" + span_boldwarning("SEVERITY: 'VARIES' - Viral illness detected - seek out medical attention and quarantine from others!")
	//Nothin. Get to medical! Technically COULD give spaceacillin, but this is only meant to help you get TO medical, not REPLACE medical.

	if(problems & ACUTE_RADIATION_DOSE)
		problem_text += "<br>" + span_boldwarning("SEVERITY: 'VARIES' - Acute exposure to ionizing radiation detected - seek medical attention.")
		if(able_to_dispense)
			medication_dispensed = TRUE
			new /obj/item/reagent_containers/pill/small_prussian_blue(src.loc)
	else if(problems & CHRONIC_RADIATION_DOSE) //We don't care about telling them about chronic rads if they have acute rads!
		problem_text += "<br>" + span_warning("SEVERITY: 'LOW' - Chronic Exposure to ionizing radiation detected - medical attention is advised.")
	//Nothing. It's acute. Sorry!

	if(problems & CLONE_DAMAGE)
		problem_text += "<br>" + span_warning("SEVERITY: 'LOW' - Exposure to genetic damage detected - medical treatment recommended.")
	//Nothing!
	if(problems & TOXIN_DAMAGE)
		problem_text += "<br>" + span_warning("SEVERITY: 'LOW' - Exposure to toxic materials detected - if severe, seek medical attention. If mild, drinking tea is suggested.") //Let people know about the secret 'drink tea to decrease toxins' technique.
		if(able_to_dispense)
			medication_dispensed = TRUE
			new /obj/item/reagent_containers/pill/small_dylovene(src.loc)
	if(problems & OXY_DAMAGE) //Honestly this will never happen. And if it is, you are probably going to get KO'd before this finishes.
		problem_text += "<br>" + span_warning("SEVERITY: 'LOW' - Blood/air perfusion level is below acceptable norms - use concentrated oxygen if necessary.")
		if(able_to_dispense & !inaprovaline_given)
			medication_dispensed = TRUE
			new /obj/item/reagent_containers/pill/small_inaprovaline(src.loc)
			inaprovaline_given = TRUE
	// begin malignants
	if(problems & WEIRD_ORGANS)
		problem_text += "<br>" + span_warning("Anatomical irregularities detected - Please see a medical professional.")
	// end
	if(problems & HUSKED_BODY)
		problem_text += "<br>" + span_danger("SEVERITY: 'Minor' - Anatomical structure lost, resuscitation not possible!") //Only borers will ever see this.
	//thoughts and prayers
	if(problems & ORGAN_DISLOCATED)
		problem_text += "<br>" + span_warning("SEVERITY: 'Minor' - Limb dislocation detected. Relocating limb recommended.")
		if(able_to_dispense && !paracetamol_given)
			medication_dispensed = TRUE
			new /obj/item/reagent_containers/pill/small_paracetamol(src.loc)

	if(medication_dispensed) //We found something and can dispense meds!
		COOLDOWN_START(src, dispense_cooldown_until, dispense_cooldown)
		problem_text += "<br>" + span_cyan("Condition has been analyzed and supplies have been dispensed. Please take any dispensed items to help stabilize your condition until medical personnel can see you!")

	return problem_text

/obj/machinery/medical_kiosk/proc/do_backup_scan(mob/living/carbon/human/user)
	if(!istype(user))
		return "<br>" + span_warning("Unable to perform full scan. Please see a medical professional.")
	if(!user.mind)
		return "<br>" + span_warning("Unable to perform full scan. Please see a medical professional.")
	if(istype(get_area(src), /area/vr))
		return "<br>" + span_danger("Incompatible database configuration error: A Transcore Mind and Body Resource Management server could not be detected.")

	var/nif = user.nif
	if(nif)
		persist_nif_data(user)

	our_db().m_backup(user.mind,nif,one_time = TRUE)
	var/datum/transhuman/body_record/BR = new()
	BR.init_from_mob(user, TRUE, TRUE, database_key = db_key)

	return "<br>" + span_notice("Backup scan completed!") + "<br>" + span_bold("Note:") + " A backup implant is required for automated notifications to the appropriate department in case of incident."

#undef BROKEN_BONES
#undef INTERNAL_BLEEDING
#undef EXTERNAL_BLEEDING
#undef SERIOUS_EXTERNAL_DAMAGE
#undef SERIOUS_INTERNAL_DAMAGE
#undef ACUTE_RADIATION_DOSE
#undef CHRONIC_RADIATION_DOSE
#undef TOXIN_DAMAGE
#undef OXY_DAMAGE
#undef HUSKED_BODY
#undef INFECTION
#undef VIRUS
#undef INTERNAL_DAMAGE
#undef CLONE_DAMAGE
#undef ORGAN_DISLOCATED
#undef ALCOHOL_POISONING
#undef BLOODLOSS
#undef WEIRD_ORGANS // malignants

/// LC-refs: the transcore database this uses, looked up by db_key (the databases are a registry).
/obj/machinery/medical_kiosk/proc/our_db() as /datum/transcore_db
	return SStranscore.db_by_key(db_key)

/// active user (a relation view: it reads null once the target is deleted).
/obj/machinery/medical_kiosk/proc/active_user() as /mob/living
	return active_user
