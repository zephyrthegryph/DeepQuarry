/*
 * Action figures
 */
/obj/item/toy/figure
	name = "Non-Specific Action Figure action figure"
	desc = "A \"Space Life\" brand... wait, what the hell is this thing?"
	icon = 'icons/obj/toy.dmi'
	icon_state = "nuketoy"
	w_class = ITEMSIZE_TINY
	var/cooldown = 0
	var/toysay = "What the fuck did you do?"

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/toy/figure/proc/variant_table()
	return GLOB.dq_variants_toy_figures

/// Every figure is described by its name (derives(), at init).
/obj/item/toy/figure/proc/space_life_desc()
	return "A \"Space Life\" brand [name]"

CAPABILITIES(/obj/item/toy/figure)
	variants(nameof(variant), PROC_REF(variant_table))
	configure(item_sounds(drop = SFX_ITEMS_DROP_ACCESSORY))
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	derives(nameof(desc), PROC_REF(space_life_desc))

/// Old attack_self.
/obj/item/toy/figure/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 3 SECONDS)
		user.visible_message(span_notice("The [src] says \"[toysay]\"."))
		play_sfx(src, SFX_MACHINES_CLICK, 0.4)
	return TRUE

/*
 * Action figures
 */
