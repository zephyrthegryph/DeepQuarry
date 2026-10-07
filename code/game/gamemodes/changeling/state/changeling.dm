///Changeling antag state (owned plain datum held by the living mob).
///Stores changeling powers, changeling recharge thingie, changeling absorbed DNA and changeling ID (for changeling hivemind)
GLOBAL_LIST_INIT(possible_changeling_IDs,list("Alpha","Beta","Chi","Delta","Epsilon","Eta","Gamma","Iota","Kappa","Lambda","Mu","Nu","Omega","Omicron","Phi","Pi","Psi","Rho","Sigma","Tau","Theta","Upsilon","Xi","Zeta")) //ALPHABETICAL ORDER.

//Needs cleanup
GLOBAL_LIST_INIT(changeling_powers, subtypesof(/datum/power/changeling)) //needed for the badmin verb for now
GLOBAL_LIST_EMPTY_TYPED(powerinstances, /datum/power/changeling)

/datum/power			//Could be used by other antags too
	var/name = "Power"
	var/desc = "Placeholder"
	var/helptext = ""
	var/enhancedtext = ""
	var/isVerb = 1 	// Is it an active power, or passive?
	var/verbpath // Path to a verb that contains the effects.
	var/make_hud_button = TRUE // Is this ability significant enough to dedicate screen space for a HUD button?
	var/ability_icon_state = null // icon_state for icons for the ability HUD.  Must be in screen_spells.dmi.

/datum/power/changeling
	var/allowduringlesserform = FALSE
	var/genomecost = 500000 // Cost for the changeling to evolve this power.

/// Changeling antag state. Owned by the changeling mob (/mob/living var changeling_state); the mind keeps a relation view.
/datum/changeling
	var/mob/living/owner
	var/list/datum/absorbed_dna/absorbed_dna = list() // ALLOW(instance_list): d: changeling state; starts with the changeling's own DNA
	var/list/absorbed_languages // Necessary because of set_species stuff
	var/absorbedcount = 0
	var/lingabsorbedcount = 1	//Starts at one, because that's us
	var/chem_charges = 20
	var/chem_recharge_rate = 0.5
	var/chem_storage = 50
	var/sting_range = 1
	var/changelingID = "Changeling"
	var/geneticdamage = 0
	var/isabsorbing = FALSE
	var/geneticpoints = 7
	var/max_geneticpoints = 7
	var/readapts = 1
	var/max_readapts = 2
	var/list/purchased_powers
	var/cloaked = FALSE
	var/is_reviving = FALSE
	var/armor_deployed = FALSE //This is only used for changeling_generic_equip_all_slots() at the moment.
	var/recursive_enhancement = FALSE //Used to power up other abilities from the ling power with the same name.
	var/list/purchased_powers_history //Used for round-end report, includes respec uses too.
	var/thermal_sight = FALSE	// Is our Vision Augmented? With thermals?
	var/datum/changeling_panel/power_panel //Our changeling eveolution panel. Generated the first time we try to open the panel.
	var/cooldown_time = 1 SECOND // Sting anti-spam.
	COOLDOWN_DECLARE(sting_cooldown) // world.time when we used last used a power.
	var/list/changeling_cooldowns = list( // ALLOW(instance_list): d: edited in place per instance (1 writers)
		CRYO_STING = 0,
		ESCAPE_RESTRAINTS = 0,
		FAKE_DEATH = 0,
		FLESHMEND = 0,
		CHANGELING_SCREECH = 0
	)

CAPABILITIES(/datum/changeling)
	owns_one(nameof(power_panel), /datum/changeling_panel)
	owns_many(nameof(absorbed_dna), /datum/absorbed_dna)

///Checks if a mind or a mob is a changeling.
///Checks to see if the thing fed to it is a changeling first, then does some deeper searching.
/proc/is_changeling(mob/M)
	var/datum/changeling/changeling = ismob(M) ? M.get_changeling_state() : null
	if(changeling) // Whatever we fed it is a changeling. Return it.
		return changeling

	//The below is what happens if we fail the above. We do some deeper searching.
	if(istype(M, /datum/mind)) //Fed a mind and we failed.
		var/datum/mind/our_mind = M
		if(our_mind.current)
			changeling = our_mind.current.get_changeling_state() //Check to see if the mob we are currently inhabiting is a changeling.
	else //Fed it a mob and we failed
		if(M.mind)
			changeling = M.mind.antag_holder.changeling() //Check our mind's antag holder.
	return changeling

///Handles the cooldown for the power. Returns TRUE if the cooldown has passed. FALSE if it's still on cooldown.
///This is just a general anti-spam thing and not really a true cooldown

/datum/changeling/proc/check_cooldown()
	if(COOLDOWN_FINISHED(src, sting_cooldown))
		return TRUE
	return FALSE

/datum/changeling/proc/set_sting_cooldown()
	COOLDOWN_START(src, sting_cooldown, cooldown_time)

/datum/changeling/proc/get_cooldown(id)
	return changeling_cooldowns[id]

/datum/changeling/proc/set_cooldown(id, cooldown_time)
	changeling_cooldowns[id] = EXPIRY_AT(src, CLOCK_WORLD, cooldown_time)

/datum/changeling/proc/is_on_cooldown(id)
	// ALLOW(cooldown): per-ability cooldown table keyed by id (one var per ability would be dozens)
	return (world.time < changeling_cooldowns[id])

/// The voice we mimic, or "". Costs a chemical every 4 seconds while set (mimic_voice.dm, DECLARE_REPEAT).
OM_FIELD(/datum/changeling, mimicing, "", CHANGE_DATUM_A)
/// Digital camouflage we turned on. Costs a chemical every 4 seconds while set (digital_camo.dm, DECLARE_REPEAT).
OM_FIELD(/datum/changeling, camo_draining, FALSE, CHANGE_DATUM_A)

/datum/changeling/New(mob/living/new_owner)
	..()
	lifecycle_decls_init(src) // starts the chemical drain declarations (a non-atom has no materialize)
	rel_set(src, nameof(owner), new_owner)
	if(owner)
		if(GLOB.possible_changeling_IDs.len)
			changelingID = pick(GLOB.possible_changeling_IDs)
			GLOB.possible_changeling_IDs -= changelingID
			changelingID = "[changelingID]"
		else
			changelingID = "[rand(1,999)]"

		grant(owner, granted_verb(/mob/proc/EvolutionMenu), src)
		grant(owner, granted_verb(/mob/proc/changeling_respec), src)
		owner.add_language("Changeling")

//Former /datum/changeling procs
/datum/changeling/proc/regenerate()
	chem_charges = min(max(0, chem_charges+chem_recharge_rate), chem_storage)
	geneticdamage = max(0, geneticdamage-1)

/datum/changeling/proc/GetDNA(dna_owner)
	for(var/datum/absorbed_dna/DNA in absorbed_dna)
		if(dna_owner == DNA.name)
			return DNA

//Former /mob procs
/mob/proc/absorbDNA(datum/absorbed_dna/newDNA)
	var/datum/changeling/comp = is_changeling(src)
	if(!comp)
		return

	for(var/language in newDNA.languages)
		LAZYOR(comp.absorbed_languages, language)

	changeling_update_languages(comp.absorbed_languages)

	if(!comp.GetDNA(newDNA.name)) // Don't duplicate - I wonder if it's possible for it to still be a different DNA? DNA code could use a rewrite
		rel_add(comp, nameof(comp.absorbed_dna), newDNA)

//Restores our verbs. It will only restore verbs allowed during lesser (monkey) form if we are not human
/mob/proc/make_changeling()

	if(!mind)
		return
	//The current mob is made a changeling AND the mind is made a changeling.
	var/datum/changeling/comp = get_changeling_state()
	if(!comp)
		if(!isliving(src)) // Changeling state only lives on /mob/living (was COMPONENT_INCOMPATIBLE).
			log_world("make_changeling: [src] ([type]) is not a living mob; no changeling state created.")
			return
		var/mob/living/living_self = src
		comp = new /datum/changeling(living_self)
		rel_set(living_self, nameof(living_self.changeling_state), comp)
	rel_set(mind.antag_holder, nameof(/datum/antag_holder::changeling), comp)
	var/lesser_form = !ishuman(src)

	if(!GLOB.powerinstances.len)
		for(var/P in GLOB.changeling_powers)
			GLOB.powerinstances += new P()

	// Code to auto-purchase free powers.
	for(var/datum/power/changeling/P in GLOB.powerinstances)
		if(!P.genomecost) // Is it free?
			if(!(P in comp.purchased_powers)) // Do we not have it already?
				comp.purchasePower(comp.owner, P.name, 0)// Purchase it. Don't remake our verbs, we're doing it after this.

	for(var/datum/power/changeling/P in comp.purchased_powers)
		if(P.isVerb)
			if(lesser_form && !P.allowduringlesserform)
				continue
			if(!(P in src.verbs))
				grant(src, granted_verb(P.verbpath), comp)
			if(P.make_hud_button)
				if(!src.ability_master)
					rel_set(src, nameof(ability_master), new /atom/movable/screen/movable/ability_master(src))
				src.ability_master.add_ling_ability(
					object_given = src,
					verb_given = P.verbpath,
					name_given = P.name,
					ability_icon_given = P.ability_icon_state,
					arguments = list()
					)

	for(var/language in languages)
		LAZYOR(comp.absorbed_languages, language)

	var/mob/living/carbon/human/H = src
	if(istype(H))
		grant(H, granted_verb(/mob/living/carbon/human/proc/innate_shapeshifting), comp)
		var/saved_dna = H.dna.Clone() /// Prevent transform from breaking.
		var/datum/absorbed_dna/newDNA = new(H.real_name, saved_dna, H.species.name, H.languages, H.identifying_gender, H.flavor_texts, H.identity()?.genetic_effects?.Copy())
		absorbDNA(newDNA)

		//Code to make it so our BR is marked as a changeling body, so it can't be stolen.
		for(var/key in SStranscore.databases)
			var/datum/transcore_db/db = SStranscore.databases[key]
			if(H.mind.name in db.body_scans)
				var/datum/transhuman/body_record/BR = db.body_scans[H.mind.name]
				BR.changeling_locked = TRUE

	return TRUE

//removes our changeling verbs
/mob/proc/remove_changeling_powers()
	if(!mind)
		return
	var/datum/changeling/comp = is_changeling(src)
	if(!comp)
		return
	for(var/datum/power/changeling/P in comp.purchased_powers)
		if(P.isVerb)
			revoke(src, granted_verb(P.verbpath), comp)
			var/atom/movable/screen/ability/verb_based/changeling/C = ability_master.get_ability_by_proc_ref(P.verbpath)
			if(C)
				ability_master.remove_ability(C)

//Helper proc. Does all the checks and stuff for us to avoid copypasta
/mob/proc/changeling_power(required_chems=0, required_dna=0, max_genetic_damage=100, max_stat=0)

	if(!src.mind)		return
	if(!isliving(src))	return

	var/datum/changeling/comp = is_changeling(src)
	if(!comp)
		log_world("[src] used a changeling verb but is not a changeling.")
		return

	if(src.stat > max_stat)
		to_chat(src, span_warning("We are incapacitated."))
		return

	if(comp.absorbed_dna.len < required_dna)
		to_chat(src, span_warning("We require at least [required_dna] samples of compatible DNA."))
		return

	if(comp.chem_charges < required_chems)
		to_chat(src, span_warning("We require at least [required_chems] units of chemicals to do that!"))
		return

	if(comp.geneticdamage > max_genetic_damage)
		to_chat(src, span_warning("Our genomes are still reassembling. We need time to recover first."))
		return

	return comp

//Used to dump the languages from the changeling datum into the actual mob.
/mob/proc/changeling_update_languages(updated_languages)
	languages = list()
	for(var/language in updated_languages)
		languages += language
	sync_language_state()

	//This isn't strictly necessary but just to be safe...
	add_language("Changeling")

	//////////
	//STINGS//	//They get a pretty header because there's just so fucking many of them ;_;
	//////////

/mob/proc/sting_can_reach(mob/M as mob, sting_range = 1)
	if(M.loc == loc)
		return 1 //target and source are in the same thing
	if(!isturf(loc) || !isturf(M.loc))
		to_chat(src, span_warning("We cannot reach \the [M] with a sting!"))
		return 0 //One is inside, the other is outside something.
	// Maximum queued turfs set to 25; I don't *think* anything raises sting_range above 2, but if it does the 25 may need raising
	if(!AStar(loc, M.loc, /turf/proc/AdjacentTurfsRangedSting, /turf/proc/Distance, max_nodes=25, max_node_depth=sting_range)) //If we can't find a path, fail
		to_chat(src, span_warning("We cannot find a path to sting \the [M] by!"))
		return 0
	return 1

//Handles the general sting code to reduce on copypasta (seeming as somebody decided to make SO MANY dumb abilities)
/mob/proc/changeling_sting(required_chems=0, then_proc, mob/living/carbon/selected_target, list/captured)
	var/datum/changeling/comp = changeling_power(required_chems)
	if(!comp)
		return
	if(!comp.check_cooldown())
		to_chat(src, span_warning("We are still recovering from our last sting."))
		return

	var/list/victims = list()
	for(var/mob/living/carbon/C in oview(comp.sting_range, src))
		victims += C
	if(isnull(selected_target))
		open_request(src, /datum/prompt/choice/changeling_sting_target, then_proc, answerer = src, choices = victims, captured = captured)
		return
	var/mob/living/carbon/T = selected_target

	if(!T)
		to_chat(src, span_warning("We have no targets in range to sting!"))
		return
	if(!comp.check_cooldown())//Check again in case we have multiple windows open at once.
		to_chat(src, span_warning("We are still recovering from our last sting."))
		return
	if(HAS_SYNTHETIC_BIOLOGY(T))
		to_chat(src, span_notice("We are unable to pierce the outer shell of [T]."))
		return
	if(!(T in view(comp.sting_range, src))) return
	if(!sting_can_reach(T, comp.sting_range)) return
	if(!changeling_power(required_chems)) return

	comp.chem_charges -= required_chems
	comp.sting_range = 1
	comp.set_sting_cooldown()

	to_chat(src, span_notice("We stealthily sting [T]."))
	var/datum/changeling/target_comp = is_changeling(T)
	if(!T.mind || !target_comp)
		return T	//T will be affected by the sting
	to_chat(T, span_warning("You feel a tiny prick.")) //Stings on other lings have no effect, but they know you're a ling, too.

	return

//Former /turf procs
/turf/proc/AdjacentTurfsRangedSting()
	//Yes this is snowflakey, but I couldn't get it to work any other way.. -Luke
	var/static/list/allowed = list(
		/obj/structure/table,
		/obj/structure/closet,
		/obj/structure/frame,
		/obj/structure/target_stake,
		/obj/structure/cable,
		/obj/structure/disposalpipe,
		/obj/machinery,
		/mob
	)

	var/L[] = new()
	for(var/turf/simulated/t in oview(src,1))
		var/add = 1
		if(t.density)
			add = 0
		if(add && LinkBlocked(src,t))
			add = 0
		if(add && TurfBlockedNonWindow(t))
			add = 0
		for(var/obj/O in t)
			if(O.density)
				add = 0
				break
			if(istype(O, /obj/machinery/door))
				//not sure why this doesn't fire on LinkBlocked()
				add = 0
				break
			for(var/type in allowed)
				if (istype(O, type))
					add = 1
					break
			if(!add)
				break
		if(add)
			L.Add(t)
	return L

/mob/proc/EvolutionMenu()
	set name = "-Evolution Menu-"
	set category = VERB_CAT_CHANGELING
	set desc = "Adapt yourself carefully."

	var/datum/changeling/comp = is_changeling(src)
	if(!comp)
		to_chat(src, "You are not a changeling!")
		return
	if(!GLOB.powerinstances.len)
		for(var/changeling_power in GLOB.changeling_powers)
			GLOB.powerinstances += new changeling_power()
	if(!comp.power_panel)
		rel_set(comp, nameof(comp.power_panel), new /datum/changeling_panel())
		rel_set(comp.power_panel, nameof(/datum/changeling_panel::comp), comp)

	comp.power_panel.tgui_interact(src)

///Purchasing a power. Called by the Evolution Panel.
/datum/changeling/proc/purchasePower(mob/owner, Pname, remake_verbs = 1)

	var/datum/power/changeling/Thepower = Pname

	for (var/datum/power/changeling/P in GLOB.powerinstances)
		if(P.name == Pname)
			Thepower = P
			break

	if(Thepower == null)
		to_chat(owner, "This is awkward.  Changeling power purchase failed, please report this bug to a coder!")
		return

	if(Thepower in purchased_powers)
		to_chat(owner, "We have already evolved this ability!")
		return

	if(geneticpoints < Thepower.genomecost)
		to_chat(owner, "We cannot evolve this... yet.  We must acquire more DNA.")
		return

	geneticpoints -= Thepower.genomecost

	rel_add(src, nameof(purchased_powers), Thepower)

	if(Thepower.genomecost > 0)
		LAZYADD(purchased_powers_history, "[Pname] ([Thepower.genomecost] points)")

	if(Thepower.make_hud_button && Thepower.isVerb)
		// A fresh master (rel_set deletes the old one); a mob without one gets its first.
		rel_set(owner, nameof(owner.ability_master), new /atom/movable/screen/movable/ability_master(owner))
		owner.ability_master.add_ling_ability(
			object_given = owner,
			verb_given = Thepower.verbpath,
			name_given = Thepower.name,
			ability_icon_given = Thepower.ability_icon_state,
			arguments = list()
			)

	if(!Thepower.isVerb && Thepower.verbpath)
		call(owner, Thepower.verbpath)()
	else if(remake_verbs)
		owner.make_changeling()

//Debug item. Here because during debugging I DO NOT want to have to open the player panel 5000 times.
/obj/item/changeling_debug
	name = "Katana of the Changeling"
	desc = "A katana imbued with special powers. It is said that those who wield it will become a changeling."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "katana"
	item_state = "katana"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_material.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_material.dmi',
		)
	slot_flags = SLOT_BELT | SLOT_BACK
	force = 5
	throwforce = 5
	w_class = ITEMSIZE_NORMAL
	attack_verb = list("attacked", "slashed", "stabbed", "sliced")

CAPABILITIES(/obj/item/changeling_debug)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/changeling_debug/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	user.make_changeling()
	return TRUE

///Changeling Panel
/datum/changeling_panel
	var/datum/changeling/comp

/datum/changeling_panel/tgui_status(mob/user)
	if(!isliving(user)) //We ghosted or something.
		return STATUS_CLOSE
	return ..()

CAPABILITIES(/datum/changeling_panel)
	interface("ChangelingPanel", title = "Changeling Evolution Panel", state = nameof(GLOB.tgui_always_state))
	op("evolve_power", ui_act("evolve_power", arg("val", schema_text(4096))), then(PROC_REF(ui_act_evolve_power)))

/// /datum/changeling_panel's window data.
/datum/changeling_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/list/power_list = list()

	for(var/datum/power/changeling/P in GLOB.powerinstances)
		var/list/all_powers = list(
			"power_name" = P.name,
			"power_cost" = P.genomecost,
			"power_purchased" = (P in comp().purchased_powers),
			"power_desc" = P.desc,
		)
		UNTYPED_LIST_ADD(power_list, all_powers)

	data["available_points"] = comp().geneticpoints
	data["power_list"] = power_list

	return data

/datum/changeling_panel/proc/ui_act_evolve_power(datum/act/op/A, val)
	comp().purchasePower(comp().owner, val) //The power must be the power's NAME.
	return TRUE

/// The changeling this panel shows (a relation view).
/datum/changeling_panel/proc/comp() as /datum/changeling
	return comp

/// The mob's changeling state, if any (only living mobs can hold it).
/mob/proc/get_changeling_state() as /datum/changeling
	return null

/mob/living/get_changeling_state()
	return changeling_state

/mob/living/var/datum/changeling/changeling_state




/datum/prompt/choice/changeling_sting_target
	question = "Who will we sting?"
	title = "Sting!"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/changeling_sting_target/recheck_extra()
	if(QDELETED(owner) || QDELETED(answerer))
		return "gone"
	var/mob/living/carbon/selected = value
	if(!isnull(selected) && QDELETED(selected))
		return "gone"
	return null

/datum/prompt/choice/changeling_sting_dna
	question = "Select the target DNA:"
	title = "Target DNA"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/changeling_sting_dna/recheck_extra()
	return QDELETED(owner) || QDELETED(answerer) ? "gone" : null
