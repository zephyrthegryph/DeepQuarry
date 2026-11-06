/obj/item/spell/projectile
	name = "projectile template"
	icon_state = "generic"
	desc = "This is a generic template that shoots projectiles.  If you can read this, the game broke!"
	cast_methods = CAST_RANGED
	var/spell_projectile = null
	var/energy_cost_per_shot = 0
	var/instability_per_shot = 0
	var/pre_shot_delay = 0
	var/fire_sound = null

/obj/item/spell/projectile/on_ranged_cast(atom/hit_atom, mob/living/user)
	if(set_up(hit_atom, user))
		var/obj/item/projectile/new_projectile = make_projectile(spell_projectile, user)
		new_projectile.old_style_target(hit_atom)
		new_projectile.fire()
		add_attack_logs(user,hit_atom,"Casted [src]")
		if(fire_sound)
			playsound(src, fire_sound, 75, 1)
		adjust_instability(instability_per_shot)
		return 1
	return 0

/obj/item/spell/projectile/proc/make_projectile(obj/item/projectile/projectile_type, mob/living/user)
	var/obj/item/projectile/P = new projectile_type(get_turf(user))
	P.damage = calculate_spell_power(P.damage)
	return P

/// TRUE to fire now. With a pre-shot delay it pays, shows the target and fires later (delayed_shot()).
/obj/item/spell/projectile/proc/set_up(atom/hit_atom, mob/living/user)
	if(shot_ready)
		return TRUE
	if(spell_projectile)
		if(pay_energy(energy_cost_per_shot))
			if(pre_shot_delay)
				var/image/target_image = image(icon = 'icons/obj/spells.dmi', loc = get_turf(hit_atom), icon_state = "target")
				user << target_image
				user.status_at_least(STAT_STUNNED, pre_shot_delay / 10)
				after(src, pre_shot_delay, PROC_REF(delayed_shot), with = list(hit_atom, user, target_image))
				return FALSE
			return TRUE // No delay, no need to check.
	return FALSE

/obj/item/spell/projectile/var/shot_ready = FALSE

/obj/item/spell/projectile/proc/delayed_shot(atom/hit_atom, mob/living/user, image/target_image)
	spent(target_image, user)
	if(QDELETED(user) || QDELETED(core))
		return
	if(!owner_ref())
		return // We got dropped before the firing occured.
	shot_ready = TRUE
	on_ranged_cast(hit_atom, user)
	shot_ready = FALSE
