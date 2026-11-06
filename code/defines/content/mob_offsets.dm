/// The pixel_y a mob's shake or float returns to: its default offset plus the raise of the bed or nest it is buckled to (code/content/sparse_vars/mob_state.dm).
#define MOB_REST_PIXEL_Y(M) ((M).default_pixel_y + STATE_GET(M, mob_misc, buckle_pixel_y))
