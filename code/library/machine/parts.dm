// Part replacement (doc/rewrite/final_api.html, section 11: the machine library's `components(slots)` is the full design; this is the one op of it that
// a converted machine needs while machine parts are still the machine core's: RefreshParts(), component_parts and the circuit board).
//
// part_replacement(): a rapid part exchange device used on the machine swaps its installed parts for better ones (the panel must be open when the
// device asks for it) and the machine's RefreshParts() re-derives what depends on them. Op part_replacement.replace, tier PART (an item in hand).
// Phase 4 (the machine track) replaces this with components(slots).

CAPABILITY_TYPE(part_replacement, CAP_PART_REPLACEMENT, /datum/capability/lib/part_replacement, key = NONE)

/datum/capability/lib/part_replacement

/datum/capability/lib/part_replacement/entries()
	return list(op("replace", item(/obj/item/storage/part_replacer), label("Replace parts"), then(CAP_PROC(replace))))

/// The machine's own part replacement (it lists the parts, swaps better ones in and calls RefreshParts()).
/datum/capability/lib/part_replacement/proc/replace(datum/act/op/A)
	var/obj/machinery/M = A.holder
	if(!istype(M) || !M.default_part_replacement(A.actor, A.held))
		return OP_REFUSED
	return OP_OK

// default_parts(): the machine refreshes its default parts as it initializes (the board's req_components, resolved lazily, and
// RefreshParts() over them). It replaces the Initialize() override that only called default_apply_parts() after ..(): the capability
// runs it in on_holder_init(), after the machine's capabilities and before any type's code after its ..(). Phase 4 (the machine track)
// replaces it with components(slots).
CAPABILITY_TYPE(default_parts, CAP_DEFAULT_PARTS, /datum/capability/lib/default_parts, key = NONE)

/datum/capability/lib/default_parts
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/default_parts/on_holder_init(datum/act/eval/A)
	var/obj/machinery/M = A.holder
	if(istype(M))
		M.default_apply_parts()
