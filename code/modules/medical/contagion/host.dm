// Contagions on a host: the mob-facing API and the body's lasting immunities.
//
// The old per-mob `viruses` / `resistances` lists are gone: a mob's diseases
// are the /datum/affliction/contagion afflictions its body owns, and lasting
// immunity (from a cured or cleared disease, or antibodies in donated blood)
// is `body.contagion_immunities`, keyed by GetDiseaseID().
//
// Queries are declared on /mob (answering "none") so code holding a plain mob
// reference can ask; living mobs answer from their body.

/datum/body
	/// GetDiseaseID() strings this body is immune to. Lazy.
	var/list/contagion_immunities

/datum/body/proc/add_contagion_immunity(id)
	if(isnull(id))
		return FALSE
	if(ispath(id))
		id = "[id]"
	LAZYOR(contagion_immunities, id)
	return TRUE

/datum/body/proc/has_contagion_immunity(id)
	if(isnull(id))
		return FALSE
	if(ispath(id))
		id = "[id]"
	return !!LAZYFIND(contagion_immunities, id)

/// Every contagion this body carries (a new list; safe to cure while walking).
/datum/body/proc/contagions()
	. = list()
	for(var/datum/affliction/A as anything in afflictions)
		if(istype(A, /datum/affliction/contagion))
			. += A


// --- Queries ----------------------------------------------------------------------

/// Contagions this mob carries (a new list).
/mob/proc/get_contagions()
	return list()

/mob/living/get_contagions()
	return body ? body.contagions() : list()

/// Does this mob carry `D` (a contagion typepath or an instance: same strain)?
/mob/proc/has_contagion(D)
	return FALSE

/mob/living/has_contagion(D)
	for(var/datum/affliction/contagion/C as anything in get_contagions())
		if(C.IsSame(D))
			return TRUE
	return FALSE

/mob/proc/has_contagions()
	return FALSE

/mob/living/has_contagions()
	for(var/datum/affliction/A as anything in body?.afflictions)
		if(istype(A, /datum/affliction/contagion))
			return TRUE
	return FALSE

/// Contagions that can pass on (not special, not non-contagious, not dormant).
/mob/proc/get_spreadable_contagions()
	return list()

/mob/living/get_spreadable_contagions()
	. = list()
	for(var/datum/affliction/contagion/D as anything in get_contagions())
		if(!D.is_spreadable() || global_flag_check(D.virus_modifiers, DORMANT))
			continue
		. += D

/mob/proc/is_infective()
	return FALSE

/mob/living/is_infective()
	return length(get_spreadable_contagions()) > 0

/// Contagions that are not dormant.
/mob/proc/get_active_contagions()
	return list()

/mob/living/get_active_contagions()
	. = list()
	for(var/datum/affliction/contagion/D as anything in get_contagions())
		if(!global_flag_check(D.virus_modifiers, DORMANT))
			. += D

/mob/proc/get_contagion_immunities()
	return list()

/mob/living/get_contagion_immunities()
	return body?.contagion_immunities ? body.contagion_immunities.Copy() : list()

/mob/proc/add_contagion_immunities(list/ids)
	return FALSE

/mob/living/add_contagion_immunities(list/ids)
	if(!body)
		return FALSE
	if(!islist(ids))
		ids = list(ids)
	for(var/id in ids)
		body.add_contagion_immunity(id)
	return TRUE

/mob/proc/has_contagion_immunity(id)
	return FALSE

/mob/living/has_contagion_immunity(id)
	return body ? body.has_contagion_immunity(id) : FALSE

/// The worst danger level among scanner-visible contagions (DISEASE_* string).
/mob/proc/contagion_threat()
	return null

/mob/living/contagion_threat()
	var/threat
	var/danger
	for(var/datum/affliction/contagion/disease as anything in get_contagions())
		if(disease.visibility_flags & HIDDEN_SCANNER)
			continue
		var/value = get_disease_danger_value(disease.danger)
		if(!threat || value > threat)
			threat = value
			danger = disease.danger
	return danger

/// A discovered, scanner-visible, non-trivial contagion (medical HUD "ill").
/mob/proc/has_known_contagion()
	return FALSE

/mob/living/has_known_contagion()
	for(var/datum/affliction/contagion/D as anything in get_contagions())
		if(!global_flag_check(D.virus_modifiers, DISCOVERED))
			continue
		if(!(D.visibility_flags & HIDDEN_SCANNER) && D.danger != DISEASE_NONTHREAT)
			return TRUE
	return FALSE

/// Detached copies of `contagions`, for carriers outside a body (blood,
/// vomit, syringes): never hold a body's own affliction.
/proc/contagion_copies(list/contagions)
	. = list()
	for(var/datum/affliction/contagion/D as anything in contagions)
		. += D.Copy()

/mob/living/proc/CanSpreadAirborneDisease()
	return !is_mouth_covered()


// --- Contracting ------------------------------------------------------------------

/// Can `D` take hold in this mob at all (ignoring exposure and protection)?
/mob/proc/can_contract_contagion(datum/affliction/contagion/D)
	return FALSE

/mob/living/can_contract_contagion(datum/affliction/contagion/D)
	if(!body || !D)
		return FALSE
	if(stat == DEAD && !global_flag_check(D.virus_modifiers, SPREAD_DEAD))
		return FALSE
	if(body.has_contagion_immunity(D.GetDiseaseID()))
		return FALSE
	if(has_contagion(D))
		return FALSE
	if(!D.can_afflict(body, null))
		return FALSE
	return TRUE

/// Humans: species immune to viruses become carriers instead (unless the
/// strain bypasses immunity).
/mob/living/carbon/human/can_contract_contagion(datum/affliction/contagion/D)
	if(!..())
		return FALSE
	if(species?.virus_immune && !global_flag_check(D.virus_modifiers, BYPASSES_IMMUNITY))
		D.set_virus_modifiers(D.virus_modifiers | CARRIER)
	else
		D.set_virus_modifiers(D.virus_modifiers & ~CARRIER)
	return TRUE

/// Exposure through the environment (contact, a splash, a sneeze): clothing
/// and species protection apply. See /datum/affliction_trigger/contagion.
/mob/proc/expose_contagion(datum/affliction/contagion/D, target_zone)
	return FALSE

/mob/living/expose_contagion(datum/affliction/contagion/D, target_zone)
	var/datum/affliction_trigger/contagion/trigger = contagion_trigger()
	return trigger.expose(src, D, CONTAGION_ROUTE_CONTACT, target_zone)

/// Direct infection (injection, ingestion, admin): no protection applies.
/mob/proc/force_contagion(datum/affliction/contagion/D, respect_carrier)
	return FALSE

/mob/living/force_contagion(datum/affliction/contagion/D, respect_carrier)
	if(!can_contract_contagion(D))
		return FALSE
	return !!D.try_infect(src, TRUE)


ADMIN_VERB(ReleaseVirus, R_SPAWN|R_EVENT, "Release Virus", "Release a pre-set virus.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/list/choices = list()
	for(var/path in subtypesof(/datum/affliction/contagion))
		var/datum/affliction/contagion/proto = path
		if(!initial(proto.max_stages))
			continue
		choices += path
	var/disease = verb_ask(user, "k247", args, /datum/om/prompt/choice, message = "Choose virus", title = "Viruses", choices = choices)

	if(isnull(disease))
		return FALSE

	var/mob/living/carbon/human/H = verb_ask(user, "k252", args, /datum/om/prompt/choice, message = "Choose infectee", title = "Characters", choices = REGISTRY_MEMBERS(REGISTRY_HUMANS))

	if(isnull(H))
		return FALSE

	var/datum/affliction/contagion/D = new disease

	if(!H.has_contagion(D) && H.force_contagion(D))
		message_admins("[key_name_admin(user)] has triggered a virus outbreak of [D.name]! Affected mob: [key_name_admin(H)]")
		log_admin("[key_name_admin(user)] infected [key_name_admin(H)] with [D.name]")

		if(!GLOB.archive_diseases[D.GetDiseaseID()])
			GLOB.archive_diseases[D.GetDiseaseID()] = D
			return TRUE

/// Admin debug: every contagion on a mob, with stage, immunity and flags.
ADMIN_VERB_AND_CONTEXT_MENU(DebugContagions, R_DEBUG, "Debug Contagions", "Show a mob's contagions, their stage and the host immune response.", ADMIN_CATEGORY_DEBUG, mob/living/L in REGISTRY_MEMBERS(REGISTRY_MOBS))
	if(!istype(L))
		return
	var/list/lines = list("<b>Contagions on [key_name(L)]</b>")
	for(var/datum/affliction/contagion/D as anything in L.get_contagions())
		lines += "[D.name] ([D.type]): stage [D.stage]/[D.max_stages], severity [D.severity], immunity [round(D.immunity, 0.1)]/[CONTAGION_IMMUNITY_CLEAR], spread [D.spread_flags], modifiers [D.virus_modifiers], lane [D.periodic_pipe || "parked"]"
	lines += "Immunities: [english_list(L.get_contagion_immunities(), "none")]"
	to_chat(user, jointext(lines, "<br>"))
