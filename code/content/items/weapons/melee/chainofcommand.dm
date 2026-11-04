/obj/item/melee/chainofcommand
	name = "chain of command"
	desc = "A tool used by great men to placate the frothing masses."
	icon_state = "chain"
	w_class = ITEMSIZE_NORMAL

CAPABILITIES(/obj/item/melee/chainofcommand)
	configure(item_worn(slots = SLOT_BELT))
	configure(item_thrown(force = 7))
	configure(item_combat(force = 10, attack_verbs = list("flogged", "whipped", "lashed", "disciplined"), reach = 2))
	configure(item_sounds(hit = SFX_WEAPONS_WHIP))

/obj/item/melee/chainofcommand/curator_whip
	name = "leather whip"
	desc = "A fine weapon for some treasure hunting."
	icon_state = "curator_whip"

CAPABILITIES(/obj/item/melee/chainofcommand/curator_whip)
	configure(item_thrown(force = 5))
	configure(item_combat(force = 5))

/obj/item/melee/chainofcommand/curator_whip/toy
	name = "toy whip"
	desc = "A fake whip. Perfect for fake treasure hunting"

CAPABILITIES(/obj/item/melee/chainofcommand/curator_whip/toy)
	configure(item_thrown(force = 2))
	configure(item_combat(force = 2))
