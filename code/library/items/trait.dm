// trait(TRAIT_X, examine =) (doc/rewrite/final_api.html, section 11 "Mobs"; section 5 "Traits"): the holder has the trait for as long as the capability does,
// and its examine text says so when `examine` is given.
//
//   CAPABILITIES(/obj/item/clothing/suit/radiation,
//       trait(TRAIT_RADIATION_PROTECTED_CLOTHING, examine = "A patch with a hazmat sign suggests it would protect you from radiation."))
//
// key = trait: two traits on one type are two capabilities, and grant(M, trait(TRAIT_X)) names which one. A type declares it for its whole life (the trait is
// granted at init, released at destroy); a grant has it while the grant lasts: both go through add_trait()/remove_trait() with the capability as the source,
// so other sources stack on the same trait as with any trait and has_trait() reads it. (The separate "traits set stat" of section 5 is not built:
// has_trait() is still the legacy store's, and granted() reads the capability.)

CAPABILITY_TYPE(trait, CAP_TRAIT, /datum/capability/lib/trait, key = trait, trait = null, examine = null)

/datum/capability/lib/trait
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/trait/entries()
	return list(examine ? examine_line(CAP_PROC(trait_line)) : null)

/datum/capability/lib/trait/proc/trait_line(datum/act/op/A)
	return span_notice(examine)

/// The source text the trait is held under: one per capability (and per grant).
/datum/capability/lib/trait/proc/trait_source_key(datum/activation/A)
	return A ? "capability_trait:[A.serial]" : "capability_trait"

/datum/capability/lib/trait/on_holder_init(datum/act/eval/A)
	if(!isnull(trait))
		add_trait(A.holder, trait, trait_source_key(null))

/datum/capability/lib/trait/on_holder_destroy(datum/act/eval/A)
	if(!isnull(trait))
		remove_trait(A.holder, trait, trait_source_key(null))

/datum/capability/lib/trait/on_activate(datum/activation/A)
	if(A.scope == SCOPE_TYPE || isnull(trait))
		return
	add_trait(A.holder, trait, trait_source_key(A))

/datum/capability/lib/trait/on_deactivate(datum/activation/A)
	if(A.scope == SCOPE_TYPE || isnull(trait))
		return
	remove_trait(A.holder, trait, trait_source_key(A))
