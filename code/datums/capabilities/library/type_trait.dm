// cap_trait(): a trait the holder has by what it is, for as long as it exists, with an optional examine line
// (doc/rewrite/lifecycle.md "Starting state"). The foundation form of a DECLARE_BEHAVIOUR whose behaviour only
// granted a trait and described it (radiation_protected_clothing was the case).
//
//	/obj/item/clothing/suit/radiation/capabilities()
//		. = ..()
//		. += cap_trait(TRAIT_RADIATION_PROTECTED_CLOTHING, examine = "A patch with a hazmat sign on the side suggests it would <b>protect you from radiation</b>.")
//
// The trait is granted at init under the capability's own source and released when the holder is destroyed; other
// sources (a MOD module's passive protection) stack on it as with any trait.

/datum/capability/type_trait
	/// The TRAIT_* the holder has.
	var/trait
	/// A notice line added to the holder's examine, or null.
	var/examine_line

/// The holder has `trait` while it exists; `examine`: a line its examine shows (span_notice), or null.
/proc/cap_trait(trait, examine = null)
	var/datum/capability/type_trait/C = new
	C.trait = trait
	C.examine_line = examine
	C.key = "trait:[trait]"
	return C

/datum/capability/type_trait/on_holder_init(atom/holder, mapload)
	add_trait(holder, trait, key)

/datum/capability/type_trait/on_holder_destroy(atom/holder)
	remove_trait(holder, trait, key)

/datum/capability/type_trait/examine(atom/holder, mob/user)
	if(examine_line)
		return list(span_notice(examine_line))
	return null
