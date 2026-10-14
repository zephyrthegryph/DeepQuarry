/mob/living/silicon/robot/platform/explorer
	req_access = list(ACCESS_EXPLORER)

/mob/living/silicon/robot/platform/cargo
	req_access = list(ACCESS_CARGO_BOT)

/obj/item/card/id/platform/proc/include_platform_access()
	include_access(ACCESS_EXPLORER)
	include_access(ACCESS_PILOT)

CAPABILITIES(/obj/item/card/id/platform)
	setup(PROC_REF(include_platform_access))
