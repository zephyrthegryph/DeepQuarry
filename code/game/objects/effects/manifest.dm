/obj/effect/manifest
	name = "manifest"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"

	invisibility = INVISIBILITY_ABSTRACT

CAPABILITIES(/obj/effect/manifest)
	configure(movable_motion(unacidable = TRUE))

/obj/effect/manifest/proc/manifest()
	var/dat = span_bold("Crew Manifest") + ":<BR>"
	for(var/mob/living/carbon/human/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		dat += text("    <B>[]</B> -  []<BR>", M.name, M.get_assignment())
	var/obj/item/paper/P = new /obj/item/paper( src.loc )
	P.set_info(dat)
	P.name = "paper- 'Crew Manifest'"
	replace_with(src, P)
	return
