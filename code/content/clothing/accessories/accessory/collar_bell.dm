/obj/item/clothing/accessory/collar/bell
	name = "Bell collar"
	desc = "A collar with a tiny bell hanging from it, purrfect furr kitties."
	icon_state = "collar_bell"
	item_state = "collar_bell"
	overlay_state = "collar_bell"
	var/jingled = 0

CAPABILITIES(/obj/item/clothing/accessory/collar/bell)
	op("bell_jinglebell_verb", menu(), label("Jingle Bell"), needs(carried()), then(PROC_REF(bell_jinglebell_verb)))

/// Old verb "Jingle Bell".
/obj/item/clothing/accessory/collar/bell/proc/bell_jinglebell_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!isliving(user)) return
	if(user.stat) return

	if(!jingled)
		user.audible_message("[user] jingles the [src]'s bell.", runemessage = "jingle")
		play_sfx(src, SFX_ITEMS_PICKUP_RING)
		jingled = 1
		after(src, 5 SECONDS, PROC_REF(jingledreset))
	return

/obj/item/clothing/accessory/collar/bell/proc/jingledreset()
	jingled = 0
