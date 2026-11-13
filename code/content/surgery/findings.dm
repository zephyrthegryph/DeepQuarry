// Surgical findings: what an opened limb shows.
//
// Surgery has two fixed bookends, opening a site (incise, retract, and saw and pry where the limb is encased) and closing it
// (set the bone layer, cauterize; the hatch on a prosthesis). Everything between is decided by what is actually in the limb.
// Opening it reveals its findings: every affliction, embedded object, crooked bone, growth or inflamed organ there that some
// surgical step answers to. The surgeon picks the step that fits each finding, in any order, then closes.
//
// A finding is never stored. Each step says what it answers to in a limb (`findings()` in surgery.dm, overridden where the
// finding is not an affliction that lists the step's treatment tag), and `surgical_findings()` collects the rows, merging the
// steps that answer to the same thing. The surgeon reads them by inspecting the opened limb (the grab inspection) and on the operating
// computer; the medical book lists the same steps from the same data.

/// One finding row: its name, where it is (the limb or an organ), the thing itself (an affliction, an object or an organ) and
/// the steps that answer to it (the list grows as steps that answer to the same source are merged in).
/proc/surgical_finding_row(name, atom/location, source, datum/surgical_step/step)
	return list("name" = name, "where" = location, "source" = source, "steps" = list(step))

/// The findings in `part` for the surgeon: empty while it is not open far enough to see into (flesh retracted); organs show once
/// the limb is open to its organs. One row per source, with every step that answers to it.
/proc/surgical_findings(mob/living/carbon/human/target, obj/item/organ/external/part)
	. = list()
	if(!istype(target) || !target.body || QDELETED(part) || part.owner != target)
		return
	var/depth = part.surgical_depth()
	if(depth < FLESH_RETRACTED)
		return
	var/full = depth >= part.surgical_full_access()
	var/list/by_source = list()
	for(var/datum/surgical_step/S as anything in surgical_steps())
		for(var/list/row as anything in S.findings(target, part, full))
			var/list/known = by_source[row["source"]]
			if(known)
				known["steps"] |= row["steps"]
				continue
			by_source[row["source"]] = row
			. += list(row)

/// Plain-language line for a finding: what it is, where, and which steps answer to it.
/proc/surgical_finding_text(list/row)
	var/atom/location = row["where"]
	var/list/step_names = list()
	for(var/datum/surgical_step/S as anything in row["steps"])
		step_names += S.name
	return "[capitalize(row["name"])] ([location]): [english_list(step_names)]"

/// What a hands-on inspection of an opened limb adds to what it finds (the grab inspection, mob_grab_specials.dm): the state
/// of the site, then each finding with the steps that answer to it, most urgent first. Empty while the limb is not open far
/// enough to see into.
/proc/surgical_inspection_lines(mob/living/carbon/human/target, obj/item/organ/external/part)
	. = list()
	if(!istype(target) || QDELETED(part) || part.surgical_depth() < FLESH_RETRACTED)
		return
	. += "The open site in the [part.name]: [part.surgery_state_text()]."
	var/list/rows = surgical_findings(target, part)
	if(!length(rows))
		. += "Nothing in here needs surgery."
		return
	for(var/list/row as anything in rows)
		. += surgical_finding_text(row)

/// A site has just been opened far enough to see inside: what is there is logged. The surgeon reads it by inspecting the limb.
/mob/living/carbon/human/proc/reveal_surgical_findings(mob/living/user, obj/item/organ/external/part)
	var/list/names = list()
	for(var/list/row as anything in surgical_findings(src, part))
		names += "[row["name"]] ([row["where"]])"
	log_game("SURGERY: findings revealed on [key_name(src)] [part] for [key_name(user)]: [length(names) ? english_list(names) : "nothing"]")
