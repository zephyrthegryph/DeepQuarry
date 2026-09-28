/obj/structure/blob/resource
	name = "resource blob"
	base_name = "resource blob"
	icon = 'icons/mob/blob.dmi'
	icon_state = "blob_resource"
	desc = "A thin spire of slightly swaying tendrils."
	max_integrity = 40
	point_return = 15
	var/resource_delay = 0
	var/resource_cooldown = 4 SECONDS

/obj/structure/blob/resource/Initialize(mapload, new_overmind)
	if(overmind)
		overmind.resource_blobs += src
	return ..()

REF_BACKLIST(/obj/structure/blob/resource, list("overmind" = "resource_blobs"))

/obj/structure/blob/resource/pulsed()
	. = ..()
	if(!COOLDOWN_FINISHED(src, resource_delay))
		return
	flick("blob_resource_glow", src)
	if(overmind)
		overmind.add_points(1)
		COOLDOWN_START(src, resource_delay, resource_cooldown + (overmind.resource_blobs.len * 2.5)) //4 seconds plus a quarter second for each resource blob the overmind has
	else
		COOLDOWN_START(src, resource_delay, resource_cooldown)

/obj/structure/blob/resource/sluggish // Tankier, but really slow.
	name = "sluggish resource blob"
	desc = "A thin spire of occasionally convulsing tendrils."
	max_integrity = 80
	resource_cooldown = 8 SECONDS
