/*

Miscellaneous traitor devices

BATTERER


*/

/*

The Batterer, like a flashbang but 50% chance to knock people over. Can be either very
effective or pretty fucking useless.

*/

/obj/item/batterer
	name = "mind batterer"
	desc = "A strange device with twin antennas."
	icon = 'icons/obj/device.dmi'
	icon_state = "batterer"
	throwforce = 5
	w_class = ITEMSIZE_TINY
	throw_speed = 4
	throw_range = 10
	item_state = "electronic"

	var/times_used = 0 //Number of times it's been used.
	var/max_uses = 2

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

TRACKED(/obj/item/batterer, times_used)
TRACKED(/obj/item/batterer, max_uses)

MSG_DEF_SELF(batterer/burnt, "the mind batterer has been burnt out")

CAPABILITIES(/obj/item/batterer)
	op("batter", in_hand(), label("Trigger mind batterer"), needs(req(PROC_REF(batter_available), because = MSG(batterer/burnt))), then(PROC_REF(batter_triggered)))

/obj/item/batterer/proc/batter_available(datum/act/op/A)
	return times_used < max_uses

/obj/item/batterer/proc/batter_triggered(datum/act/op/A)
	var/mob/user = A.actor
	var/list/affected = list()
	for(var/mob/living/carbon/human/M in orange(10, user))
		affected += M
		after(src, 0, PROC_REF(mind_batter_effect), with = list(M))

	add_attack_logs(user,affected,"Used a [name]")

	play_sfx(src, SFX_MISC_INTERFERENCE)
	to_chat(user, span_notice("You trigger [src]."))
	set_times_used(times_used + 1)
	if(times_used >= max_uses)
		icon_state = "battererburnt"

/obj/item/batterer/proc/mind_batter_effect(mob/living/carbon/human/M)
	if(prob(50))
		M.status_at_least(STAT_WEAKENED, rand(10,20))
		if(prob(25))
			M.status_at_least(STAT_STUNNED, rand(5,10))
		to_chat(M, span_danger("You feel a tremendous, paralyzing wave flood your mind."))
	else
		to_chat(M, span_danger("You feel a sudden, electric jolt travel through your head."))
