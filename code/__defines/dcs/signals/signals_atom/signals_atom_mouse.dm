// mouse signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

///from base of client/Click(): (atom/target, atom/location, control, params, mob/user)
#define COMSIG_CLIENT_CLICK "atom_client_click"
///from base of atom/Click(): (atom/location, control, params, mob/user)
#define COMSIG_CLICK "atom_click"
///from base of atom/ShiftClick(): (/mob)
#define COMSIG_CLICK_SHIFT "shift_click"
//	#define COMSIG_MOB_CANCEL_CLICKON (1<<0) //shared with other forms of click, this is so you're aware it exists here too.
///from base of atom/ShiftClick()
#define COMSIG_SHIFT_CLICKED_ON "shift_clicked_on"
///from base of atom/click_ctrlOn(): (/mob)
#define COMSIG_CLICK_CTRL "ctrl_click"
///from base of atom/click_alt(): (/mob)
#define COMSIG_CLICK_ALT "alt_click"
///from base of atom/base_click_alt_secondary(): (/mob)
#define COMSIG_CLICK_ALT_SECONDARY "click_alt_secondary"
	#define COMPONENT_CANCEL_CLICK_ALT_SECONDARY (1<<0)
///from base of atom/click_ctrl_shift(/mob)
#define COMSIG_CLICK_CTRL_SHIFT "ctrl_shift_click"
///from base of mob/MouseWheelOn(): (/atom, delta_x, delta_y, params)
#define COMSIG_MOUSE_SCROLL_ON "mousescroll_on"
