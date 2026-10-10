/// apply_wound_damage() tuning: spill into internal organs, dismemberment, overflow spread.
#define LIMB_SPILL_SHARP_BRUTE 5
#define LIMB_SPILL_BLUNT_BRUTE 10
#define LIMB_SPILL_CHANCE 5
#define LIMB_VITAL_DISMEMBER_RESIST 1.5
#define LIMB_RUINED_DISMEMBER_MULT 3
#define LIMB_DISMEMBER_PRIOR_FRACTION (1/3)
#define LIMB_DISMEMBER_HIT_FRACTION 0.5
#define LIMB_SPREAD_MIN_OVERFLOW 5
#define LIMB_DISMEMBER_INELIGIBLE 0
#define LIMB_DISMEMBER_SPARED 1
#define LIMB_DISMEMBER_DROPPED 2

/****************************************************
				EXTERNAL ORGANS
****************************************************/

//These control the damage thresholds for the various ways of removing limbs
/// <summary>
/// Arms and legs have 80 damage, which is a good baseline to go off of.
/// The droplimb_threshold is "Divide the limb's max health by this number"
/// That is the damage required (in ONE hit) to tear off or destroy a limb.
/// If the damage dealt per hit is below that, it can NOT remove limbs.
/// </summary>
#define DROPLIMB_THRESHOLD_EDGE 5 //For limb of 80(arm/leg) requires 16 or more damage to cut off.
#define DROPLIMB_THRESHOLD_DESTROY 3.34 //Requires 24 damage or more to DESTROY a arm/leg with a blunt object. Blunt is going to DESTROY over just knocking something off!

/obj/item/organ/external
	name = "external"
	min_broken_damage = 60 // Flat doubling of all min_broken_damage
	max_damage = 0
	dir = SOUTH
	organ_tag = "limb"

	var/brokenpain = 50
	// Strings
	var/broken_description             // fracture string if any.
	var/damage_state = "00"            // Modifier used for generating the on-mob damage overlay for this limb.

	// Damage vars.
	var/brute_mod = 1                  // Multiplier for incoming brute damage.
	var/burn_mod = 1                   // As above for burn.
	var/spread_dam = 0
	// Appearance vars.
	var/nonsolid                       // Snowflake warning, reee. Used for slime limbs.
	var/transparent                    // As above, so below. Used for transparent limbs.
	var/icon_name = null               // Icon state base.
	var/body_part = null               // Part flag
	var/icon_position = 0              // Used in mob overlay layering calculations.
	var/model                          // Used when caching robolimb icons.
	var/force_icon                     // Used to force override of species-specific limb icons (for prosthetics). Also used for any limbs chopped from a simple mob, and then attached to humans.
	var/icon/mob_icon                  // Cached icon for use in mob overlays.
	var/gendered_icon = 0              // Whether or not the icon state appends a gender.
	var/s_tone                         // Skin tone.
	var/list/s_col                     // skin colour
	var/s_col_blend = ICON_ADD         // How the skin colour is applied.
	var/list/h_col                     // hair colour
	var/body_hair                      // Icon blend for body hair if any.
	var/mob/living/applied_pressure
	var/list/markings                  // Markings (body_markings) to apply to the icon
	var/skip_robo_icon = FALSE 			//to force it to use the normal species icon
	var/digi_prosthetic = FALSE 		//is it a prosthetic that can be digitigrade

	// Wound and structural data.
	// Wounds are /datum/affliction/wound located on this limb: see get_wounds() (body/parts/limb.dm).
	var/obj/item/organ/external/parent // Master-limb.
	var/list/children                  // Sub-limbs.
	var/sabotaged = 0                  // If a prosthetic limb is emagged, it will detonate when it fails.
	var/list/implants                  // Currently implanted objects.
	var/organ_rel_size = 25            // Relative size of the organ.
	var/base_miss_chance = 20          // Chance of missing.
	var/atom/movable/splinted

	// Joint/state stuff.
	var/can_grasp                      // It would be more appropriate if these two were named "affects_grasp" and "affects_stand" at this point
	var/can_stand                      // Modifies stance tally/ability to stand.
	var/disfigured = 0                 // Scarred/burned beyond recognition.
	var/cannot_amputate                // Impossible to amputate.
	var/cannot_break                   // Impossible to fracture.
	var/cannot_gib                     // Impossible to gib, distinct from amputation.
	var/joint = "joint"                // Descriptive string used in dislocation.
	var/amputation_point               // Descriptive string used in amputation.
	var/dislocated = 0    // If you target a joint, you can dislocate the limb, impairing it's usefulness and causing pain
	var/encased                        // Needs to be opened with a saw to access the organs.

	/// Surgical access depth. A cache of this limb's surgical incision
	/// affliction (code/modules/surgery/incision.dm); only the incision writes it.
	var/open = 0
	/// Dissection stage of a severed limb on the bench.
	var/stage = 0

	// HUD element variable, see organ_icon.dm get_damage_hud_image()
	var/image/hud_damage_image


// child limbs and internal organs go with it; it leaves its owner's organ tables.
/obj/item/organ/external/on_destroy(force)
	// Child limbs and organs sit in this limb's part slots: the ledger deletes
	// them (SLOT_DROP_DELETE, children first) and the detach hook clears the
	// tree caches and the owner's (code/modules/body/parts/).
	for(var/datum/affliction/wound/W as anything in get_wounds())
		remove_wound(W)

	// `splinted` is a relation view (it may name a worn spacesuit), so a splint that went into
	// this limb goes with it by hand; the tourniquet is owned and deleted by policy.
	if(splinted && splinted.loc == src)
		var/atom/movable/splint = splinted
		splint.moveToNullspace()
		consume(splint)

	// The detach hook (body/parts/attach.dm) keeps the owner's organ caches; the
	// implant site slot's own teardown (destroy transaction phase 5, before
	// Destroy(), OM relations step 2) already unlinked every implant here --
	// clearing its part/imp_in and this organ's implants list. The real
	// objects themselves are then deleted below, by drop_policy.

	..()

/// An organ's implant site (OM relations step 2, doc/rewrite/containment.md
/// §3): a keyed internal slot, replacing the old bare implanted_in relation
/// plus a hand-managed forceMove(). Keyed by implant type, so re-implanting
/// the same kind refuses rather than stacking duplicates. Deleted with the
/// organ, same as the raw contents this slot replaces.
/datum/relation_definition/slot/implant_site
	holder = /obj/item/organ/external
	slot_id = ORGAN_SLOT_IMPLANTS
	name = "implant site"
	// After the tree slots (parts:child, parts:organs), before cavity and the rest:
	// declaration order is destroy order, parts before what is merely stuck in them.
	order = 3
	exposure = SLOT_EXPOSURE_INTERNAL
	capacity_model = SLOT_CAPACITY_NONE
	keyed = TRUE
	drop_policy = SLOT_DROP_DELETE

/// No view fields (OM relations step 3): `part` (the implant's own var) and
/// `implants` (the organ's list) are still ordinary vars every reader here
/// uses, but this slot's own on_link()/on_unlink() are their only writer now.
/// `imp_in` (the host mob) has no reverse list of its own to double-check
/// against, so it needs the organ's `owner`, not the organ itself. Previously
/// all of this was hand-maintained (/obj/item/implant/Destroy() and
/// /obj/item/organ/external/Destroy() each cleaned up their own half); now
/// hard-deleting either one tears the whole link down automatically,
/// including `imp_in`, which used to only get cleared by the organ's
/// Destroy() -- so directly hard-deleting the host mob without going through
/// organ removal left `imp_in` dangling.
/datum/relation_definition/slot/implant_site/on_link(obj/item/implant/source, obj/item/organ/external/target, datum/relation_edge/edge)
	if(istype(source) && istype(target))
		rel_set(source, nameof(source.part), target)
		rel_add(target, nameof(target.implants), source)
		rel_set(source, nameof(source.imp_in), target.owner)

/datum/relation_definition/slot/implant_site/on_unlink(obj/item/implant/source, obj/item/organ/external/target, datum/relation_edge/edge)
	if(istype(source) && source.part == target)
		rel_clear(source, nameof(source.part))
	if(istype(target))
		rel_remove(target, nameof(target.implants), source)
	// Unlike a bare relation, this slot's own drop_policy (DELETE) may
	// already be what's destroying `source` (its organ is going and takes it
	// with it) -- writing to a QDELETED datum's own vars is harmless, and
	// leaving `imp_in` stale until then would fail a "no dangling refs" check
	// that inspects it before GC.
	if(istype(source))
		rel_clear(source, nameof(source.imp_in))

/// A robotic limb is also scorched by a pulse.
/obj/item/organ/external/organ_emp(datum/act/A)
	..()
	var/datum/notice/hit/emp/N = A
	var/datum/damage_packet/packet = N.packet
	for(var/obj/O as anything in contents_of(src))
		O.emp_act(packet.severity)

	if(!(is_robotic()))
		return
	var/scorch_damage = 0
	switch (packet.severity)
		if (1)
			scorch_damage += rand(5, 8)
		if (2)
			scorch_damage += rand(4, 6)
		if(3)
			scorch_damage += rand(2, 5)
		if(4)
			scorch_damage += rand(1, 3)

	if(scorch_damage)
		if(owner)
			owner.injure(INJURY_ELECTRIC, scorch_damage, organ_tag, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
		else
			apply_wound_damage(0, scorch_damage)

// A limb in hand: what is stuck in it (or in the limbs attached to it) is pulled out first, one thing a use, in any stance, before it
// can be bitten. A limb on the table: the old bench surgery, one tool per stage.
CAPABILITIES(/obj/item/organ/external)
	after_init(0, then(PROC_REF(icon_after_init)))
	owns_one(nameof(tourniquet))
	owns_one(nameof(nail_polish), /datum/nail_polish)
	op("pull_embedded", in_hand(), label("Pull out"), priority(OP_PRIORITY_PART), when(req(PROC_REF(has_embedded))), then(PROC_REF(pull_embedded)))
	op("bench_scalpel", item(/obj/item/surgical/scalpel), label("Cut"), when(req(PROC_REF(at_scalpel_stage))), then(PROC_REF(bench_scalpel)))
	op("bench_retract", item(/obj/item/surgical/retractor), label("Crack open"), when(req(PROC_REF(at_stage_1))), then(PROC_REF(bench_retract)))
	op("bench_cauterize", item(/obj/item/surgical/cautery), label("Close"), when(req(PROC_REF(at_stage_1))), then(PROC_REF(bench_cauterize)))
	op("bench_extract", item(/obj/item/surgical/hemostat), label("Extract"), when(req(PROC_REF(at_stage_2))),
		asks(/datum/prompt/choice, fields = list("question" = "What would you like to remove?", "title" = "Extraction", "choices" = computed(PROC_REF(extraction_names)), "timeout" = 20 SECONDS),
			step = "extract", when = PROC_REF(has_contents)),
		then(PROC_REF(bench_extract)))
	op("bench_fixovein", item(/obj/item/surgical/FixOVein), label("Partially close"), when(req(PROC_REF(at_stage_2))), then(PROC_REF(bench_fixovein)))
	op("bench_rejuvenate", item(/obj/item/surgical/bioregen), label("Rejuvenate"), when(req(PROC_REF(at_stage_3))), then(PROC_REF(bench_rejuvenate)))
	// A patch on a robotic limb takes a second with the tool in hand; the welder or the cable says what it patches (robo_repair()).
	op("robo_repair", ai(), wait(1 SECOND, keeps = HELD | ALIVE | STAY), on_interrupt(PROC_REF(robo_repair_failed)), then(PROC_REF(robo_repair_done)))

/// What can be pulled out of this limb and the limbs attached to it: anything but organs.
/obj/item/organ/external/proc/embedded_objects()
	. = list()
	for(var/obj/item/organ/external/E in (contents + src)) // ALLOW(reads): what is stuck in the limb is read when the limb is used, never from a cached menu
		for(var/obj/item/I in contents_of(E))
			if(istype(I,/obj/item/organ))
				continue
			. |= I

/obj/item/organ/external/proc/has_embedded(datum/act/op/A)
	return (length(embedded_objects()) > 0) ? null : /datum/msg/req_failed

/obj/item/organ/external/proc/pull_embedded(datum/act/op/A)
	var/mob/living/user = A.actor
	var/list/removable_objects = embedded_objects()
	if(!length(removable_objects))
		return
	var/obj/item/I = pick(removable_objects)
	I.forceMove(get_turf(user)) //just in case something was embedded that is not an item
	if(istype(I))
		user.put_in_hands(I)
	act_message(user, src, others = span_danger("%U% rips %I% out of %T%!"), item = I)

/// The scalpel cuts a closed limb open, or the necrotic tissue off a fully open one.
/obj/item/organ/external/proc/at_scalpel_stage(datum/act/op/A)
	return (stage == 0 || stage == 2) ? null : /datum/msg/req_failed // ALLOW(reads): the bench stage is read when a tool is used, never from a cached menu
/obj/item/organ/external/proc/at_stage_1(datum/act/op/A)
	return (stage == 1) ? null : /datum/msg/req_failed // ALLOW(reads): the bench stage is read when a tool is used, never from a cached menu
/obj/item/organ/external/proc/at_stage_2(datum/act/op/A)
	return (stage == 2) ? null : /datum/msg/req_failed // ALLOW(reads): the bench stage is read when a tool is used, never from a cached menu
/obj/item/organ/external/proc/at_stage_3(datum/act/op/A)
	return (stage == 3) ? null : /datum/msg/req_failed // ALLOW(reads): the bench stage is read when a tool is used, never from a cached menu

/obj/item/organ/external/proc/bench_scalpel(datum/act/op/A)
	if(stage == 2)
		bench_necrosis(A)
	else
		bench_incise(A)

/obj/item/organ/external/proc/bench_incise(datum/act/op/A)
	act_message(A.actor, src, others = span_danger(span_bold("%U%") + " cuts %T% open with [A.held]!"))
	stage++

/obj/item/organ/external/proc/bench_retract(datum/act/op/A)
	act_message(A.actor, src, others = span_danger(span_bold("%U%") + " cracks %T% open like an egg with [A.held]!"))
	stage++

/obj/item/organ/external/proc/bench_cauterize(datum/act/op/A)
	act_message(A.actor, src, others = span_danger(span_bold("%U%") + " closes %T% with [A.held]!"))
	stage--

/obj/item/organ/external/proc/has_contents(datum/act/op/A)
	return LAZYLEN(contents) > 0 // ALLOW(reads): the extraction question is asked from what the limb holds when the hemostat goes in

/// The things in the limb, by a name each (a repeated name gets its place in the list).
/obj/item/organ/external/proc/extraction_choices()
	. = list()
	for(var/atom/movable/thing as anything in contents)
		var/label = "[thing.name]"
		if(.[label])
			label = "[thing.name] ([length(.) + 1])"
		.[label] = thing

/obj/item/organ/external/proc/extraction_names(datum/act/op/A)
	. = list()
	for(var/label in extraction_choices())
		. += label

/obj/item/organ/external/proc/bench_extract(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!LAZYLEN(contents))
		act_message(user, src, others = span_danger(span_bold("%U%") + " fishes around fruitlessly in %T% with [A.held]."))
		return
	var/obj/item/removing = extraction_choices()[A.step_value("extract")]
	if(!removing || removing.loc != src || !Adjacent(user)) //Didn't select anything or selected something that was already removed OR we walked away.
		act_message(user, src, others = span_danger(span_bold("%U%") + " decides against removing anything from %T%"))
		return
	removing.forceMove(get_turf(user.loc))
	user.put_in_hands(removing)
	act_message(user, src, others = span_danger(span_bold("%U%") + " extracts [removing] from %T% with [A.held]!"))

/obj/item/organ/external/proc/bench_fixovein(datum/act/op/A)
	act_message(A.actor, src, others = span_danger(span_bold("%U%") + " partially closes %T% with [A.held]!"))
	stage--

//Begin necrosis surgery
/obj/item/organ/external/proc/bench_necrosis(datum/act/op/A)
	if(!(status & ORGAN_DEAD))
		to_chat(A.actor, span_notice("The limb isn't necrotic, there's no need to fix it!"))
		return
	act_message(A.actor, src, others = span_danger(span_bold("%U%") + " cuts necrotic tissue off %T% with [A.held]!"))
	stage++

/obj/item/organ/external/proc/bench_rejuvenate(datum/act/op/A)
	act_message(A.actor, src, others = span_danger(span_bold("%U%") + " rejuvinates formerly necrotic tissue on %T% with [A.held]!"))
	germ_level = 0
	set_status(status & ~ORGAN_DEAD)
	clear_necrosis() // the dead-tissue afflictions go too (audit D12)
	stage-- //Go back to stage 2

/obj/item/organ/external/get_mechanics_info(list/additional_information)
	if(!additional_information)
		additional_information = list()
	switch(stage)
		if(0)
			additional_information += "Can be cut open via a scalpel to perform procedures on it."
		if(1)
			additional_information += "The [name] is cut open and can be opened further with a retractor or closed with a cautery."
		if(2)
			additional_information += "The [name] is fully open, allowing for removal of anything within or attached via a hemostat. It can also be partially closed with fix-o-vein."
			if(status & ORGAN_DEAD)
				additional_information += "Can have necrosis partially removed by use of a scalpel."
		if(3) //Status only happens if we used a scalpel on stage 2.
			additional_information += "The [name] is fully open with some necrotic tissue removed. The use of a bioregenerator can fully remove infection and necrosis from the limb."
	if(status & ORGAN_DEAD)
		additional_information += "Can have necrosis and infection surgically removed."
	. = ..(additional_information)
	return .

/obj/item/organ/external/examine(mob/user)
	. = ..()
	if(in_range(user, src) || isobserver(user))
		FOR_REAL_CONTENTS(var/obj/item/I, src)

			//Handling attached limbs, like the foot on a leg.
			if(istype(I, /obj/item/organ/external))
				var/obj/item/organ/external/child_organ = I
				. += span_notice("There is [child_organ.name] attached to it.")

				//Handling status on attached limbs.
				if(child_organ.status & ORGAN_DEAD) //Can happen for other reasons than infection.
					. += span_bolddanger("The attached [child_organ.name] is dead.")
				if(child_organ.status & ORGAN_MUTATED)
					. += span_danger("The attached [child_organ.name] is mutated and deformed.")
				if(child_organ.is_fractured())
					. += span_danger("The attached [child_organ.name] is broken.")

				//Handling infections on attached limbs.
				if(child_organ.germ_level < INFECTION_LEVEL_ONE)
					continue

				switch(child_organ.germ_level)
					if(INFECTION_LEVEL_ONE to INFECTION_LEVEL_TWO - 1)
						. += span_warning("The attached [child_organ.name] has signs of a minor infection.")
					if(INFECTION_LEVEL_TWO to INFECTION_LEVEL_THREE - 1)
						. += span_boldwarning("The attached [child_organ.name] has signs of a moderate infection.")
					if(INFECTION_LEVEL_THREE to INFINITY)
						. += span_bolddanger("The attached [child_organ.name] is necrotic.")
				continue

			if(istype(I, /obj/item/organ)) //We can't see inside the organ if it has an organ in it.
				continue
			. += span_danger("There is \a [I] sticking out of it.")
		if(stage)
			switch(stage)
				if(1)
					. += span_danger("The [name] is surgically cut open.")
				if(2)
					. += span_danger("The [name] is cut open and the skin retracted.")


/// Remove the dead-tissue afflictions on this limb, attached or loose (bioregeneration).
/obj/item/organ/external/proc/clear_necrosis()
	for(var/datum/affliction/tissue_necrosis/N in afflictions_here())
		if(N.body)
			N.body.remove_affliction(N)
		if(!rel_remove(src, nameof(detached_afflictions), N))
			spent(N)
	integrity_dirty = TRUE

/obj/item/organ/external/proc/is_dislocated()
	if(dislocated > 0)
		return 1
	if(is_parent_dislocated())
		return 1//if any parent is dislocated, we are considered dislocated as well
	return 0

/obj/item/organ/external/proc/is_parent_dislocated()
	var/obj/item/organ/external/O = parent
	while(O && O.dislocated != -1)
		if(O.dislocated == 1)
			return 1
		O = O.parent
	return 0

//new function to check for markings
/obj/item/organ/external/proc/is_hidden_by_markings()
	for(var/M in markings)
		if(!markings[M]["on"]) //If the marking is off, the organ isn't hidden by it.
			continue
		var/datum/sprite_accessory/marking/mark_style = markings[M]["datum"]
		if(istype(mark_style,/datum/sprite_accessory/marking) && (organ_tag in mark_style.hide_body_parts))
			return 1

/obj/item/organ/external/proc/dislocate()
	if(dislocated == -1)
		return

	dislocated = 1
	if(istype(owner))
		grant(owner, granted_verb(/mob/living/carbon/human/proc/relocate), src)
		owner.body?.invalidate(BODY_DIRTY_ORGANS)

/obj/item/organ/external/proc/relocate()
	if(dislocated == -1)
		return

	dislocated = 0
	if(istype(owner))
		if(!organ_can_feel_pain())
			owner.adjust_shock(20, "dislocation reset")

		// Each dislocated limb grants the verb; it stays while another limb is still out.
		revoke(owner, granted_verb(/mob/living/carbon/human/proc/relocate), src)
		owner.body?.invalidate(BODY_DIRTY_ORGANS)

/obj/item/organ/external/update_health()
	recalc_integrity()

/obj/item/organ/external/Initialize(mapload, internal)
	. = ..(mapload, 0)
	if(istype(owner))
		sync_colour_to_human(owner)

/// Draws itself, once the body it was made in has placed it.
/obj/item/organ/external/proc/icon_after_init(datum/act/timer/A)
	if(!QDELETED(src))
		get_icon()

/// Attaches this limb to `target`: onto the limb its parent_organ names, or
/// as the root when it has none. A stump holding the place is taken off
/// first. A ledger move into the part slot: the attach hook does the
/// bookkeeping for the whole subtree. Returns TRUE on success.
/obj/item/organ/external/replaced(mob/living/carbon/human/target)
	if(!istype(target))
		return FALSE
	if(!parent_organ)
		return place_into(target, SLOT_ID_PART_ROOT)
	var/obj/item/organ/external/joint_limb = target.get_organ(parent_organ)
	if(!joint_limb)
		log_runtime("PARTS: [src] ([type]) has no [parent_organ] to join onto on [key_name(target)]")
		return FALSE
	var/obj/item/organ/external/placeholder = joint_limb.slot_lookup(SLOT_ID_PART_CHILD, organ_tag)
	if(placeholder?.is_stump())
		spent(placeholder)
	return place_into(joint_limb, SLOT_ID_PART_CHILD)

/// Born inside `M`: onto the limb our parent_organ names, or into the root.
/obj/item/organ/external/place_in_body(mob/living/M)
	var/datum/ledger/L = dq_ledger(M) // syncs: a mob with no part tree adopts us here
	if(!L?.def_by_id(SLOT_ID_PART_ROOT))
		return !!L
	if(!parent_organ)
		return place_into(M, SLOT_ID_PART_ROOT)
	var/obj/item/organ/external/joint_limb = LAZYACCESS(M.organs_by_name, parent_organ)
	if(!joint_limb)
		log_runtime("PARTS: [src] ([type]) born in [key_name(M)] with no [parent_organ] to join onto; left loose")
		return FALSE
	return place_into(joint_limb, SLOT_ID_PART_CHILD)

/****************************************************
			   DAMAGE PROCS
****************************************************/

/obj/item/organ/external/proc/is_damageable(additional_damage = 0)
	//Continued damage to vital organs can kill you, and robot organs don't count towards total damage so no need to cap them.
	return (vital || (is_robotic()) || get_trauma() + get_burn() + additional_damage < max_damage)

/obj/item/organ/external/proc/is_fracturable()
	if(is_robotic())
		return FALSE	//robot limbs don't fracture
	if(is_fractured() || cannot_break)
		return FALSE
	return TRUE

/// Body-internal: turn an already-mitigated limb injury into wounds (and
/// spill-over into the limb's internal organs, fractures, dismemberment).
/// Reached from injure() through the humanoid plan and the limb's
/// receive_injury(); brute_mod / burn_mod are applied there, as the part
/// multiplier in body.injury_multiplier(). Code outside code/modules/body and
/// code/modules/body calls injure(), never this.
/obj/item/organ/external/proc/apply_wound_damage(brute, burn, sharp, edge, used_weapon = null, list/forbidden_limbs = null, permutation = FALSE, projectile)
	if(in_godmode(owner))
		return 0
	owner?.body?.invalidate(BODY_DIRTY_ORGANS)
	brute = round(brute, 0.1)
	burn = round(burn, 0.1)

	if((brute <= 0) && (burn <= 0))
		return 0

	//This tells us how damaged we are prior to this attack.
	var/prior_damage = get_trauma() + get_burn()

	brute = spill_into_organs(brute, sharp, edge)

	if(is_fractured() && brute)
		jostle_bone(brute)
		if(owner && organ_can_feel_pain() && prob(40) && !isbelly(owner.loc) && !istype(owner.loc, /obj/item/dogborg/sleeper)) // detached limbs have no owner (D14)
			owner.emote("scream")	//getting hit on broken hand hurts
	if(used_weapon)
		add_autopsy_data("[used_weapon]", brute + burn)

	var/list/overflow = inflict_wounds(brute, burn, sharp, edge)

	// sync the organ's damage with its wounds
	update_damages()

	//If limb took enough damage, try to cut or tear it off.
	// A limb that was eligible to come off but held spreads what it couldn't take.
	if(owner && !is_stump() && try_dismember(brute, burn, edge, used_weapon, projectile, prior_damage) == LIMB_DISMEMBER_SPARED && overflow && !permutation)
		spread_overflow(overflow[1], overflow[2], forbidden_limbs)
	if(QDELETED(src))
		return
	return update_damage_state()

/// High brute or a sharp hit may carry into one of the limb's internal organs. Blunt force
/// bruises it, blades tear it, a narrow penetrating hit holes it. Returns the brute left for
/// the limb itself (halved when an organ took some).
/obj/item/organ/external/proc/spill_into_organs(brute, sharp, edge)
	if(!length(held_organs()))
		return brute
	if(!(get_trauma() >= max_damage || (((sharp && brute >= LIMB_SPILL_SHARP_BRUTE) || brute >= LIMB_SPILL_BLUNT_BRUTE) && prob(LIMB_SPILL_CHANCE))))
		return brute
	brute *= 0.5
	var/obj/item/organ/internal/spilled = pick(held_organs())
	if(istype(spilled))
		var/spill_lesion = /datum/affliction/lesion/contusion
		if(sharp)
			spill_lesion = edge ? /datum/affliction/lesion/laceration : /datum/affliction/lesion/perforation
		spilled.apply_lesion_damage(brute, spill_lesion)
	return brute

/// The wound a brute hit of this kind makes.
/obj/item/organ/external/proc/brute_wound_type(sharp, edge)
	if(!sharp)
		return BRUISE
	return edge ? CUT : PIERCE

/// Turn the hit into wounds. A limb that can't take it all (limbs_can_break) takes what it can;
/// the rest becomes shock. Returns list(brute_overflow, burn_overflow), or null with none.
/obj/item/organ/external/proc/inflict_wounds(brute, burn, sharp, edge)
	if(is_damageable(brute + burn) || !CONFIG_GET(flag/limbs_can_break))
		if(brute)
			create_wound(brute_wound_type(sharp, edge), brute)
		if(burn)
			create_wound(BURN, burn)
		return null
	// Non-vital organs are limited to max_damage: you can't kill someone by bludgeoning their
	// arm to 200, but the excess pushes them into paincrit as shock.
	var/limb_cap = max_damage * CONFIG_GET(number/organ_health_multiplier)
	var/can_inflict = limb_cap - (get_trauma() + get_burn())
	if(!can_inflict)
		return null
	var/brute_overflow = 0
	var/burn_overflow = 0
	if(brute > 0)
		create_wound(brute_wound_type(sharp, edge), min(brute, can_inflict))
		brute_overflow = max(0, brute - can_inflict)
	can_inflict = limb_cap - (get_trauma() + get_burn()) // so burn doesn't overload a limb taking both
	if(burn > 0 && can_inflict)
		create_wound(BURN, min(burn, can_inflict))
		burn_overflow = max(0, burn - can_inflict)
	var/spillover = brute_overflow + burn_overflow
	if(!spillover)
		return null
	if(owner) // detached limbs have no owner (D14)
		owner.adjust_shock(spillover * CONFIG_GET(number/organ_damage_spillover_multiplier), "organ spillover")
	return list(brute_overflow, burn_overflow)

/// Chance-based dismemberment after a hit. Returns LIMB_DISMEMBER_INELIGIBLE (the hit can't take
/// it off), LIMB_DISMEMBER_SPARED (it could, but held) or LIMB_DISMEMBER_DROPPED.
/obj/item/organ/external/proc/try_dismember(brute, burn, edge, used_weapon, projectile, prior_damage)
	if(cannot_amputate || !CONFIG_GET(flag/limbs_can_break))
		return LIMB_DISMEMBER_INELIGIBLE
	var/limb_cap = max_damage * CONFIG_GET(number/organ_health_multiplier)
	// How injured the limb is after this hit: the more damaged, the likelier it comes off.
	var/damage_factor = ((get_trauma() + get_burn()) / limb_cap) * 100
	if(get_trauma() > max_damage || get_burn() > max_damage) // only vital limbs go over
		damage_factor = 100

	var/edge_eligible = FALSE
	if(edge)
		var/obj/item/W = used_weapon
		edge_eligible = !istype(W) || W.w_class >= w_class

	// The thresholds were tuned for melee. Projectiles creep, so they count half unless the one
	// hit exceeds the limb; vital limbs resist; hammering an already-ruined limb counts triple.
	var/modified_brute = brute
	var/modified_burn = burn
	if(projectile && (brute + burn) < max_damage)
		modified_brute /= 2
		modified_burn /= 2
	if(vital)
		modified_brute /= LIMB_VITAL_DISMEMBER_RESIST
		modified_burn /= LIMB_VITAL_DISMEMBER_RESIST
	if(prior_damage >= max_damage)
		modified_brute *= LIMB_RUINED_DISMEMBER_MULT
		modified_burn *= LIMB_RUINED_DISMEMBER_MULT

	// Eligible when already a third ruined, or when one hit does over half the limb.
	if(prior_damage <= max_damage * LIMB_DISMEMBER_PRIOR_FRACTION && (modified_brute + modified_burn) <= max_damage * LIMB_DISMEMBER_HIT_FRACTION)
		return LIMB_DISMEMBER_INELIGIBLE

	if(nonsolid && damage >= max_damage)
		droplimb(TRUE, DROPLIMB_EDGE)
	else if(is_nanoform() && damage >= max_damage)
		droplimb(TRUE, DROPLIMB_BURN)
	else if(edge_eligible && modified_brute >= max_damage / DROPLIMB_THRESHOLD_EDGE && prob(modified_brute * 0.15) && prob(damage_factor))
		droplimb(FALSE, DROPLIMB_EDGE) // a sharp object
	else if(modified_burn >= max_damage / DROPLIMB_THRESHOLD_DESTROY && prob(modified_burn * 0.75) && prob(damage_factor))
		droplimb(FALSE, DROPLIMB_BURN) // burned off, e.g. a shocking door
	else if(!edge_eligible && modified_brute >= max_damage / DROPLIMB_THRESHOLD_DESTROY && prob(modified_brute * 0.25) && prob(damage_factor))
		droplimb(FALSE, DROPLIMB_BLUNT) // a big blunt weapon (or a wall, enough times)
	else
		return LIMB_DISMEMBER_SPARED
	return LIMB_DISMEMBER_DROPPED

/// Damage a maxed limb couldn't take spreads a third to its children and a third to its parent
/// (spread_dam limbs only). The spread hits are permutations, so they never spread again.
/obj/item/organ/external/proc/spread_overflow(brute_overflow, burn_overflow, list/forbidden_limbs)
	if(!spread_dam || !owner || !parent || (brute_overflow < LIMB_SPREAD_MIN_OVERFLOW && burn_overflow < LIMB_SPREAD_MIN_OVERFLOW))
		return
	var/brute_third = brute_overflow * 0.33
	var/burn_third = burn_overflow * 0.33
	var/obj/item/organ/external/up = parent
	if(length(children))
		var/list/targets = children.Copy() // a child can come off mid-loop
		var/brute_on_children = brute_third / targets.len
		var/burn_on_children = burn_third / targets.len
		for(var/obj/item/organ/external/C as anything in targets)
			if(!QDELETED(C) && !C.is_stump())
				C.apply_wound_damage(brute_on_children, burn_on_children, FALSE, FALSE, null, forbidden_limbs, TRUE)
	if(!QDELETED(up))
		up.apply_wound_damage(brute_third, burn_third, FALSE, FALSE, null, forbidden_limbs, TRUE)

/// Body-internal: heal this limb's wounds directly. Only for a limb that is
/// NOT in a body (repairing a detached prosthetic on the bench); limbs in a
/// body heal through mend().
/obj/item/organ/external/proc/heal_wound_damage(brute, burn, internal = FALSE, robo_repair = FALSE)
	owner?.body?.invalidate(BODY_DIRTY_ORGANS)
	if(is_robotic() && !robo_repair)
		return

	//Heal damage on the individual wounds
	for(var/datum/affliction/wound/W as anything in get_wounds())
		if(brute <= 0 && burn <= 0)
			break
		if(W.damage_type == BURN)
			burn = W.heal_damage(burn)
		else
			brute = W.heal_damage(brute)

	//Sync the organ's damage with its wounds
	src.update_damages()

	var/result = update_damage_state()
	return result

//Helper proc used by various tools for repairing robot limbs
/// Starts repairing this robotic limb with `tool`. TRUE if the repair started; when it
/// completes, `tool_proc` (if any) is called on the tool with `tool_args` (to use up fuel,
/// cable, ...).
/obj/item/organ/external/proc/robo_repair(repair_amount, damage_type, damage_desc, obj/item/tool, mob/living/user, tool_proc, list/tool_args)
	if((!src.is_robotic()))
		return 0

	var/damage_amount
	switch(damage_type)
		if(BRUTE)   damage_amount = get_trauma()
		if(BURN)    damage_amount = get_burn()
		if("omni")  damage_amount = max(get_trauma(), get_burn())
		else return 0

	if(!damage_amount && !disfigured)
		to_chat(user, span_notice("Nothing to fix!"))
		return 0

	if(get_trauma() + get_burn() >= min_broken_damage) // Makes robotic limb damage scalable
		to_chat(user, span_danger("The damage is far too severe to patch over externally."))
		return 0
	/*	// Leaving this here as a reference to how it used to work, but as of now, this just makes self repair for synths extra tedious.
		// Normal meds like brute kits and such dont have this restriction, so this shouldn't have it either.
	if(user == src.owner)
		var/grasp
		if(user.l_hand == tool && (src.body_part & (ARM_LEFT|HAND_LEFT)))
			grasp = BP_L_HAND
		else if(user.r_hand == tool && (src.body_part & (ARM_RIGHT|HAND_RIGHT)))
			grasp = BP_R_HAND

		if(grasp)
			to_chat(user, span_warning("You can't reach your [src.name] while holding [tool] in your [owner.get_bodypart_name(grasp)]."))
			return 0
	*/
	user.setClickCooldown(user.get_attack_speed(tool))
	LAZYSET(robo_repairs, REF(user), list(repair_amount, damage_type, damage_desc, damage_amount, tool_proc, tool_args, REF(user.loc)))
	var/datum/op_result/R = perform_op(user, src, "robo_repair", tool, ORIGIN_SYSTEM)
	if(R?.outcome == ACT_REFUSED)
		LAZYREMOVE(robo_repairs, REF(user))
		return FALSE
	return TRUE

/obj/item/organ/external
	/// REF(repairer) -> list(amount, damage type, description, damage before, tool proc, tool args, REF(where the repairer stood)) of the patch
	/// that repairer has under way.
	var/list/robo_repairs


/obj/item/organ/external/proc/robo_repair_failed(datum/act/op/A)
	LAZYREMOVE(robo_repairs, REF(A.actor))
	to_chat(A.actor, span_warning("You must stand still to do that."))

/obj/item/organ/external/proc/robo_repair_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/tool = A.held
	var/list/record = LAZYACCESS(robo_repairs, REF(user))
	LAZYREMOVE(robo_repairs, REF(user))
	if(!record)
		return
	var/repair_amount = record[1]
	var/damage_type = record[2]
	var/damage_desc = record[3]
	var/damage_amount = record[4]
	var/tool_proc = record[5]
	var/list/tool_args = record[6]
	if(REF(user.loc) != record[7]) // the repairer must stand still for the whole patch
		to_chat(user, span_warning("You must stand still to do that."))
		return
	// Repair by mechanism: plating for structural damage, wiring for scorching.
	if(owner)
		if(damage_type == BRUTE || damage_type == "omni")
			owner.mend(TREAT_PLATING_REPAIR, repair_amount, organ_tag)
		if(damage_type == BURN || damage_type == "omni")
			owner.mend(TREAT_WIRING_REPAIR, repair_amount, organ_tag)
	else
		switch(damage_type)
			if("omni")src.heal_wound_damage(repair_amount, repair_amount, 0, 1)
			if(BRUTE) src.heal_wound_damage(repair_amount, 0, 0, 1)
			if(BURN)  src.heal_wound_damage(0, repair_amount, 0, 1)

	if(damage_desc)
		var/fix_verb = "patches"
		if(damage_amount > repair_amount)
			fix_verb = "finishes patching"
			disfigured = FALSE //Prevents some edgecases where you can repair despite hitting disfigurement thresholds, they're fully healed at this point anyways.
		if(user == src.owner)
			act_message(user, null, others = span_infoplain(span_bold("%U%") + " [fix_verb] [damage_desc] on %THEIR% [src.name] with [tool]."))
		else
			act_message(user, null, others = span_infoplain(span_bold("%U%") + " [fix_verb] [damage_desc] on [owner]'s [src.name] with [tool]."))
	if(tool_proc && tool)
		call(tool, tool_proc)(arglist(list(user) + (tool_args || list())))

/*
This function completely restores a damaged organ to perfect condition.
*/
/obj/item/organ/external/rejuvenate(ignore_prosthetic_prefs)
	damage_state = "00"
	set_status(0)
	germ_level = 0
	for(var/datum/affliction/wound/W as anything in get_wounds())
		remove_wound(W)
	recalc_integrity()

	// handle internal organs
	for(var/obj/item/organ/current_organ in held_organs())
		current_organ.rejuvenate(ignore_prosthetic_prefs)

	// remove embedded objects and drop them on the floor
	for(var/obj/implanted_object in implants)
		if(istype(implanted_object,/obj/item/implant) || istype(implanted_object,/obj/item/nif)) // We don't want to remove REAL implants. Just shrapnel etc. // NIFs pls
			continue
		implanted_object.forceMove(get_turf(src))
		rel_remove(src, nameof(implants), implanted_object)
	if(owner && !owner.has_embedded_objects()) // rejuvenating a detached limb has no owner (D13)
		owner.clear_alert("embeddedobject")

	if(owner && !ignore_prosthetic_prefs)
		if(owner.client && owner.client.prefs && owner.client.prefs.read_preference(/datum/preference/name/real_name) == owner.real_name)
			var/list/organ_data = owner.client.prefs.read_preference(/datum/preference/organ_data)
			var/status = organ_data?[organ_tag]
			if(status == "amputated")
				remove_rejuv()
			else if(status == "cyborg")
				var/list/rlimb_data = owner.client.prefs.read_preference(/datum/preference/rlimb_data)
				var/robodata = rlimb_data?[organ_tag]
				if(robodata)
					robotize(robodata)
				else
					robotize()

/// Lowest-level wound funnel: every limb injury (apply_wound_damage, and through
/// it every injure() call) becomes a wound affliction here. `type` is CUT,
/// PIERCE, BRUISE or BURN. Synthetic limbs get synthetic wounds.
/obj/item/organ/external/proc/create_wound(type = CUT, damage)
	if(damage <= 0)
		return
	var/synthetic = (is_robotic())

	// Injury-driven afflictions (compartment syndrome, burn shock, fractures…).
	// See code/modules/medical/cascades.dm.
	if(owner)
		dq_check_damage_cascades(type, damage)

	//Burn damage can cause fluid loss due to blistering and cook-off
	if(owner && (damage > 5 || damage + get_burn() >= 15) && type == BURN && !synthetic && !(data.get_species_flags() & NO_BLOOD))
		var/fluid_loss = 0.1 * (damage / (2 * owner.get_endurance())) * owner.species.blood_volume*(1 - owner.species.blood_level_fatal) // reduce fluid loss 4-fold so lasers dont suck your blood
		owner.remove_blood(fluid_loss)

	var/list/current_wounds = get_wounds()
	if(integrity_dirty)
		recalc_integrity()
	// first check whether we can widen an existing wound
	if(length(current_wounds) && prob(max(50+(number_wounds-1)*10,90)))
		if((type == CUT || type == BRUISE) && damage >= 5)
			//we need to make sure that the wound we are going to worsen is compatible with the type of damage...
			var/list/compatible_wounds = list()
			for(var/datum/affliction/wound/W as anything in current_wounds)
				if(W.can_worsen(type, damage))
					compatible_wounds += W

			if(compatible_wounds.len)
				var/datum/affliction/wound/W = pick(compatible_wounds)
				W.open_wound(damage)
				if(owner && prob(25))
					if(synthetic)
						owner.visible_message(span_danger("The damage to [owner.name]'s [name] worsens."),						span_danger("The damage to your [name] worsens."),						span_danger("You hear the screech of abused metal."))
					else
						owner.visible_message(span_danger("The wound on [owner.name]'s [name] widens with a nasty ripping noise."),						span_danger("The wound on your [name] widens with a nasty ripping noise."),						span_danger("You hear a nasty ripping noise, as if flesh is being torn apart."))
				return W

	//Creating wound
	var/wound_type = wound_affliction_type(type, damage, synthetic)
	if(!wound_type)
		return
	var/datum/affliction/wound/new_wound = new wound_type(src, damage)

	//Check whether we can add the wound to an existing wound
	for(var/datum/affliction/wound/other as anything in current_wounds)
		if(other.can_merge(new_wound))
			other.merge_wound(new_wound)
			consumed(new_wound)
			return other
	add_wound(new_wound)
	return new_wound

/****************************************************
			   PROCESSING & UPDATING
****************************************************/

//external organs handle brokenness a bit differently when it comes to damage. Instead get_trauma() is checked in update_damages()
//this also ensures that an external organ cannot be "broken" without broken_description being set.
/obj/item/organ/external/is_broken()
	// A splint in place holds the bone: a splinted fracture is not broken for grip and stance.
	return ((status & ORGAN_CUT_AWAY) || (is_fractured() && !(splinted && splinted.loc == src)))

/obj/item/organ/external/organ_tick(cycles)
	if(owner)

		//Chem traces slowly vanish: one point every ten cycles.
		for(var/chemID in trace_chemicals)
			trace_chemicals[chemID] = trace_chemicals[chemID] - 0.1 * cycles
			if(trace_chemicals[chemID] <= 0)
				LAZYREMOVE(trace_chemicals, chemID)

		//Infections
		update_germs(cycles)
	else
		..()

//Updating germ levels. Handles organ germ levels and necrosis.
/*
The INFECTION_LEVEL values defined in setup.dm control the time it takes to reach the different
infection levels. Since infection growth is exponential, you can adjust the time it takes to get
from one germ_level to another using the rough formula:

desired_germ_level = initial_germ_level*e^(desired_time_in_seconds/1000)

So if I wanted it to take an average of 15 minutes to get from level one (100) to level two
I would set INFECTION_LEVEL_TWO to 100*e^(15*60/1000) = 245. Note that this is the average time,
the actual time is dependent on RNG.

INFECTION_LEVEL_ONE		below this germ level nothing happens, and the infection doesn't grow
INFECTION_LEVEL_TWO		above this germ level the infection will start to spread to internal and adjacent organs
INFECTION_LEVEL_THREE	above this germ level the player will take additional toxin damage per second, and will die in minutes without
						antitox. also, above this germ level you will need to overdose on spaceacillin to reduce the germ_level.

Note that amputating the affected organ does in fact remove the infection from the player's body.
*/
/obj/item/organ/external/proc/update_germs(cycles)

	if(is_robotic() || (owner.species && (owner.species.flags & IS_PLANT || (owner.species.flags & NO_INFECT)))) //Robotic limbs shouldn't be infected, nor should nonexistant limbs.
		germ_level = 0
		return

	if(owner.body_temperature() >= 170)	//cryo stops germs from moving and doing their bad stuffs
		//** Syncing germ levels with external wounds
		handle_germ_sync(cycles)

		//** Handle antibiotics and curing infections
		handle_antibiotics(cycles)

		//** Handle the effects of infections
		handle_germ_effects(cycles)

/obj/item/organ/external/proc/handle_germ_sync(cycles)
	if(owner && isbelly(owner.loc)) //If we're in a belly, just skip infection spreading. This leads to extended vore scenes killing via infection.
		return
	var/antibiotics = owner.factor(BF_ANTIMICROBIAL)
	var/list/current_wounds = get_wounds()
	for(var/datum/affliction/wound/W as anything in current_wounds)
		//Open wounds can become infected
		if(owner.germ_level > W.germ_level && W.infection_check())
			W.germ_level += cycles

	if(!antibiotics)
		for(var/datum/affliction/wound/W as anything in current_wounds)
			//Infected wounds raise the organ's germ level
			if (W.germ_level > germ_level)
				adjust_germ_level(cycles)
				break	//limit increase to a maximum of one per second

/obj/item/organ/external/handle_germ_effects(cycles)
	. = ..() //May be null or an infection level, if null then no specific processing needed here
	if(!.) return

	var/antibiotics = owner.factor(BF_ANTIMICROBIAL)

	if(. >= 2 && antibiotics < ANTIBIO_NORM) //INFECTION_LEVEL_TWO
		//spread the infection to internal organs
		var/obj/item/organ/target_organ = null	//make internal organs become infected one at a time instead of all at once
		for (var/obj/item/organ/I in held_organs())
			if (I.germ_level > 0 && I.germ_level < min(germ_level, INFECTION_LEVEL_TWO))	//once the organ reaches whatever we can give it, or level two, switch to a different one
				if (!target_organ || I.germ_level > target_organ.germ_level)	//choose the organ with the highest germ_level
					target_organ = I

		if (!target_organ)
			//figure out which organs we can spread germs to and pick one at random
			var/list/candidate_organs = list()
			for (var/obj/item/organ/I in held_organs())
				if (I.germ_level < germ_level)
					candidate_organs |= I
			if (candidate_organs.len)
				target_organ = pick(candidate_organs)

		if (target_organ)
			target_organ.adjust_germ_level(cycles)

		//spread the infection to child and parent organs
		if (children)
			for (var/obj/item/organ/external/child in children)
				if (child.germ_level < germ_level && (!child.is_robotic()))
					if (child.germ_level < INFECTION_LEVEL_ONE*2 || prob(30))
						child.adjust_germ_level(cycles)

		if (parent)
			if (parent.germ_level < germ_level && (!parent.is_robotic()))
				if (parent.germ_level < INFECTION_LEVEL_ONE*2 || prob(30))
					parent.adjust_germ_level(cycles)

	if(. >= 3 && antibiotics < ANTIBIO_OD)	//INFECTION_LEVEL_THREE
		if (!(status & ORGAN_DEAD))
			set_status(status | ORGAN_DEAD)
			to_chat(owner, span_notice("You can't feel your [name] anymore..."))
			owner.update_icons_body()
			for (var/obj/item/organ/external/child in children)
				child.germ_level += 110 //Burst of infection from a parent organ becoming necrotic

/// Rebuilds limb integrity from its wounds and updates the BLEEDING status
/// and fractures.
/obj/item/organ/external/proc/update_damages()
	recalc_integrity()
	set_status(status & ~ORGAN_BLEEDING)

	var/mob/living/carbon/human/H
	if(ishuman(owner))
		H = owner

	var/can_bleed = !(is_robotic()) && H && H.should_have_organ(O_HEART) && !(H.species.flags & NO_BLOOD)
	if(can_bleed)
		for(var/datum/affliction/wound/W as anything in get_wounds())
			if(W.bleeding())
				set_status(status | ORGAN_BLEEDING)
				break

	// An open, unclamped surgical site bleeds.
	var/datum/affliction/surgical_incision/incision = get_incision()
	if(incision?.is_bleeding() && !flow_occluded())
		set_status(status | ORGAN_BLEEDING)

	//Bone fractures
	if(CONFIG_GET(flag/bones_can_break) && get_trauma() > min_broken_damage * CONFIG_GET(number/organ_health_multiplier) && !(is_robotic()))
		src.fracture()

// new damage icon system
// adjusted to set damage_state to brute/burn code only (without r_name0 as before)
/// Caches damage_state from the limb's damage; TRUE when it changed (the owner's body then redraws).
/obj/item/organ/external/proc/update_damage_state()
	var/n_is = damage_state_text()
	if (n_is != damage_state)
		damage_state = n_is
		return 1
	return 0

// new damage icon system
// returns just the brute/burn damage code
/obj/item/organ/external/proc/damage_state_text()

	var/tburn = 0
	var/tbrute = 0

	var/burns = get_burn()
	var/trauma = get_trauma()
	if(burns == 0)
		tburn = 0
	else if (burns < (max_damage * 0.25 / 2))
		tburn = 1
	else if (burns < (max_damage * 0.75 / 2))
		tburn = 2
	else
		tburn = 3

	if (trauma == 0)
		tbrute = 0
	else if (trauma < (max_damage * 0.25 / 2))
		tbrute = 1
	else if (trauma < (max_damage * 0.75 / 2))
		tbrute = 2
	else
		tbrute = 3
	return "[tbrute][tburn]"

/****************************************************
			   DISMEMBERMENT
****************************************************/

//Handles dismemberment
/obj/item/organ/external/proc/droplimb(clean, disintegrate = DROPLIMB_EDGE, ignore_children = null)

	if(cannot_amputate || !owner)
		return
	if(is_nanoform())
		disintegrate = DROPLIMB_BURN //Ashes will be fine
	else if(disintegrate == DROPLIMB_EDGE && nonsolid)
		disintegrate = DROPLIMB_BLUNT //splut

	GLOB.lost_limbs_shift_roundstat++
	if(owner && !owner.transforming)
		switch(disintegrate)
			if(DROPLIMB_EDGE)
				if(!clean)
					var/gore_sound = "[(is_robotic()) ? "tortured metal" : "ripping tendons and flesh"]"
					owner.visible_message(
						span_danger("\The [owner]'s [src.name] flies off in an arc!"),\
						span_bolddanger("Your [src.name] goes flying off!"),\
						span_danger("You hear a terrible sound of [gore_sound]."))
			if(DROPLIMB_BURN)
				if(cannot_gib)
					return
				var/gore = "[(is_robotic()) ? "": " of burning flesh"]"
				owner.visible_message(
					span_danger("\The [owner]'s [src.name] flashes away into ashes!"),\
					span_bolddanger("Your [src.name] flashes away into ashes!"),\
					span_danger("You hear a crackling sound[gore]."))
			if(DROPLIMB_BLUNT)
				if(cannot_gib)
					return
				var/gore = "[(is_robotic()) ? "": " in shower of gore"]"
				var/gore_sound = "[(status >= ORGAN_ROBOT) ? "rending sound of tortured metal" : "sickening splatter of gore"]"
				owner.visible_message(
					span_danger("\The [owner]'s [src.name] explodes[gore]!"),\
					span_bolddanger("Your [src.name] explodes[gore]!"),\
					span_danger("You hear the [gore_sound]."))

			if(DROPLIMB_ACID)
				if(cannot_gib)
					return
				var/gore = "[(is_robotic()) ? "": " in gush of gore"]"
				var/gore_sound = "[(status >= ORGAN_ROBOT) ? "sizzling sound of melting metal" : "sickening drips of melting flesh"]"
				owner.visible_message(
					span_danger("\The [owner]'s [src.name] sloughs off[gore]!"),\
					span_bolddanger("<b>Your [src.name] sloughs off of your body[gore]!</b>"),\
					span_danger("You hear the [gore_sound]."))

	var/mob/living/carbon/human/victim = owner //Keep a reference for post-removed().
	var/obj/item/organ/external/parent_organ = parent

	var/use_flesh_colour = data.get_species_flesh_colour(owner)
	var/use_blood_colour = data.get_species_blood_colour(owner)

	// Child limbs ride along inside this one unless each is to come off on its
	// own (gibbing): then they go first, leaves before parents.
	if(ignore_children)
		for(var/obj/item/organ/external/child as anything in slot_contents(SLOT_ID_PART_CHILD))
			child.droplimb(clean, disintegrate, TRUE)

	removed(null)
	victim?.adjust_shock(60, "limb loss")

	if(parent_organ)
		var/datum/affliction/wound/lost_limb/W = new (null, src, disintegrate, clean)
		if(clean)
			parent_organ.add_wound(W)
			parent_organ.update_damages()
		else
			// Born in the victim, the stump takes this limb's place on its parent.
			var/obj/item/organ/external/stump/stump = new (victim, 0, src)
			if(is_robotic())
				stump.robotize()
			stump.add_wound(W)
			stump.update_damages()
		victim?.body?.on_status_changed()

	after(victim, 0.1 SECONDS, GLOBAL_PROC_REF(droplimb_refresh_icons), with = list(victim))
	dir = 2

	var/atom/droploc = victim.drop_location()
	switch(disintegrate)
		if(DROPLIMB_EDGE)
			appearance_flags &= ~PIXEL_SCALE
			compile_icon()
			add_blood(victim)
			var/matrix/M = matrix()
			M.Turn(rand(180))
			src.transform = M
			if(!clean)
				// Throw limb around.
				if(src && istype(loc,/turf))
					throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,3),5)
				dir = 2
		if(DROPLIMB_BURN)
			new /obj/effect/decal/cleanable/ash(droploc)
			// Large foreign objects survive the fire; the parts burn with the limb.
			for(var/obj/item/I in slot_contents())
				if(I.w_class > ITEMSIZE_SMALL && !istype(I,/obj/item/organ))
					slot_remove(I, droploc, null, LEDGER_MOVE_FORCED)
			destroyed(src, null, BURN)
		if(DROPLIMB_BLUNT)
			var/obj/effect/decal/cleanable/blood/gibs/gore
			if(is_robotic())
				gore = new /obj/effect/decal/cleanable/blood/gibs/robot(droploc)
			else
				gore = new /obj/effect/decal/cleanable/blood/gibs(droploc)
				gore.set_fleshcolor(use_flesh_colour)
				gore.set_basecolor(use_blood_colour)

			gore.throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,3),5)

			// Everything in the limb, organs and child limbs included, is flung out.
			for(var/atom/movable/thing as anything in slot_contents())
				if(slot_remove(thing, droploc, null, LEDGER_MOVE_FORCED))
					thing.throw_at(get_edge_target_turf(src,pick(GLOB.alldirs)),rand(1,3),5)

			destroyed(src, null, BRUTE)

		if(DROPLIMB_ACID)
			appearance_flags &= ~PIXEL_SCALE
			compile_icon()
			add_blood(victim)
			var/matrix/M = matrix()
			M.Turn(rand(180))
			transform = M

	if(victim.get_equipped_item(SLOT_ID_HAND_L))
		if(istype(victim.get_equipped_item(SLOT_ID_HAND_L),/obj/item/material/twohanded)) //if they're holding a two-handed weapon, drop it now they've lost a hand
			victim.get_equipped_item(SLOT_ID_HAND_L).update_held_icon()
	if(victim.get_equipped_item(SLOT_ID_HAND_R))
		if(istype(victim.get_equipped_item(SLOT_ID_HAND_R),/obj/item/material/twohanded))
			victim.get_equipped_item(SLOT_ID_HAND_R).update_held_icon()

/****************************************************
			   HELPERS
****************************************************/

/obj/item/organ/external/proc/is_stump()
	return 0

/obj/item/organ/external/proc/release_restraints(mob/living/carbon/human/holder)
	if(!holder)
		holder = owner
	if(!holder)
		return
	if (holder.get_equipped_item(SLOT_ID_HANDCUFFED) && (body_part in list(ARM_LEFT, ARM_RIGHT, HAND_LEFT, HAND_RIGHT)))
		act_message(holder, null, MSG_SELF("\The [holder.get_equipped_item(SLOT_ID_HANDCUFFED).name] falls off you."), \
			MSG_OTHERS("\The [holder.get_equipped_item(SLOT_ID_HANDCUFFED).name] falls off of [holder.name]."))
		holder.drop_from_inventory(holder.get_equipped_item(SLOT_ID_HANDCUFFED))
	if (holder.get_equipped_item(SLOT_ID_LEGCUFFED) && (body_part in list(FOOT_LEFT, FOOT_RIGHT, LEG_LEFT, LEG_RIGHT)))
		act_message(holder, null, MSG_SELF("\The [holder.get_equipped_item(SLOT_ID_LEGCUFFED).name] falls off you."), \
			MSG_OTHERS("\The [holder.get_equipped_item(SLOT_ID_LEGCUFFED).name] falls off of [holder.name]."))
		holder.drop_from_inventory(holder.get_equipped_item(SLOT_ID_LEGCUFFED))

// checks if all wounds on the organ are bandaged
/obj/item/organ/external/proc/is_bandaged()
	for(var/datum/affliction/wound/W as anything in get_wounds())
		if(W.internal) continue
		if(!W.bandaged)
			return 0
	return 1

// checks if all wounds on the organ are salved
/obj/item/organ/external/proc/is_salved()
	for(var/datum/affliction/wound/W as anything in get_wounds())
		if(W.internal) continue
		if(!W.salved)
			return 0
	return 1

// checks if all wounds on the organ are disinfected
/obj/item/organ/external/proc/is_disinfected()
	for(var/datum/affliction/wound/W as anything in get_wounds())
		if(W.internal) continue
		if(!W.disinfected)
			return 0
	return 1

/obj/item/organ/external/proc/bandage()
	var/rval = 0
	set_status(status & ~ORGAN_BLEEDING)
	for(var/datum/affliction/wound/W as anything in get_wounds())
		if(W.internal) continue
		rval |= !W.bandaged
		W.bandage()
	return rval

/obj/item/organ/external/proc/salve()
	var/rval = 0
	for(var/datum/affliction/wound/W as anything in get_wounds())
		rval |= !W.salved
		W.salve()
	return rval

/obj/item/organ/external/proc/disinfect()
	var/rval = 0
	for(var/datum/affliction/wound/W as anything in get_wounds())
		if(W.internal) continue
		rval |= !W.disinfected
		W.disinfect()
		W.germ_level = 0
	return rval

/obj/item/organ/external/proc/organ_clamp()
	var/rval = 0
	src.set_status(src.status & ~ORGAN_BLEEDING)
	for(var/datum/affliction/wound/W as anything in get_wounds())
		if(W.internal) continue
		rval |= !W.clamped
		W.clamped = 1
	return rval

/// The limb's fracture IS its untreated_fracture affliction: present means
/// broken. Robot limbs don't fracture.
/obj/item/organ/external/is_fractured()
	return !!owner?.body?.find_affliction(/datum/affliction/untreated_fracture, src)

/// Break the bone: afflict the limb with a fracture.
/obj/item/organ/external/proc/fracture()
	if(is_robotic())
		return
	if(!owner?.body || is_fractured() || cannot_break)
		return
	if(!owner.body.afflict(/datum/affliction/untreated_fracture, src, FRACTURE_INITIAL_SEVERITY))
		return

	if(owner)
		var/show_message = TRUE
		var/scream = TRUE
		if(!organ_can_feel_pain() || owner.transforming)
			show_message = FALSE
			scream = FALSE
		if(isbelly(owner.loc) || isliving(owner.loc))
			scream = FALSE
			if(!owner.digest_pain)
				show_message = FALSE

		if(show_message)
			owner.custom_pain(pick(\
				span_danger("You hear a loud cracking sound coming from \the [owner]."),\
				span_danger("Something feels like it shattered in your [name]!"),\
				span_danger("You hear a sickening crack.")), brokenpain)
			if(scream)
				owner.emote("scream")
		jostle_bone()

	if(istype(owner.loc, /obj/belly)) // bone breaks in bellys should be whisper range to prevent bar wide blender prefbreak. This is a hacky passive hardcode, if a pref gets added, remove this if else
		play_sfx(src, SFX_FRACTURE, extrarange = -6.5)
	else
		play_sfx(src, SFX_FRACTURE) // Much more audible bonebreaks.
	log_runtime("FRACTURE: [key_name(owner)] fractured their [name].")
	broken_description = pick("broken","fracture","hairline fracture")

	// Fractures have a chance of getting you out of restraints
	if (prob(25))
		release_restraints()

	// This is mostly for the ninja suit to stop ninja being so crippled by breaks.
	// TODO: consider moving this to a suit proc or process() or something during
	// hardsuit rewrite.

	if(!(splinted) && owner && istype(owner.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/space))
		var/obj/item/clothing/suit/space/suit = owner.get_equipped_item(SLOT_ID_SUIT)
		suit.handle_fracture(owner, src)

	return 1

/// Knit the bone at once (magic and chemical bone heals): cure the fracture
/// affliction. Surgery sets bones through TREAT_BONE_SETTING instead.
/obj/item/organ/external/proc/mend_fracture()
	if(is_robotic())
		return 0
	if(get_trauma() > min_broken_damage * CONFIG_GET(number/organ_health_multiplier))
		return 0	//will just immediately fracture again
	var/datum/affliction/untreated_fracture/F = owner?.body?.find_affliction(/datum/affliction/untreated_fracture, src)
	if(!F)
		return 0
	F.cure()
	log_runtime("FRACTURE: [key_name(owner)]'s [name] fracture mended.")
	return 1

/obj/item/organ/external/proc/apply_splint(atom/movable/splint)
	if(!splinted)
		rel_set(src, nameof(splinted), splint)
		if(!applied_pressure)
			rel_set(src, nameof(applied_pressure), splint)
		refresh_fracture_support()
		return 1
	return 0

/obj/item/organ/external/proc/remove_splint()
	if(splinted)
		if(splinted.loc == src)
			splinted.dropInto(owner? owner.loc : src.loc)
		if(applied_pressure == splinted)
			rel_clear(src, nameof(applied_pressure))
		rel_clear(src, nameof(splinted))
		refresh_fracture_support()
		return 1
	return 0

/obj/item/organ/external/robotize(company, skip_prosthetics = 0, keep_organs = 0)

	// Sideways handling for nanoform limbs (ugh): temporarily clear the robotic
	// flag so the guard below passes, force-keep organs, and restore the
	// nanoform vars afterwards.
	var/original_robotic = robotic
	var/restore_nanoform = is_nanoform()
	var/o_encased
	var/o_max_damage
	var/o_min_broken_damage
	if(restore_nanoform)
		o_encased = encased
		o_max_damage = max_damage
		o_min_broken_damage = min_broken_damage
		set_robotic(FALSE)
		keep_organs = TRUE

	if(is_robotic())
		return

	..()

	if(company)
		model = company
		var/datum/robolimb/R = GLOB.all_robolimbs[company]
		if(!R || (data.get_species_name() in R.species_cannot_use))
			R = GLOB.basic_robolimb
		if(R)
			force_icon = R.icon
			brute_mod *= R.robo_brute_mod
			burn_mod *= R.robo_burn_mod
			skip_robo_icon = R.no_icon
			digi_prosthetic = R.can_be_digitigrade
			if(R.lifelike)
				set_robotic(ORGAN_LIFELIKE)
				name = "[initial(name)]"
			else if(R.modular_bodyparts == MODULAR_BODYPART_PROSTHETIC)
				name = "prosthetic [initial(name)]"
			else
				name = "robotic [initial(name)]"
			desc = "[R.desc] It looks like it was produced by [R.company]."

	dislocated = -1
	cannot_break = 1
	min_broken_damage = ROBOLIMB_REPAIR_CAP // ition - Makes robotic limb damage scalable
	remove_splint()
	get_icon()
	unmutate()
	drop_sound = SFX_ITEMS_DROP_WELDINGTOOL
	pickup_sound = SFX_ITEMS_PICKUP_WELDINGTOOL

	for(var/obj/item/organ/external/T in children)
		T.robotize(company, keep_organs = keep_organs)

	if(owner)

		if(!keep_organs)
			// Deleting an organ detaches it (the hook clears every cache).
			for(var/obj/item/organ/thing as anything in slot_contents(SLOT_ID_PART_ORGANS))
				if(!thing.vital)
					replaced_by(thing)

		owner.refresh_modular_limb_verbs()

	if(restore_nanoform)
		set_robotic(original_robotic)
		encased = o_encased
		set_max_damage(o_max_damage)
		min_broken_damage = o_min_broken_damage

	shed_mismatched_afflictions()
	return 1

/obj/item/organ/external/proc/mutate()
	if(src.is_robotic())
		return
	src.set_status(src.status | ORGAN_MUTATED)
	if(owner) owner.update_icons_body()

/obj/item/organ/external/proc/unmutate()
	src.set_status(src.status & ~ORGAN_MUTATED)
	if(owner) owner.update_icons_body()

/obj/item/organ/external/proc/get_damage()	//returns total damage
	return (get_trauma() + get_burn())	//could use max_damage?

/obj/item/organ/external/proc/has_infected_wound()
	for(var/datum/affliction/wound/W as anything in get_wounds())
		if(W.germ_level > INFECTION_LEVEL_ONE)
			return 1
	return 0

/obj/item/organ/external/proc/is_usable()
	return !(status & (ORGAN_MUTATED|ORGAN_DEAD))

/obj/item/organ/external/proc/is_malfunctioning()
	var/total = get_trauma() + get_burn()
	return ((is_robotic()) && total >= min_broken_damage*0.83 && prob(total)) // Makes robotic limb damage scalable

/obj/item/organ/external/proc/embed(obj/item/W, silent = 0)
	if(!owner)
		return
	if(in_godmode(owner)) //Normally we'd let this proc continue on, but it's much less time consumptive to just do a godmode check here.
		return 0
	if(!silent)
		owner.visible_message(span_danger("\The [W] sticks in the wound!"))
	rel_add(src, nameof(implants), W)
	owner.embedded_flag = 1
	grant(owner, granted_verb(/mob/proc/yank_out_object), owner)
	owner.throw_alert("embeddedobject", /atom/movable/screen/alert/embeddedobject)
	W.add_blood(owner)
	if(ismob(W.loc))
		var/mob/living/H = W.loc
		H.drop_from_inventory(W)
	W.forceMove(owner)

/// Severs this limb, with everything below it, onto the floor (the base
/// removed() moves it; the detach hook releases the subtree). Implants still
/// kept in the mob for this limb and the limbs below it come too, until O3c
/// moves implants into the limb's implant slot.
/obj/item/organ/external/removed(mob/living/user)
	if(!owner)
		return FALSE
	var/is_robotic = is_robotic()
	var/mob/living/carbon/human/victim = owner

	// What the subtree wears has nothing to hang on once it goes. Before the
	// move: the detach hook runs inside it and must not move anything.
	var/list/subtree = dq_part_subtree(src)
	if(istype(victim))
		for(var/obj/item/organ/external/E in subtree)
			E.drop_worn(victim)

	if(!..())
		return FALSE

	for(var/obj/item/organ/external/E in subtree)
		E.shed_mob_implants(victim)

	if(!istype(victim))
		return TRUE // a loose limb on a mob with no part tree (butchery)
	release_restraints(victim)

	//Robotic limbs explode if sabotaged.
	if(is_robotic && sabotaged)
		act_message(victim, null, MSG_SELF(span_danger("Your [src.name] explodes!")), \
			MSG_OTHERS(span_danger("%U%'s [src.name] explodes violently!")), \
			MSG_BLIND(span_danger("You hear an explosion!")))
		// owner is already null here (the base removed() detached us): use victim (audit D4).
		explosion(get_turf(victim),-1,-1,2,3)
		fx_sparks(victim, 5, FALSE)
		// droplimb() keeps using this limb after removed() returns; delete it once that unwinds.
		expire(0.1 SECONDS)

	victim.update_icons_body()
	return TRUE

/// Drops what `victim` wears on this limb, which is about to be severed.
/obj/item/organ/external/proc/drop_worn(mob/living/carbon/human/victim)
	return

/// Implants recorded on this limb but kept in `victim` (not yet in the limb's
/// implant slot, O3c): small ones fall to the floor, the rest go with the limb.
/obj/item/organ/external/proc/shed_mob_implants(mob/living/victim)
	for(var/atom/movable/implant in implants)
		if(implant.loc != victim)
			continue
		var/obj/item/I = implant
		if(istype(I) && I.w_class < ITEMSIZE_NORMAL)
			implant.forceMove(get_turf(victim))
		else
			implant.forceMove(src)
	rel_clear(src, nameof(implants))

/obj/item/organ/external/proc/disfigure(type = "brute")
	if (disfigured)
		return
	if(owner)
		if(type == "brute")
			owner.visible_message(span_danger("You hear a sickening cracking sound coming from \the [owner]'s [name]."),	\
			span_danger("Your [name] becomes a mangled mess!"),	\
			span_danger("You hear a sickening crack."))
		else
			owner.visible_message(span_danger("\The [owner]'s [name] melts away, turning into mangled mess!"),	\
			span_danger("Your [name] melts away!"),	\
			span_danger("You hear a sickening sizzle."))
	disfigured = 1

/obj/item/organ/external/proc/jostle_bone(force)
	if(!is_fractured()) //intact bones stay still
		return
	var/trauma = get_trauma()
	if(trauma + force < min_broken_damage/5)	//no papercuts moving bones
		return
	if(length(held_organs()) && prob(trauma + force) && !owner.transforming)
		owner.custom_pain("A piece of bone in your [encased ? encased : name] moves painfully!", 50)
		var/obj/item/organ/internal/I = pick(held_organs())
		if(istype(I))
			I.apply_lesion_damage(rand(3,5), /datum/affliction/lesion/laceration)

/obj/item/organ/external/proc/get_wounds_desc()
	. = ""
	if(status & ORGAN_DESTROYED && !is_stump())
		. += "tear at [amputation_point] so severe that it hangs by a scrap of flesh"

	//Handle robotic and synthetic organ damage
	if(is_robotic())
		var/LL //Life-Like, aka only show that it's robotic in heavy damage
		if(robotic >= ORGAN_LIFELIKE)
			LL = 1
		var/trauma = get_trauma()
		var/burns = get_burn()
		if(trauma)
			switch(trauma)
				if(0 to 20)
					. += "some [LL ? "cuts" : "dents"]"
				if(21 to INFINITY)
					. += "[LL ? pick("exposed wiring","torn-back synthflesh") : pick("a lot of dents","severe denting")]"

		if(trauma && burns)
			. += " and "

		if(burns)
			switch(burns)
				if(0 to 20)
					. += "some burns"
				if(21 to INFINITY)
					. += "[LL ? pick("roasted synth-flesh","melted internal wiring") : pick("many burns","scorched metal")]"

		if(open)
			if(trauma || burns)
				. += " and "
			if(open == 1)
				. += "some exposed screws"
			else
				. += "an open panel"

		return

	//Normal organic organ damage
	var/list/wound_descriptors = list()
	if(open > 1)
		wound_descriptors["an open incision"] = 1
	else if (open)
		wound_descriptors["an incision"] = 1
	for(var/datum/affliction/wound/W as anything in get_wounds())
		if(W.internal && !open) continue // can't see internal wounds
		var/this_wound_desc = W.desc

		if(W.damage_type == BURN && W.salved)
			this_wound_desc = "salved [this_wound_desc]"

		if(W.bleeding())
			this_wound_desc = "bleeding [this_wound_desc]"
		else if(W.bandaged && W.damage > 0)
			this_wound_desc = "bandaged [this_wound_desc]"

		if(W.germ_level > 600)
			this_wound_desc = "badly infected [this_wound_desc]"
		else if(W.germ_level > 330)
			this_wound_desc = "lightly infected [this_wound_desc]"

		if(wound_descriptors[this_wound_desc])
			wound_descriptors[this_wound_desc] += W.amount
		else
			wound_descriptors[this_wound_desc] = W.amount

	if(wound_descriptors.len)
		var/list/flavor_text = list()
		var/static/list/no_exclude = list("gaping wound", "big gaping wound", "massive wound", "large bruise",\
		"huge bruise", "massive bruise", "severe burn", "large burn", "deep burn", "carbonised area") //note to self make this more robust
		for(var/wound in wound_descriptors)
			switch(wound_descriptors[wound])
				if(1)
					flavor_text += "[prob(10) && !(wound in no_exclude) ? "what might be " : ""]a [wound]"
				if(2)
					flavor_text += "[prob(10) && !(wound in no_exclude) ? "what might be " : ""]a pair of [wound]s"
				if(3 to 5)
					flavor_text += "several [wound]s"
				if(6 to INFINITY)
					flavor_text += "a ton of [wound]\s"
		return english_list(flavor_text)

// Returns a list of the clothing (not glasses) that are covering this part
/// Clothing and accessories over this limb (or over `target_covering`, a body
/// part flag such as FACE or EYES): the owner's covering_items().
/obj/item/organ/external/proc/get_covering_clothing(target_covering)
	return owner ? owner.covering_items(target_covering || body_part) : list()

/mob/living/carbon/human/proc/has_embedded_objects()
	. = 0
	for(var/obj/item/organ/external/L in organs)
		for(var/obj/item/I in L.implants)
			if(!istype(I,/obj/item/implant) && !istype(I,/obj/item/nif)) // NIFs
				return 1

/obj/item/organ/external/proc/is_hidden_by_sprite_accessory(clothing_only = FALSE)			// Clothing only will mean the check should only be used in places where we want to hide clothing icon, not organ itself.
	if(owner && owner.tail_style && owner.tail_style.hide_body_parts && (organ_tag in owner.tail_style.hide_body_parts))
		return 1
	if(clothing_only && LAZYLEN(markings))
		for(var/M in markings)
			if(!markings[M]["on"]) //If the marking is off, the organ isn't hidden by it.
				continue
			var/datum/sprite_accessory/marking/mark = markings[M]["datum"]
			if(mark.hide_body_parts && (organ_tag in mark.hide_body_parts))
				return 1

#undef DROPLIMB_THRESHOLD_EDGE
#undef DROPLIMB_THRESHOLD_DESTROY

/obj/item/organ/external/digitize(company, skip_prosthetics = FALSE, keep_organs = FALSE)
	robotize(company, skip_prosthetics, keep_organs)

/// A tick after a limb comes off, the body's icons catch up.
/proc/droplimb_refresh_icons(mob/living/victim)
	if(ishuman(victim))
		var/mob/living/carbon/human/H = victim
		H.UpdateDamageIcon()
		H.update_icons_body()
	else
		victim.update_icons()

#undef LIMB_SPILL_SHARP_BRUTE
#undef LIMB_SPILL_BLUNT_BRUTE
#undef LIMB_SPILL_CHANCE
#undef LIMB_VITAL_DISMEMBER_RESIST
#undef LIMB_RUINED_DISMEMBER_MULT
#undef LIMB_DISMEMBER_PRIOR_FRACTION
#undef LIMB_DISMEMBER_HIT_FRACTION
#undef LIMB_SPREAD_MIN_OVERFLOW
#undef LIMB_DISMEMBER_INELIGIBLE
#undef LIMB_DISMEMBER_SPARED
#undef LIMB_DISMEMBER_DROPPED

