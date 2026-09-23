///Called on /basic when updating its speed, from base of /mob/living/basic/update_basic_mob_varspeed(): ()
#define POST_BASIC_MOB_UPDATE_VARSPEED "post_basic_mob_update_varspeed"
///from base of /mob/Login(): ()
#define COMSIG_MOB_LOGIN "mob_login"
///from base of /mob/Logout(): ()
#define COMSIG_MOB_LOGOUT "mob_logout"
///from base of mob/set_stat(): (new_stat, old_stat)
#define COMSIG_MOB_STATCHANGE "mob_statchange"
	#define COMSIG_MOB_CANCEL_CLICKON (1<<0)


/// From base of /mob/proc/reset_perspective() : ()
#define COMSIG_MOB_RESET_PERSPECTIVE "mob_reset_perspective"

/// Sent from /proc/do_after if someone starts a do_after action bar.
#define COMSIG_DO_AFTER_BEGAN "mob_do_after_began"
/// Sent from /proc/do_after once a do_after action completes, whether via the bar filling or via interruption.
#define COMSIG_DO_AFTER_ENDED "mob_do_after_ended"

///from mind/transfer_to. Sent to the receiving mob.
#define COMSIG_MOB_MIND_TRANSFERRED_INTO "mob_mind_transferred_into"
///from mind/transfer_from. Sent to the mob the mind is being transferred out of.
#define COMSIG_MOB_MIND_TRANSFERRED_OUT_OF "mob_mind_transferred_out_of"


/// from base of /mob/living/proc/apply_damage(): (damage, damagetype, def_zone, blocked, wound_bonus, exposed_wound_bonus, sharpness, attack_direction, attacking_item)
#define COMSIG_MOB_APPLY_DAMAGE "mob_apply_damage"


///sent when a mob/login() finishes: (client)
#define COMSIG_MOB_CLIENT_LOGIN "comsig_mob_client_login"
//from base of client/MouseDown(): (/client, object, location, control, params)
//from base of client/MouseUp(): (/client, object, location, control, params)
//from base of client/MouseUp(): (/client, object, location, control, params)


///from /obj/item/crusher_trophy/on_mark_activate(): (trophy, user)


/// from base of mob/death(): (gibbed)
#define COMSIG_MOB_DEATH "mob_death"


// NON TG SIGNALS

///from base of /client/Move(n, direct) : (direction) returns bool, if component handled movement
#define COMSIG_MOB_RELAY_MOVEMENT "mob_relay_movement"
///From the vision life system (/mob/proc/refresh_vision() for mobs without one).
#define COMSIG_MOB_HANDLE_VISION "mob_handle_vision"
///From the HUD life system (/mob/proc/hud_available()).
#define COMSIG_MOB_HANDLE_HUD "mob_handle_hud"
	#define COMSIG_COMPONENT_HANDLED_HUD (1<<0)
///From the HUD life system (health_icons()).
#define COMSIG_MOB_HANDLE_HUD_HEALTH_ICON "living_handle_hud_health_icon"
	#define COMSIG_COMPONENT_HANDLED_HEALTH_ICON (1<<0)
///From the HUD life system (darksight()).
#define COMSIG_MOB_HANDLE_HUD_DARKSIGHT "living_handle_hud_darksight"
///from /proc/domutcheck(): ()
#define COMSIG_MOB_DNA_MUTATION "mob_dna_mutation"
/// Signal that gets sent when a ghost query is completed
#define COMSIG_GHOST_QUERY_COMPLETE "ghost_query_complete"
///from end of revival_healing_action(): ()
#define COMSIG_LIVING_AHEAL "living_post_aheal"

///from /mob/living/carbon/human/GetVoice(): (list/voice_data) - voice_data[1] contains the voice name
#define COMSIG_HUMAN_GET_VOICE "human_get_voice"
	#define COMPONENT_VOICE_CHANGED (1<<0)
///from /mob/living/carbon/human/GetAltName(): (list/name_data) - name_data[1] contains the alt name
#define COMSIG_HUMAN_GET_ALT_NAME "human_get_alt_name"
	#define COMPONENT_ALT_NAME_CHANGED (1<<0)
