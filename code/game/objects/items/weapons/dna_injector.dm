/obj/item/dnainjector
	name = "\improper DNA injector"
	desc = "This injects the person with DNA."
	icon = 'icons/obj/items.dmi'
	icon_state = "dnainjector"
	var/block=0
	var/datum/dna2/record/buf=null
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	var/uses = 1
	var/nofail

	// USE ONLY IN PREMADE SYRINGES.  WILL NOT WORK OTHERWISE.
	var/datatype=0
	var/value=0

	// Removed subtype, replaced with flag. Allows for safe injectors. Mostly for admin usage.
	var/has_radiation = TRUE

CAPABILITIES(/obj/item/dnainjector)
	owns_one(nameof(buf), /datum/dna2/record)

TYPE_TABLE_DECLARE(/obj/item/dnainjector, injector_random_selector, null)

// ALLOW(init/INSTANCE_STATE): allocates this injector's owned gene record and DNA buffer, then writes its selected gene value before parent initialization
/obj/item/dnainjector/Initialize(mapload)
	var/selector = TYPE_TABLE_GET(src, injector_random_selector)
	switch(selector)
		if(/obj/item/dnainjector/random)
			pick_block( pick(GLOB.dna_genes_good + GLOB.dna_genes_neutral + GLOB.dna_genes_bad), FALSE, TRUE)
		if(/obj/item/dnainjector/random_labeled)
			pick_block( pick(GLOB.dna_genes_good + GLOB.dna_genes_neutral + GLOB.dna_genes_bad), TRUE, TRUE)
		if(/obj/item/dnainjector/random_good)
			pick_block( pick(GLOB.dna_genes_good + GLOB.dna_genes_neutral ), FALSE, TRUE)
		if(/obj/item/dnainjector/random_good_labeled)
			pick_block( pick(GLOB.dna_genes_good + GLOB.dna_genes_neutral ), TRUE, TRUE)
		if(/obj/item/dnainjector/random_bad)
			pick_block( pick(GLOB.dna_genes_bad + GLOB.dna_genes_neutral ), FALSE, TRUE)
		if(/obj/item/dnainjector/random_bad_labeled)
			pick_block( pick(GLOB.dna_genes_bad + GLOB.dna_genes_neutral ), TRUE, TRUE)
		if(/obj/item/dnainjector/random_verygood)
			pick_block( pick(GLOB.dna_genes_good), FALSE, FALSE)
		if(/obj/item/dnainjector/random_verygood_labeled)
			pick_block( pick(GLOB.dna_genes_good), TRUE, FALSE)
		if(/obj/item/dnainjector/random_verybad)
			pick_block( pick(GLOB.dna_genes_bad), FALSE, FALSE)
		if(/obj/item/dnainjector/random_verybad_labeled)
			pick_block( pick(GLOB.dna_genes_bad), TRUE, FALSE)
		if(/obj/item/dnainjector/random_neutral)
			pick_block( pick(GLOB.dna_genes_neutral ), FALSE, TRUE)
		if(/obj/item/dnainjector/random_neutral_labeled)
			pick_block( pick(GLOB.dna_genes_neutral ), TRUE, TRUE)
	if(datatype && block)
		rel_set(src, nameof(buf), new /datum/dna2/record) // ALLOW(decl): only when datatype and block are set, then configured
		rel_set(buf, nameof(buf.dna), new /datum/dna)
		buf.types = datatype
		buf.dna.ResetSE()
		SetValue(src.value)
	. = ..()

/obj/item/dnainjector/proc/GetRealBlock(selblock)
	if(selblock==0)
		return block
	else
		return selblock

/obj/item/dnainjector/proc/GetState(selblock=0)
	var/real_block=GetRealBlock(selblock)
	if(buf.types&DNA2_BUF_SE)
		return buf.dna.GetSEState(real_block)
	else
		return buf.dna.GetUIState(real_block)

/obj/item/dnainjector/proc/SetState(on, selblock=0)
	var/real_block=GetRealBlock(selblock)
	if(buf.types&DNA2_BUF_SE)
		return buf.dna.SetSEState(real_block,on)
	else
		return buf.dna.SetUIState(real_block,on)

/obj/item/dnainjector/proc/GetValue(selblock=0)
	var/real_block=GetRealBlock(selblock)
	if(buf.types&DNA2_BUF_SE)
		return buf.dna.GetSEValue(real_block)
	else
		return buf.dna.GetUIValue(real_block)

/obj/item/dnainjector/proc/SetValue(val,selblock=0)
	var/real_block=GetRealBlock(selblock)
	if(buf.types&DNA2_BUF_SE)
		return buf.dna.SetSEValue(real_block,val)
	else
		return buf.dna.SetUIValue(real_block,val)

/obj/item/dnainjector/proc/inject(mob/M as mob, mob/user as mob)
	if(isliving(M) && has_radiation)
		var/mob/living/L = M
		L.apply_effect(rand(5,20), IRRADIATE, check_protection = 0)
		L.injure(INJURY_CELLULAR, max(2, L.injury_load(INJURY_CATEGORY_GENETIC)), source = src)

	// NO_DNA and Synthetics cannot be mutated
	var/allow = TRUE
	if(HAS_SYNTHETIC_BIOLOGY(M))
		allow = FALSE
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!H.species || H.species.flags & NO_DNA)
			allow = FALSE
	if (!(M.has_mutation(NOCLONE)) && allow) // prevents drained people from having their DNA changed; NO_DNA and synthetics cannot be mutated
		if(buf)
			if (buf.types & DNA2_BUF_UI)
				if (!block) //isolated block?
					M.UpdateAppearance(buf.dna.UI.Copy())
					if (buf.types & DNA2_BUF_UE) //unique enzymes? yes
						M.real_name = buf.dna.real_name
						M.name = buf.dna.real_name
					uses--
				else
					M.dna.SetUIValue(block,src.GetValue())
					M.UpdateAppearance()
					uses--
			if (buf.types & DNA2_BUF_SE)
				if (!block) //isolated block?
					M.dna.SE = buf.dna.SE.Copy()
					M.dna.UpdateSE()
				else
					M.dna.SetSEValue(block,src.GetValue())
				uses--
				// Moved gene checks to after side effects
				if(prob(5))
					trigger_side_effect(M)
			// Do gene updates here, and more comprehensively
			if(ishuman(M))
				var/mob/living/carbon/human/H = M
				H.sync_dna_traits(FALSE,FALSE)
				H.sync_organ_dna()
			M.regenerate_icons()

	if (user)
		user.drop_from_inventory(src)
	spent(src, M)
	return uses

/obj/item/dnainjector/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if (!user.IsAdvancedToolUser())
		return ITEM_INTERACT_FAILURE
	if (task_busy(src))
		return ITEM_INTERACT_FAILURE

	act_message(user, src, others = span_danger("%U% is trying to inject \the [M] with %T%!"))


	task_timed(user, 5 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_timed_done), done_args = list(M, user), claims = TRUE)
	return TRUE

/obj/item/dnainjector/proc/attack_timed_done(mob/living/M, mob/living/user)


	user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)
	user.do_attack_animation(M)

	act_message(user, M, others = span_danger("%T% has been injected with \the [src] by %U%."))

	var/mob/living/carbon/human/H = M
	if(!istype(H))
		to_chat(user, span_warning("Apparently it didn't work..."))
		return ITEM_INTERACT_FAILURE

	inject(M, user)
	return ITEM_INTERACT_SUCCESS

// Traitgenes Injectors are randomized now due to no hardcoded genes. Split into good or bad, and then versions that specify what they do on the label.
// Otherwise scroll down further for how to make unique injectors
/obj/item/dnainjector/proc/pick_block(datum/gene/trait/G, labeled, allow_disable, force_disable = FALSE)
	if(G)
		block = G.block
		datatype = DNA2_BUF_SE
		if(!force_disable)
			value = 0xFFF
		else
			value = 0x000
		if(allow_disable)
			value = pick(0x000,0xFFF)
		if(labeled)
			name = initial(name) + " - [value == 0x000 ? "Removes" : ""] [G.get_name()]"

/obj/item/dnainjector/random
	name = "\improper DNA injector"
	desc = "This injects the person with DNA."

// Purely rando
TYPE_TABLE(/obj/item/dnainjector/random, injector_random_selector, /obj/item/dnainjector/random)

TYPE_TABLE(/obj/item/dnainjector/random_labeled, injector_random_selector, /obj/item/dnainjector/random_labeled)

// Good/bad but also neutral genes mixed in, less OP selection of genes
TYPE_TABLE(/obj/item/dnainjector/random_good, injector_random_selector, /obj/item/dnainjector/random_good)

TYPE_TABLE(/obj/item/dnainjector/random_good_labeled, injector_random_selector, /obj/item/dnainjector/random_good_labeled)

TYPE_TABLE(/obj/item/dnainjector/random_bad, injector_random_selector, /obj/item/dnainjector/random_bad)

TYPE_TABLE(/obj/item/dnainjector/random_bad_labeled, injector_random_selector, /obj/item/dnainjector/random_bad_labeled)

// Purely good/bad genes, intended to be usually good rewards or punishments
TYPE_TABLE(/obj/item/dnainjector/random_verygood, injector_random_selector, /obj/item/dnainjector/random_verygood)

TYPE_TABLE(/obj/item/dnainjector/random_verygood_labeled, injector_random_selector, /obj/item/dnainjector/random_verygood_labeled)

TYPE_TABLE(/obj/item/dnainjector/random_verybad, injector_random_selector, /obj/item/dnainjector/random_verybad)

TYPE_TABLE(/obj/item/dnainjector/random_verybad_labeled, injector_random_selector, /obj/item/dnainjector/random_verybad_labeled)

// Random neutral traits
TYPE_TABLE(/obj/item/dnainjector/random_neutral, injector_random_selector, /obj/item/dnainjector/random_neutral)

TYPE_TABLE(/obj/item/dnainjector/random_neutral_labeled, injector_random_selector, /obj/item/dnainjector/random_neutral_labeled)

// If you want a unique injector, use a subtype of these
/obj/item/dnainjector/set_trait
	var/trait_path
	var/disabling = FALSE

/obj/item/dnainjector/set_trait/Initialize(mapload)
	var/G = get_gene_from_trait(trait_path)
	if(trait_path && G)
		pick_block( G, TRUE, FALSE, disabling)
	else
		. = ..()
		return INITIALIZE_HINT_QDEL
	. = ..()

	disabling = TRUE

// Injectors for all original genes and some new ones
/obj/item/dnainjector/set_trait/anxiety	// stutter
	trait_path = /datum/trait/negative/disability_nervousness // neutral -> negative
/obj/item/dnainjector/set_trait/anxiety/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/noprints // noprints
	trait_path = /datum/trait/positive/superpower_noprints
/obj/item/dnainjector/set_trait/noprints/disable
	disabling = TRUE
// Note: TRAITGENETICS - tourettes Disabled on VS // Enable
/obj/item/dnainjector/set_trait/tourettes // tour
	trait_path = /datum/trait/neutral/disability_tourettes
/obj/item/dnainjector/set_trait/tourettes/disable
	disabling = TRUE
// Note: TRAITGENETICS - tourettes Disabled on VS // Enable
/obj/item/dnainjector/set_trait/cough // cough
	trait_path = /datum/trait/negative/disability_cough
/obj/item/dnainjector/set_trait/cough/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/nearsighted // glasses
	trait_path = /datum/trait/negative/disability_nearsighted
/obj/item/dnainjector/set_trait/nearsighted/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/heatadapt // fire
	trait_path = /datum/trait/neutral/hotadapt
/obj/item/dnainjector/set_trait/heatadapt/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/epilepsy // epi
	trait_path = /datum/trait/negative/disability_epilepsy
/obj/item/dnainjector/set_trait/epilepsy/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/morph // morph
	trait_path = /datum/trait/positive/superpower_morph
/obj/item/dnainjector/set_trait/morph/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/regenerate // regenerate
	trait_path = /datum/trait/positive/superpower_regenerate
/obj/item/dnainjector/set_trait/regenerate/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/clumsy // clumsy
	trait_path = /datum/trait/negative/disability_clumsy
/obj/item/dnainjector/set_trait/clumsy/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/coldadapt // insulated
	trait_path = /datum/trait/neutral/coldadapt
/obj/item/dnainjector/set_trait/coldadapt/disable
	disabling = TRUE
// Note: TRAITGENETICS - Disabled on VS // Enable
/obj/item/dnainjector/set_trait/xray // xraymut
	trait_path = /datum/trait/positive/superpower_xray
/obj/item/dnainjector/set_trait/xray/disable
	disabling = TRUE
// Note: TRAITGENETICS - Disabled on VS // Enable
/obj/item/dnainjector/set_trait/deaf // deafmut
	trait_path = /datum/trait/negative/disability_deaf
/obj/item/dnainjector/set_trait/deaf/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/tk // telemut
	trait_path = /datum/trait/positive/superpower_tk
/obj/item/dnainjector/set_trait/tk/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/haste // runfast
	trait_path = /datum/trait/positive/speed_fast
/obj/item/dnainjector/set_trait/haste/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/blind // blindmut
	trait_path = /datum/trait/negative/blindness
/obj/item/dnainjector/set_trait/blind/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/nobreathe // nobreath
	trait_path = /datum/trait/positive/superpower_nobreathe
/obj/item/dnainjector/set_trait/nobreathe/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/remoteview // remoteview
	trait_path = /datum/trait/positive/superpower_remoteview
/obj/item/dnainjector/set_trait/remoteview/disable
	disabling = TRUE
/obj/item/dnainjector/set_trait/flashproof // flashproof
	trait_path = /datum/trait/positive/superpower_flashproof
/obj/item/dnainjector/set_trait/flashproof/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/hulk // hulk
	trait_path = /datum/trait/positive/superpower_hulk
/obj/item/dnainjector/set_trait/hulk/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/table_passer // midgit
	trait_path = /datum/trait/positive/table_passer
/obj/item/dnainjector/set_trait/table_passer/disable
	disabling = TRUE

/obj/item/dnainjector/set_trait/remotetalk // remotetalk
	trait_path = /datum/trait/positive/superpower_remotetalk
/obj/item/dnainjector/set_trait/remotetalk/disable
	disabling = TRUE
/obj/item/dnainjector/set_trait/damagedspine // brokenspine
	trait_path = /datum/trait/negative/disability_damagedspine
/obj/item/dnainjector/set_trait/damagedspine/disable
	disabling = TRUE
/obj/item/dnainjector/set_trait/nonconduct // shock
	trait_path = /datum/trait/positive/nonconductive_plus
/obj/item/dnainjector/set_trait/nonconduct/disable
	disabling = TRUE
