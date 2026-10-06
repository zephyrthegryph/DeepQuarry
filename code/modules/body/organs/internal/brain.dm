REGISTRY_MEMBERSHIP(/obj/item/organ/internal/brain, REGISTRY_BRAIN_ORGANS)

/obj/item/organ/internal/brain
	name = "brain"
	desc = "A piece of juicy meat found in a person's head."
	organ_tag = O_BRAIN
	parent_organ = BP_HEAD
	vital = TRUE
	icon_state = "brain2"
	force = 1.0
	w_class = ITEMSIZE_SMALL
	throwforce = 1.0
	throw_speed = 3
	throw_range = 5
	attack_verb = list("attacked", "slapped", "whacked")
	var/clone_source = FALSE
	var/can_assist = TRUE
	/// Biological time the defibrillation window has run down, deciseconds (audit D10). Read it
	/// through defib_window_left(); sync_defib_window() charges it on the body clock.
	var/defib_elapsed = 0
	/// om_clock_now(CLOCK_BIO) of the last sync, or null before the first.
	var/tmp/defib_clock_at
	/// Whether that reading came from the owner's clock (TRUE) or the loose brain's own.
	var/tmp/defib_clock_on_owner = FALSE
	/// Whether the window was running down (dead or loose, not preserved) since the last sync.
	var/tmp/defib_decaying = FALSE

/// Fraction of max_damage below which a brain still recovers on its own
/// (natural regeneration). Above it the brain needs neural repair; past the
/// salvage band it swells (see lesions.dm).
#define BRAIN_NATURAL_HEAL_FRACTION 0.2

/obj/item/organ/internal/brain/natural_heal_ceiling()
	return max_damage * BRAIN_NATURAL_HEAL_FRACTION

#undef BRAIN_NATURAL_HEAL_FRACTION

/// The whole defibrillation window, deciseconds of biological time (config minutes).
/proc/defib_window_length()
	return CONFIG_GET(number/defib_timer) MINUTES

/// The last part of the window, deciseconds, in which a revival costs brain damage.
/proc/defib_braindamage_length()
	return min(defib_window_length(), CONFIG_GET(number/defib_braindamage_timer) MINUTES)

/// Charge the defib window for the biological time since the last sync: it runs down while the
/// brain is dead or loose (unless preserved) and recovers while its owner lives. Time is read
/// from the owner's CLOCK_BIO (stasis stops it) or, loose, the brain's own. Idempotent, so any
/// reader may call it; death, revival, removal and insertion call it at the transition.
/obj/item/organ/internal/brain/proc/sync_defib_window()
	var/on_owner = !!owner
	var/now = om_clock_now(owner || src, CLOCK_BIO)
	if(!isnull(defib_clock_at) && on_owner == defib_clock_on_owner && now > defib_clock_at)
		var/span = now - defib_clock_at
		if(defib_decaying)
			defib_elapsed = min(defib_window_length(), defib_elapsed + span)
		else
			defib_elapsed = max(0, defib_elapsed - span)
	defib_clock_at = now
	defib_clock_on_owner = on_owner
	defib_decaying = !preserved && (!owner || owner.is_dead())

/// Deciseconds of biological time left before this brain decays past revival.
/obj/item/organ/internal/brain/proc/defib_window_left()
	sync_defib_window()
	return max(0, defib_window_length() - defib_elapsed)

/// A fresh window (revival restore, a new brain).
/obj/item/organ/internal/brain/proc/reset_defib_window()
	defib_elapsed = 0
	defib_clock_at = null
	sync_defib_window()

/// Close the window outright.
/obj/item/organ/internal/brain/proc/expire_defib_window()
	defib_elapsed = defib_window_length()
	defib_clock_at = null
	sync_defib_window()

/// Neural injury a revival now should leave (CPR and defib share it): none while more than the
/// brain-damage stretch of the window is left, rising linearly to max_damage as it closes.
/obj/item/organ/internal/brain/proc/revival_brain_damage(current_neural)
	var/stretch = defib_braindamage_length()
	var/left = defib_window_left()
	if(stretch <= 0 || left >= stretch)
		return 0
	// 1 = fresh, 0 = gone.
	var/freshness = left / stretch
	var/target = LERP(max_damage, current_neural, freshness)
	return max(0, between(current_neural, target, max_damage) - current_neural)

/obj/item/organ/internal/brain/proc/can_assist()
	return can_assist

/obj/item/organ/internal/brain/proc/implant_assist(targ_icon_state = null)
	name = "[owner.real_name]'s assisted [initial(name)]"
	if(targ_icon_state)
		icon_state = targ_icon_state
		if(dead_icon)
			dead_icon = "[targ_icon_state]_dead"
	else
		icon_state = "[initial(icon_state)]_assisted"
	if(dead_icon)
		dead_icon = "[initial(dead_icon)]_assisted"

/obj/item/organ/internal/brain/robotize()
	replace_self_with(/obj/item/organ/internal/mmi_holder/posibrain)

/obj/item/organ/internal/brain/mechassist()
	replace_self_with(/obj/item/organ/internal/mmi_holder)

/obj/item/organ/internal/brain/digitize()
	replace_self_with(/obj/item/organ/internal/mmi_holder/robot)

/obj/item/organ/internal/brain/handle_germ_effects(cycles)
	. = ..() //Up should return an infection level as an integer
	if(!.) return

	//Bacterial meningitis (more of a spine thing but 'brain infection' isn't a common thing)
	if (. >= 1)
		if(prob(1))
			owner.custom_pain("Your neck aches, and feels very stiff!",0)
	if (. >= 2)
		if(prob(1))
			owner.custom_pain("Your feel very dizzy for a moment!",0)
			owner.status_at_least(STAT_CONFUSED, 2)

/obj/item/organ/internal/brain/proc/replace_self_with(replace_path)
	var/mob/living/carbon/human/tmp_owner = owner
	replaced_by(src)
	if(tmp_owner)
		new replace_path(tmp_owner, 1) // takes the freed brain slot
		tmp_owner = null

/obj/item/organ/internal/brain/Initialize(mapload)
	. = ..()
	sync_defib_window()
	make_mind_host(src)

/// THE brain-death decision. A brain at 100% damage, or a dead organ, cannot
/// be defibrillated or treated back: the person needs a resleeve. Defib,
/// the humanoid body plan, scanners, MMIs and the brain view all ask this.
/obj/item/organ/internal/brain/proc/is_brain_dead()
	return (status & ORGAN_DEAD) || (max_damage && damage >= max_damage)

/// A brain-dead brain is not repaired back: revival goes through resleeving.
/obj/item/organ/internal/brain/is_beyond_repair()
	return is_brain_dead()

/obj/item/organ/internal/brain/beyond_repair_perception(mob/living/user)
	return "The tissue stays grey and slack; the brain has already died."

/obj/item/organ/internal/brain/examine(mob/user) // -- TLE
	. = ..()
	var/mob/living/carbon/brain/view = hosted_view()
	if(view?.client)//if thar be a brain inside... the brain.
		. += "You can feel the small spark of life still left in this one."
	else
		. += "This one seems particularly lifeless. Perhaps it will regain some of its luster later..."

/obj/item/organ/internal/brain/removed(mob/living/user)
	sync_defib_window() // charge the span in the body before the clock source changes

	if(name == initial(name))
		name = "\the [owner.real_name]'s [initial(name)]"

	var/mob/living/simple_mob/animal/borer/borer = owner?.has_brain_worms()

	if(borer)
		borer.detatch() //Should remove borer if the brain is removed - RR

	if(owner?.mind)
		var/datum/mind_host/host = get_mind_host(src)
		var/mob/living/carbon/brain/view = host.receive_mind(owner.mind, "brain removed from [owner]")
		to_chat(view, span_notice("You feel slightly disoriented. That's normal when you're just  [initial(name)]."))

	..()
	sync_defib_window() // re-anchor on the loose brain's clock
	hosted_view()?.refresh_host_status()

/obj/item/organ/internal/brain/replaced(mob/living/target)

	var/datum/mind_host/host = get_mind_host(src)
	if(host?.hosted_mind())
		if(target.key)
			target.ghostize()
		host.release_mind(target, "brain implanted into [target]")
	host?.discard_view() // an implanted brain shows no view
	sync_defib_window() // charge the span spent loose
	..()
	sync_defib_window() // re-anchor on the new owner's clock

/// Brain-slot interface (audit P2-D9): whatever organ sits in O_BRAIN (a brain, an MMI holder,
/// a posibrain) answers how well it still runs the body, 0..1 in tenths. Callers type the slot's
/// occupant as /obj/item/organ/internal and ask this; no occupant duck-types brain procs.
/obj/item/organ/internal/proc/get_control_efficiency()
	return max_damage ? max(0, 1 - round(damage / max_damage, 0.1)) : 1

/obj/item/organ/internal/brain/pariah_brain
	name = "brain remnants"
	desc = "Did someone tread on this? It looks useless for cloning or cyborgification."
	organ_tag = O_BRAIN
	parent_organ = BP_HEAD
	icon = 'icons/mob/alien.dmi'
	icon_state = "chitin"
	can_assist = FALSE

/obj/item/organ/internal/brain/xeno
	name = "thinkpan"
	desc = "It looks kind of like an enormous wad of purple bubblegum."
	icon = 'icons/mob/alien.dmi'
	icon_state = "chitin"
	can_assist = FALSE

/obj/item/organ/internal/brain/slime
	icon = 'icons/obj/surgery.dmi'
	name = "slime core"
	desc = "A complex, organic knot of jelly and crystalline particles."
	icon_state = "core"
	decays = FALSE
	parent_organ = BP_TORSO
	clone_source = TRUE
	flags = OPENCONTAINER

/obj/item/organ/internal/brain/slime/is_open_container()
	return 1

DECLARE_REAGENTS(/obj/item/organ/internal/brain/slime, 50, null)

CAPABILITIES(/obj/item/organ/internal/brain/slime)
	after_init(0, then(PROC_REF(match_core_color)))

/// Matches the core to the Promethean's starting colour, once the body has placed it.
/obj/item/organ/internal/brain/slime/proc/match_core_color(datum/act/timer/A)
	//Match the core to the Promethean's starting color.
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = rgb(min(H.r_skin + 40, 255), min(H.g_skin + 40, 255), min(H.b_skin + 40, 255))

/obj/item/organ/internal/brain/slime/proc/reviveBody()
	// The core hosts the promethean's mind; the new body is grown from the
	// character's identity (its DNA reference, persistent traits, languages
	// and flavour follow the mind when it moves in).
	var/datum/mind_host/host = get_mind_host(src)
	var/datum/mind/clonemind = host?.hosted_mind()
	if(!clonemind)
		return 0
	var/datum/character_identity/identity = clonemind.get_identity()
	var/datum/dna/source_dna = identity?.get_dna()
	if(!source_dna)
		return 0
	if(identity.has_genetic_effect(/datum/body_effect/no_clone))	//Can't be revived. Probably won't happen...?
		return 0

	var/mob/living/carbon/human/H = new /mob/living/carbon/human(get_turf(src), source_dna.species)
	own_clear(H, nameof(H.dna), OWN_DELETE)
	rel_set(H, nameof(H.dna), source_dna.Clone()) // a new body needs DNA of its own

	H.UpdateAppearance()
	H.sync_dna_traits(FALSE) // Traitgenes Sync traits to genetics if needed
	H.sync_organ_dna()
	H.initialize_vessel()
	H.real_name = identity.real_name || H.dna.real_name || "promethean ([rand(0,999)])"

	H.set_nutrition(260) //Enough to try to regenerate ONCE.
	H.injure(INJURY_BLUNT, 40, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.injure(INJURY_BURN, 40, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.status_at_least(STAT_PARALYZED, 4)
	H.status_at_least(STAT_SLEEPING, 4)
	for(var/obj/item/organ/external/E in H.organs) //They've still gotta congeal, but it's faster than the clone sickness they'd normally get.
		if(E && E.organ_tag == BP_L_ARM || E.organ_tag == BP_R_ARM || E.organ_tag == BP_L_LEG || E.organ_tag == BP_R_LEG)
			E.removed()
			dissolved(E) // the limb melts away to regrow
			E = null
	H.regenerate_icons()
	host.release_mind(H, "promethean core revival")
	for(var/effect_type in identity.genetic_effects)
		H.apply_body_effect(effect_type)

	OM_EMIT(H, /datum/om/event/human_dna_finalized)

	spent(src)
	return 1

/datum/decl/chemical_reaction/instant/promethean_brain_revival
	name = "Promethean Revival"
	id = "prom_revival"
	result = null
	required_reagents = list(REAGENT_ID_PHORON = 40)
	result_amount = 1

/datum/decl/chemical_reaction/instant/promethean_brain_revival/can_happen(datum/reagents/holder)
	if(holder.my_atom && istype(holder.my_atom, /obj/item/organ/internal/brain/slime))
		return ..()
	return FALSE

/datum/decl/chemical_reaction/instant/promethean_brain_revival/on_reaction(datum/reagents/holder)
	var/obj/item/organ/internal/brain/slime/brain = holder.my_atom
	if(brain.reviveBody())
		brain.visible_message(span_notice("[brain] bubbles, surrounding itself with a rapidly expanding mass of slime!"))
	else
		brain.visible_message(span_warning("[brain] shifts strangely, but falls still."))

/obj/item/organ/internal/brain/golem
	name = "chem"
	desc = "A tightly furled roll of paper, covered with indecipherable runes."
	icon = 'icons/obj/wizard.dmi'
	icon_state = "scroll"
	can_assist = FALSE

/obj/item/organ/internal/brain/grey
	desc = "A piece of juicy meat found in a person's head. This one is strange."
	icon_state = "brain_grey"

CAPABILITIES(/obj/item/organ/internal/brain/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/brain/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color


// --- The brain view reads its tissue ---------------------------------------------------
//
// A view (/mob/living/carbon/brain) whose mind host has brain tissue has no
// health of its own: harm lands on the organ as lesions, repair comes off the
// organ, and its questions are answered from the organ. The organ keeps every
// lesion across body -> view -> MMI -> body, so damage and treatment carry on.

/mob/living/carbon/brain/injure(kind, amount, zone = null, atom/source = null, armor = 0, affliction = null, flags = NONE)
	var/obj/item/organ/internal/brain/tissue = host_tissue()
	if(!tissue)
		return ..()
	if(amount <= 0 || kind < 1 || kind > INJURY_KIND_COUNT || in_godmode(src))
		return 0
	var/lesion_type = ispath(affliction, /datum/affliction/lesion) ? affliction : organ_lesion_for_injury(kind)
	if(!lesion_type)
		return 0
	. = tissue.apply_lesion_damage(amount, lesion_type, TRUE)
	refresh_host_status()

/mob/living/carbon/brain/mend(tag, amount, target = null)
	var/obj/item/organ/internal/brain/tissue = host_tissue()
	if(!tissue)
		return ..()
	if(amount <= 0 || tag != tissue.lesion_repair_tag())
		return 0
	. = tissue.restore_lesions(amount)
	refresh_host_status()

/mob/living/carbon/brain/vitality()
	var/obj/item/organ/internal/brain/tissue = host_tissue()
	if(!tissue)
		return ..()
	if(!tissue.max_damage)
		return 1
	return clamp(1 - tissue.damage / tissue.max_damage, 0, 1)

/mob/living/carbon/brain/injury_load(category)
	var/obj/item/organ/internal/brain/tissue = host_tissue()
	if(!tissue)
		return ..()
	return category == INJURY_CATEGORY_NEURAL ? tissue.damage : 0

/mob/living/carbon/brain/is_injured()
	var/obj/item/organ/internal/brain/tissue = host_tissue()
	if(!tissue)
		return ..()
	return tissue.damage > 0

