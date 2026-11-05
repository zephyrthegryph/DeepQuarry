/*
** Holds defines for code\game\atoms_movable.dm to avoid magic numbers and potential unexpected overwrites down the line
*/

#define NON_LISTENING_ATOM		0
#define LISTENING_ATOM			1
#define LISTENING_PLAYER		2

#define DEFAULT_ICON_SCALE_X 1
#define DEFAULT_ICON_SCALE_Y 1
#define DEFAULT_ICON_ROTATION 0

#define MOVE_GLIDE_CALC(glide_size, moving_diagonally) ( (TICKS2DS(WORLD_ICON_SIZE/glide_size)) * (moving_diagonally ? (ONE_OVER_SQRT_2) : 1) ) // - move calc
/// The move_resist of a movable with no override (a field default of the movable_misc lazy state, so a macro file defines it).
#define MOVE_RESIST_DEFAULT 100
