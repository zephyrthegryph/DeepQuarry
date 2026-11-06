GLOBAL_LIST_EMPTY(hud_icon_reference)

///The one click catcher screen every client shows under the map.
GLOBAL_DATUM(click_catcher, /atom/movable/screen/click_catcher)

//Icons for in-game HUD glasses. Why don't we just share these a little bit?
GLOBAL_DATUM_INIT(ingame_hud, /icon, icon('icons/mob/hud.dmi'))
GLOBAL_DATUM_INIT(ingame_hud_med, /icon, icon('icons/mob/hud_med.dmi'))
GLOBAL_DATUM_INIT(buildmode_hud, /icon, icon('icons/misc/buildmode.dmi'))
