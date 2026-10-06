/datum/power/changeling/fake_death
	name = "Regenerative Stasis"
	desc = "We become weakened to a death-like state, where we will rise again from death."
	helptext = "Can be used before or after death. Duration varies greatly."
	ability_icon_state = "ling_regenerative_stasis"
	genomecost = 0
	allowduringlesserform = TRUE
	verbpath = /mob/proc/changeling_fakedeath

//Fake our own death and fully heal. You will appear to be dead but regenerate fully after a short delay.
/mob/proc/changeling_fakedeath()
	set category = VERB_CAT_CHANGELING
	set name = "Regenerative Stasis (20)"

	return changeling_fakedeath_stage()

/mob/proc/changeling_fakedeath_stage(selected_answer, selected_ready = FALSE)

	var/datum/changeling/changeling = changeling_power(CHANGELING_STASIS_COST,1,100,DEAD)
	if(!changeling)
		return

	var/mob/living/carbon/C = src

	if(changeling.max_geneticpoints < 0) //Absorbed by another ling
		to_chat(src, span_danger("We have no genomes, not even our own, and cannot regenerate."))
		return 0

	if(!selected_ready)
		open_request(src, /datum/prompt/choice, PROC_REF(changeling_fakedeath_answered), answerer = src, question = "Are we sure we wish to regenerate? We will appear to be dead while doing so.", title = "Revival", choices = list("Yes","No"), buttons = TRUE, timeout = 0)
		return
	var/_answer_a1 = selected_answer
	if(isnull(_answer_a1))
		return
	if(!C.stat && _answer_a1 != "Yes")
		return

	C.update_canmove()
	changeling.chem_charges -= CHANGELING_STASIS_COST

	if(C.suiciding)
		C.suiciding = FALSE

	C.set_does_not_breathe(FALSE)	//This means they don't autoheal the oxy damage from the next step

	if(C.stat != DEAD)
		C.add_oxygen_debt(PHYSIOLOGY_DEBT_MAX, "changeling fake death")

	C.forbid_seeing_deadchat = TRUE

	var/resurrection_time = rand(2 MINUTES, 4 MINUTES)
	changeling.set_cooldown(FAKE_DEATH, resurrection_time)
	changeling.is_reviving = TRUE
	to_chat(C, span_notice("We will attempt to regenerate our form. This will take [(changeling.get_cooldown(FAKE_DEATH) - world.time)/600] minutes."))
	after(src, resurrection_time, PROC_REF(finish_changeling_revive))
	feedback_add_details("changeling_powers","FD")
	return 1

/mob/proc/finish_changeling_revive()
	//Lets the ling know it's revive time.
	to_chat(src, span_notice(span_giant("We are ready to rise.  Use the <b>Revive</b> verb when you are ready.")))

/mob/proc/changeling_fakedeath_answered(datum/act/request/context)
	if(!context.answer)
		return
	// The old kept replay refreshes windows even if its effect faults.
	. = changeling_fakedeath_stage(context.answer.value, TRUE)
	SStgui.update_uis(src)
