/proc/output_named_image(var/user, var/art)
    user << image(icon=art, icon_state="target", loc=user)

/proc/output_named_sound(var/user)
    user << sound(null, volume=50)

/proc/output_field_sound(var/mob/owner)
    owner.client << sound(null, volume=50)
