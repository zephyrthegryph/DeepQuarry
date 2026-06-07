// Strip-down of the upstream health analyzer.
//
// The upstream /obj/item/healthanalyzer/scan_mob() emits a fully
// detailed readout: per-organ damage numbers, every reagent by name,
// germ-level "cellulitis/necrosis" labels, internal-bleeding location
// + severity, defib viability prediction, etc. With the cascading-
// conditions system in place, that's far too much information — it's
// the equivalent of every patient handing the doctor a complete chart.
//
// We replace scan_mob() at the proc level. That intercepts EVERY
// caller — the handheld /attack, PDA scanner mode, the sleevemate,
// dog_sleeper, bio-augment, surgery do_surgery — none of them need
// per-call edits. They all go through this one entry point now.
//
// The original scan_mob() body is dropped. If anything ever needs
// the full upstream readout (admin debug, autopsy report), it can
// call /proc/dq_full_scan_readout() which is still there.

/obj/item/healthanalyzer/scan_mob(mob/living/M, mob/living/user)
	if(!user)
		return
	if(CLUMSY_FAIL_CHANCE(user))
		user.visible_message(
			span_warning("\The [user] has analyzed the floor's vitals!"),
			span_warning("You try to analyze the floor's vitals!"),
		)
		to_chat(user, span_notice("Subject: floor. Status: not alive."))
		return
	if(!user.IsAdvancedToolUser())
		to_chat(user, span_warning("You don't have the dexterity to do this!"))
		return
	flick("[icon_state]-scan", src)
	user.visible_message(
		span_notice("[user] has run \the [src] over [M]."),
		span_notice("You have run \the [src] over [M]."),
	)
	to_chat(user, dq_crude_scan_readout(M))

/// Build the limited readout string. Aliveness, gross injury level,
/// nothing more. We intentionally omit damage type breakdowns, named
/// reagents, organ-level breakdowns, IB location, and defib viability
/// — those require real instruments or a body scanner that has
/// diagnosed specific conditions.
/proc/dq_crude_scan_readout(mob/living/M)
	if(!ishuman(M))
		return span_notice("Subject: [M]. Reading not interpretable.")
	var/mob/living/carbon/human/H = M
	var/list/lines = list()
	lines += "<b>Subject:</b> [H]"
	if(H.stat == DEAD)
		lines += "<b>Status:</b> [span_danger("not breathing, no detectable signs of life")]"
	else if(H.stat == UNCONSCIOUS)
		lines += "<b>Status:</b> [span_warning("unresponsive")]"
	else
		lines += "<b>Status:</b> conscious"
	var/total = H.getBruteLoss() + H.getFireLoss()
	var/injury_band
	if(total <= 0)
		injury_band = "no visible trauma"
	else if(total < 25)
		injury_band = "mild visible trauma"
	else if(total < 60)
		injury_band = "moderate visible trauma"
	else if(total < 100)
		injury_band = "severe visible trauma"
	else
		injury_band = "catastrophic visible trauma"
	lines += "<b>Visible trauma:</b> [injury_band]"
	var/r_count = 0
	if(H.reagents)
		r_count += length(H.reagents.reagent_list)
	if(H.bloodstr)
		r_count += length(H.bloodstr.reagent_list)
	if(r_count)
		lines += "<b>Bloodstream:</b> [r_count] foreign substance\s detected; unable to identify"
	return span_notice(jointext(lines, "<br>"))
