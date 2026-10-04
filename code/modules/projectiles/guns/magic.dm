/*
 * "Magic" "Guns"
 */

/obj/item/gun/magic
	name = "staff of nothing"
	desc = "This staff is boring to watch because even though it came first you've seen everything it can do in other staves for years."
	icon = 'icons/obj/wizard.dmi'
	icon_state = "staffofnothing"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_magic.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_magic.dmi',
		)
	fire_sound = SFX_WEAPONS_EMITTER
	w_class = ITEMSIZE_HUGE
	projectile_type = null
	var/checks_antimagic = TRUE
	var/max_charges = 6
	var/charges = 0
	var/recharge_rate = 4
	var/charge_tick = 0

/obj/item/gun/magic/var/can_charge = TRUE
TRACKED(/obj/item/gun/magic, can_charge)
CAPABILITIES(/obj/item/gun/magic)
	/// Regains charges while it can charge.
	every(2 SECONDS, then(PROC_REF(magic_step)), when = nameof(can_charge))

/obj/item/gun/magic/consume_next_projectile(mob/user)
	if(checks_antimagic && locate_within(user, /obj/item/nullrod)) return null
	if(!ispath(projectile_type)) return null
	if(charges <= 0) return null

	charges -= 1

	return new projectile_type(src)

/obj/item/gun/magic/Initialize(mapload)
	. = ..()
	charges = max_charges

/obj/item/gun/magic/proc/magic_step(datum/act/timer/A)
	if (charges >= max_charges)
		charge_tick = 0
		return
	charge_tick++
	if(charge_tick < recharge_rate)
		return 0
	charge_tick = 0
	charges++
	return 1

/obj/item/gun/magic/handle_click_empty(mob/user)
	if (user)
		act_message(user, null, MSG_SELF(span_danger("The [name] whizzles quietly.")), MSG_OTHERS("*wzhzhzh*"))
	else
		src.visible_message("*wzhzh*")
	play_sfx(src, SFX_WEAPONS_EMPTY, 2)
