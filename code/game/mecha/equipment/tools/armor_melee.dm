/obj/item/mecha_parts/mecha_equipment/anticcw_armor_booster //what is that noise? A BAWWW from TK mutants.
	name = "\improper CCW armor booster"
	desc = "Close-combat armor booster. Boosts exosuit armor against armed melee attacks. Requires energy to operate."
	icon_state = "mecha_abooster_ccw"
	equip_cooldown = 10
	energy_drain = 50
	range = 0
	var/deflect_coeff = 1.15
	var/damage_coeff = 0.8

	step_delay = 0.5

	equip_type = EQUIP_HULL

/obj/item/mecha_parts/mecha_equipment/anticcw_armor_booster/get_equip_info()
	if(!chassis) return
	return (equip_ready ? span_green("*") : span_red("*")) + "&nbsp;[src.name]"

/obj/item/mecha_parts/mecha_equipment/anticcw_armor_booster/handle_melee_contact(obj/item/W, mob/living/user, inc_damage = null)
	if(!action_checks(user))
		return inc_damage
	chassis.log_message("Attacked by [W]. Attacker - [user]", LOG_GAME)
	if(prob(chassis.deflect_chance*deflect_coeff))
		to_chat(user, span_danger("\The [W] bounces off \the [chassis]'s armor."))
		chassis.log_append_to_last("Armor saved.")
		inc_damage = 0
	else
		chassis.occupant_message(span_danger("\The [user] hits [chassis] with [W]."))
		user.visible_message(span_danger("\The [user] hits [chassis] with [W]."), span_danger("You hit [src] with [W]."))
		inc_damage *= damage_coeff
	set_ready_state(FALSE)
	chassis.use_power(energy_drain)
	spawn()
		do_after_cooldown()
	return max(0, inc_damage)

