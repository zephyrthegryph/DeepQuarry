// wears(item, slot, each =): what a mob starts wearing or holding (doc/rewrite/framework_gaps.md, "Mob init burn-down forms").
//
//	CAPABILITIES(/mob/living/carbon/human/monkey/punpun)
//		wears(/obj/item/clothing/under/punpun, SLOT_ID_UNIFORM)
//	CAPABILITIES(/mob/living/carbon/human/ai_controlled)
//		wears(nameof(to_wear_uniform), SLOT_ID_UNIFORM)            // a var holding the type: a subtype or a map edit changes it, null wears nothing
//		wears(nameof(to_wear_id_type), SLOT_ID_ID, each = PROC_REF(fit_id_card))
//
// `item` is a type, or nameof(var) holding one. The item is made in the mob and equipped with equip_to_slot_or_del() in the capability init
// (phase 2 of the init contract: the body and species exist, the mob's own code after `..()` has not run yet, so its first
// regenerate_icons() draws what it wears). `each` is a holder proc x(item) that fits the item first (an ID card's name and access). The
// key is the slot: one item per slot, and a subtype changes one with configure(wears(slot = SLOT_ID_X, item = ...)). It replaces the
// Initialize() overrides that ran `equip_to_slot_or_del(new /obj/item/x(src), SLOT_ID_X)` after `..()`.

CAPABILITY_TYPE(wears, CAP_WEARS, /datum/capability/lib/wears, key = slot, item = null, slot = null, each = null)

/datum/capability/lib/wears
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/wears/on_holder_init(datum/act/eval/A)
	var/mob/holder = A.holder
	if(!ismob(holder) || isnull(slot))
		return
	var/path = istext(item) ? holder.vars[item] : item
	if(!ispath(path, /obj/item))
		return
	var/obj/item/worn = new path(holder)
	if(each)
		call(holder, each)(worn)
	holder.equip_to_slot_or_del(worn, slot)
