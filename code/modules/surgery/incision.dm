// The open surgical site: access state as an affliction on the limb.
//
// Access steps create it (body.afflict()) and deepen it (open_to()). Its
// depth is the single source of truth for how far a limb is open; the limb's
// `open` var only caches it for icons, examine and scanners. While open it:
//  - bleeds (organic parts, until clamped with TREAT_HEMOSTATIC): the limb's
//    ORGAN_BLEEDING comes from is_bleeding() in update_damages();
//  - gathers germs every tick in proportion to depth and the sterility of
//    the surface it was opened on (infection risk until closed);
//  - hurts (severity per depth).
// It is closed by treatment like any other affliction:
//  - TREAT_BONE_SETTING closes a sawn bone layer back to retracted flesh;
//  - TREAT_SURGICAL_CLOSURE (organic) / TREAT_PANEL_CLOSURE (synthetic)
//    closes the rest, once no bone layer is open;
//  - TREAT_RESTORATION closes everything.
// It never closes on its own and doesn't progress in severity.

/datum/affliction/surgical_incision
	name = "surgical incision"
	category = "Surgical"
	catalogued = FALSE
	clinical_description = "An open surgical site. It bleeds until the vessels are clamped and gathers infection until it is closed."
	biology = BIOLOGY_ALL
	body_plans = BODY_PLAN_HUMANOID
	injury_category = null
	progression_rate = 0
	severity_per_injury = 0
	pain_at_max = 40
	min_symptoms = 0
	max_symptoms = 0
	restoration_rate = 1
	treated_by = list(
		TREAT_SURGICAL_CLOSURE = 1,
		TREAT_PANEL_CLOSURE = 1,
		TREAT_BONE_SETTING = 1,
		TREAT_HEMOSTATIC = 1,
	)
	/// Access depth (INCISION_MADE .. BONE_RETRACTED).
	var/depth = SURGERY_DEPTH_CLOSED
	/// The site's bleeders are clamped.
	var/clamped = FALSE
	/// Cleanliness (0-100) of the surface the site was opened on.
	var/sterility = 100

/datum/affliction/surgical_incision/on_added()
	. = ..()
	sync()

/datum/affliction/surgical_incision/on_removed()
	. = ..()
	var/obj/item/organ/external/E = location
	if(istype(E))
		E.open = SURGERY_DEPTH_CLOSED
		E.owner?.update_surgery()

/// Open (or re-open) the site to `new_depth`. `site_sterility` is the
/// cleanliness of the surface; the site keeps the dirtiest it has seen.
/datum/affliction/surgical_incision/proc/open_to(new_depth, site_sterility = 100)
	depth = new_depth
	sterility = min(sterility, site_sterility)
	log_game("SURGERY: incision on [key_name(owner)] [location] opened to depth [depth] (sterility [sterility])")
	sync()

/// Push depth into severity and the limb's cache.
/datum/affliction/surgical_incision/proc/sync()
	set_severity(depth * INCISION_SEVERITY_PER_DEPTH)
	var/obj/item/organ/external/E = location
	if(istype(E))
		E.open = depth
		E.owner?.update_surgery()

/// Does the open site bleed? Organic parts of bodies with blood, unclamped.
/datum/affliction/surgical_incision/proc/is_bleeding()
	if(depth <= SURGERY_DEPTH_CLOSED || clamped || !body)
		return FALSE
	if(!(body.biology_of(location) & BIOLOGY_ORGANIC))
		return FALSE
	var/mob/living/carbon/human/H = owner
	return istype(H) && H.should_have_organ(O_HEART) && !(H.species?.flags & NO_BLOOD)

/// Close the site entirely.
/datum/affliction/surgical_incision/proc/close_site()
	log_game("SURGERY: incision on [key_name(owner)] [location] closed")
	depth = SURGERY_DEPTH_CLOSED
	cure()

/// Surgical sites answer only to instant (procedure) treatment: a hemostatic
/// drug doesn't clamp a vessel and nothing closes a wound by itself.
/datum/affliction/surgical_incision/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(amount <= 0)
		return 0
	if(tag == TREAT_RESTORATION)
		close_site()
		return amount
	if(continuous)
		return 0
	switch(tag)
		if(TREAT_HEMOSTATIC)
			if(clamped)
				return 0
			clamped = TRUE
			return amount
		if(TREAT_BONE_SETTING)
			if(depth <= FLESH_RETRACTED)
				return 0
			depth = FLESH_RETRACTED
			sync()
			return amount
		if(TREAT_SURGICAL_CLOSURE, TREAT_PANEL_CLOSURE)
			if(depth > FLESH_RETRACTED)
				return 0 // the bone layer has to be set first
			close_site()
			return amount
	return 0

/// Open, unclamped bleeders for a hemostat.
/datum/affliction/surgical_incision/proc/needs_clamp()
	return !clamped && is_bleeding()

/// A sawn bone layer is open.
/datum/affliction/surgical_incision/proc/needs_bone_setting()
	return depth > FLESH_RETRACTED

/// Nothing but soft tissue (or a panel) left to close.
/datum/affliction/surgical_incision/proc/can_close()
	return depth > SURGERY_DEPTH_CLOSED && depth <= FLESH_RETRACTED

/// The open site doesn't heal or worsen; it gathers germs until closed.
/datum/affliction/surgical_incision/progress()
	pending_treatment = 0
	if(depth <= SURGERY_DEPTH_CLOSED)
		return
	if(!(body.biology_of(location) & BIOLOGY_ORGANIC))
		return
	var/obj/item/organ/external/E = location
	if(!istype(E))
		return
	var/germs = INCISION_GERMS_PER_DEPTH * depth * (100 - sterility) / 100
	if(germs > 0)
		E.adjust_germ_level(germs)

/// Detached limbs keep their open site as it was.
/datum/affliction/surgical_incision/tick_offline()
	return


// --- Limb helpers ------------------------------------------------------------------------

/// This limb's open surgical site, if any.
/obj/item/organ/external/proc/get_incision()
	for(var/datum/affliction/surgical_incision/I in afflictions_here())
		return I
	return null

/// Current access depth (SURGERY_DEPTH_CLOSED .. BONE_RETRACTED).
/obj/item/organ/external/proc/surgical_depth()
	var/datum/affliction/surgical_incision/I = get_incision()
	return I ? I.depth : SURGERY_DEPTH_CLOSED

/// The depth at which this limb's interior is reachable.
/obj/item/organ/external/proc/surgical_full_access()
	return (encased && !(robotic >= ORGAN_ROBOT)) ? BONE_RETRACTED : FLESH_RETRACTED

/// Open the surgical site on this limb to `depth`. Creates the incision.
/obj/item/organ/external/proc/open_surgical_site(depth, sterility = 100)
	if(!owner?.body)
		return null
	var/datum/affliction/surgical_incision/I = owner.body.afflict(/datum/affliction/surgical_incision, src)
	I?.open_to(depth, sterility)
	return I

/// Plain-language state of the surgical site (operating computer, examine).
/obj/item/organ/external/proc/surgery_state_text()
	var/datum/affliction/surgical_incision/I = get_incision()
	if(!I)
		return "None."
	var/synthetic = !(owner?.body?.biology_of(src) & BIOLOGY_ORGANIC)
	var/text
	switch(I.depth)
		if(INCISION_MADE)
			text = synthetic ? "Panel unscrewed." : "Incision made."
		if(FLESH_RETRACTED)
			text = synthetic ? "Maintenance hatch open." : "Surgical site opened."
		if(BONE_CUT)
			text = "Bones cut."
		if(BONE_RETRACTED)
			text = "Bones retracted."
		else
			text = "None."
	if(I.is_bleeding())
		text += " Bleeding."
	return text
