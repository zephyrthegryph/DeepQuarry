// mouse signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

///from base of client/Click(): (atom/target, atom/location, control, params, mob/user)
#define COMSIG_CLIENT_CLICK "atom_client_click"
///from base of atom/Click(): (atom/location, control, params, mob/user)
#define COMSIG_CLICK "atom_click"
//	#define COMSIG_MOB_CANCEL_CLICKON (1<<0) //shared with other forms of click, this is so you're aware it exists here too.
///from base of atom/click_alt(): (/mob)
#define COMSIG_CLICK_ALT "alt_click"
