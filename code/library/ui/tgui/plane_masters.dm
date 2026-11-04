// This is a helper for anything that wants to render the map in TGUI
/proc/get_tgui_plane_masters()
	. = list()
	// 'Utility' planes
	. += new /atom/movable/screen/plane_master/fullbright						//Lighting system (lighting_overlay objects)
	. += new /atom/movable/screen/plane_master/lighting							//Lighting system (but different!)
	. += new /atom/movable/screen/plane_master/o_light_visual					//Object lighting (using masks)
	. += new /atom/movable/screen/plane_master/emissive							//Emissive overlays

	. += new /atom/movable/screen/plane_master/ghosts							//Ghosts!
	. += new /atom/movable/screen/plane_master{plane = PLANE_AI_EYE}			//AI Eye!

	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_STATUS}			//Status is the synth/human icon left side of medhuds
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_HEALTH}			//Health bar
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_LIFE}			//Alive-or-not icon
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_ID}				//Job ID icon
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_WANTED}			//Wanted status
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_IMPLOYAL}		//Loyalty implants
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_IMPTRACK}		//Tracking implants
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_IMPCHEM}		//Chemical implants
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_SPECIAL}		//"Special" role stuff
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_STATUS_OOC}		//OOC status HUD

	. += new /atom/movable/screen/plane_master{plane = PLANE_ADMIN1}			//For admin use
	. += new /atom/movable/screen/plane_master{plane = PLANE_ADMIN2}			//For admin use
	. += new /atom/movable/screen/plane_master{plane = PLANE_ADMIN3}			//For admin use

	. += new /atom/movable/screen/plane_master{plane = PLANE_MESONS} 			//Meson-specific things like open ceilings.
	. += new /atom/movable/screen/plane_master{plane = PLANE_BUILDMODE}			//Things that only show up while in build mode
	. += new /atom/movable/screen/plane_master{plane = PLANE_JANHUD}

	// Real tangible stuff planes
	. += new /atom/movable/screen/plane_master/main{plane = TURF_PLANE}
	. += new /atom/movable/screen/plane_master/main{plane = OBJ_PLANE}
	. += new /atom/movable/screen/plane_master/main{plane = MOB_PLANE}
	. += new /atom/movable/screen/plane_master/cloaked								//Cloaked atoms!

	// Random other plane masters
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_STATUS_R}			//Right-side status icon
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_HEALTH_VR}			//Health bar but transparent at 100
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_BACKUP}				//Backup implant status
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_VANTAG}				//Vore Antags
	. += new /atom/movable/screen/plane_master{plane = PLANE_CH_STOMACH}				//Stomachs
	. += new /atom/movable/screen/plane_master{plane = PLANE_AUGMENTED}				//Augmented reality
	. += new /atom/movable/screen/plane_master{plane = PLANE_SOULCATCHER}			//Soulcatcher
