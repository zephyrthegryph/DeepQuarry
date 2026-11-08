// Client lighting, piece 5: planet sunlight. The advanced sunlight system (a /datum/sunlight_handler per turf on a level with a
// planetary or advanced fake sun) lights through the DM corners and lighting objects: a turf lit only by the sun shows the
// level's shared sun tile (its planet handler's vis_overhead, or vis_shade near the outdoors) in vis_contents, recoloured by
// one write when the sun changes. Client lighting has no corners or lighting objects, so there each handler shows its turf the
// same shared tile itself, from its own sunlight state: outdoors the overhead tile, within reach of the outdoors the shade
// tile, nothing otherwise. The tiles lie under the glows, so lamps add on top. (The simple sun, /datum/sun_holder and the
// plain fake sun, draws on the object-lighting mask and needs nothing here.)
//
// Events only: the handler's own sunlight_check() (init, a turf change that may let the sun in or cut it off), the mode switch
// and the sun's colour (one appearance write on the shared tile, as before).

/datum/sunlight_handler
	/// Client lighting: the sun tile this handler shows its turf (CLIENT_SUN_*).
	var/client_sun = 0

#define CLIENT_SUN_NONE 0
#define CLIENT_SUN_OVERHEAD 1
#define CLIENT_SUN_SHADE 2

/// The tile this handler's turf shows under client lighting.
/datum/sunlight_handler/proc/client_sun_wanted()
	if(!GLOB.client_lighting || QDELETED(holder) || !try_get_sun())
		return CLIENT_SUN_NONE
	switch(sunlight)
		if(SUNLIGHT_OVERHEAD)
			return CLIENT_SUN_OVERHEAD
		if(TRUE)
			return CLIENT_SUN_SHADE
	return CLIENT_SUN_NONE

/// Puts this handler's turf on the sun tile it should show now (client lighting), or takes it off.
/datum/sunlight_handler/proc/client_sun_apply()
	var/want = client_sun_wanted()
	if(want == client_sun)
		return
	var/datum/planet_sunlight_handler/P = pshandler
	if(client_sun && P && holder)
		vis_remove(holder, client_sun == CLIENT_SUN_OVERHEAD ? P.vis_overhead : P.vis_shade)
	client_sun = want
	if(want)
		vis_add(holder, want == CLIENT_SUN_OVERHEAD ? P.vis_overhead : P.vis_shade)

/// The gameplay light the sun gives this handler's turf under client lighting (the corner engine's sun term).
/datum/sunlight_handler/proc/client_sun_level()
	var/datum/planet_sunlight_handler/P = pshandler
	if(!P)
		return 0
	switch(client_sun)
		if(CLIENT_SUN_OVERHEAD)
			return P.maxlum
		if(CLIENT_SUN_SHADE)
			return P.maxlumshade
	return 0

/// Client lighting switched: every sunlight handler shows (or drops) its sun tile.
/proc/client_sun_switched()
	var/n = 0
	for(var/datum/sunlight_handler/S)
		if(QDELETED(S))
			continue
		S.client_sun_apply()
		if(S.client_sun)
			n++
	log_world("client lighting: [n] sunlit turf(s) show a sun tile")
	return n
