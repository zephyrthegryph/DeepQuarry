///Object doesn't use any of the light systems. Should be changed to add a light source to the object.
#define NO_LIGHT_SUPPORT 0
///Light made with the lighting datums, applying a matrix.
#define STATIC_LIGHT 1
///Light made by masking the lighting darkness plane.
#define MOVABLE_LIGHT 2
///Light made by masking the lighting darkness plane, and is directional.
#define MOVABLE_LIGHT_DIRECTIONAL 3

///Is a movable light source attached to another movable (its loc), meaning that the lighting component should go one level deeper.
#define LIGHT_ATTACHED (1<<0)

//Bay lighting engine shit, not in /code/modules/lighting because BYOND is being shit about it
/// frequency, in 1/10ths of a second, of the lighting process
#define LIGHTING_INTERVAL       5

#define MINIMUM_USEFUL_LIGHT_RANGE 1.4

/// type of falloff to use for lighting; 1 for circular, 2 for square
#define LIGHTING_FALLOFF        1
/// use lambertian shading for light sources
#define LIGHTING_LAMBERTIAN     0
/// height off the ground of light sources on the pseudo-z-axis, you should probably leave this alone
#define LIGHTING_HEIGHT         1
/// Value used to round lumcounts, values smaller than 1/129 don't matter (if they do, thanks sinking points), greater values will make lighting less precise, but in turn increase performance, VERY SLIGHTLY.
#define LIGHTING_ROUND_VALUE    (1 / 64)

/// icon used for lighting shading effects
#define LIGHTING_ICON 'icons/effects/lighting_object.dmi'

/// If the max of the lighting lumcounts of each spectrum drops below this, disable luminosity on the lighting objects.
/// Set to zero to disable soft lighting. Luminosity changes then work if it's lit at all.
#define LIGHTING_SOFT_THRESHOLD 0

/// If I were you I'd leave this alone.
#define LIGHTING_BASE_MATRIX \
	list                     \
	(                        \
		1, 1, 1, 0, \
		1, 1, 1, 0, \
		1, 1, 1, 0, \
		1, 1, 1, 0, \
		0, 0, 0, 1           \
	)                        \

///How many tiles standard fires glow.
#define LIGHT_RANGE_FIRE 3

#define LIGHTING_PLANE_ALPHA_VISIBLE 255
#define LIGHTING_PLANE_ALPHA_NV_TRAIT 245
#define LIGHTING_PLANE_ALPHA_MOSTLY_VISIBLE 192
/// For lighting alpha, small amounts lead to big changes. even at 128 its hard to figure out what is dark and what is light, at 64 you almost can't even tell.
#define LIGHTING_PLANE_ALPHA_MOSTLY_INVISIBLE 128
#define LIGHTING_PLANE_ALPHA_INVISIBLE 0

//lighting area defines
/// dynamic lighting disabled (area stays at full brightness)
#define DYNAMIC_LIGHTING_DISABLED 0
/// dynamic lighting enabled
#define DYNAMIC_LIGHTING_ENABLED 1
/// dynamic lighting enabled even if the area doesn't require power
#define DYNAMIC_LIGHTING_FORCED 2
#define IS_DYNAMIC_LIGHTING(A) A.dynamic_lighting


//code assumes higher numbers override lower numbers.
#define LIGHTING_NO_UPDATE 0
#define LIGHTING_VIS_UPDATE 1
#define LIGHTING_CHECK_UPDATE 2
#define LIGHTING_FORCE_UPDATE 3

#define FLASH_LIGHT_DURATION 2
#define FLASH_LIGHT_POWER 3
#define FLASH_LIGHT_RANGE 3.8

// Emissive blocking.
/// Uses vis_overlays to leverage caching so that very few new items need to be made for the overlay. For anything that doesn't change outline or opaque area much or at all.
#define EMISSIVE_BLOCK_GENERIC 0
/// Uses a dedicated render_target object to copy the entire appearance in real time to the blocking layer. For things that can change in appearance a lot from the base state, like humans.
#define EMISSIVE_BLOCK_UNIQUE 1
/// Don't block any emissives. Useful for things like, pieces of paper?
#define EMISSIVE_BLOCK_NONE 2

/// The color matrix applied to all emissive overlays. Should be solely dependent on alpha and not have RGB overlap with [EM_BLOCK_COLOR].
#define EMISSIVE_COLOR list(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1, 1,1,1,0)
/// A globaly cached version of [EMISSIVE_COLOR] for quick access.
GLOBAL_LIST_INIT(emissive_color, EMISSIVE_COLOR)
/// The color matrix applied to all emissive blockers. Should be solely dependent on alpha and not have RGB overlap with [EMISSIVE_COLOR].
#define EM_BLOCK_COLOR list(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1, 0,0,0,0)
/// A globaly cached version of [EM_BLOCK_COLOR] for quick access.
GLOBAL_LIST_INIT(em_block_color, EM_BLOCK_COLOR)
/// The color matrix used to mask out emissive blockers on the emissive plane. Alpha should default to zero, be solely dependent on the RGB value of [EMISSIVE_COLOR], and be independant of the RGB value of [EM_BLOCK_COLOR].
#define EM_MASK_MATRIX list(0,0,0,1/3, 0,0,0,1/3, 0,0,0,1/3, 0,0,0,0, 1,1,1,0)
/// A globaly cached version of [EM_MASK_MATRIX] for quick access.
GLOBAL_LIST_INIT(em_mask_matrix, EM_MASK_MATRIX)

/// Returns the red part of a #RRGGBB hex sequence as number
#define GETREDPART(hexa) hex2num(copytext(hexa, 2, 4))

/// Returns the green part of a #RRGGBB hex sequence as number
#define GETGREENPART(hexa) hex2num(copytext(hexa, 4, 6))

/// Returns the blue part of a #RRGGBB hex sequence as number
#define GETBLUEPART(hexa) hex2num(copytext(hexa, 6, 8))

/// Parse the hexadecimal color into lumcounts of each perspective.
#define PARSE_LIGHT_COLOR(source) \
do { \
	if (source.light_color != COLOR_WHITE) { \
		var/__light_color = source.light_color; \
		source.lum_r = GETREDPART(__light_color) / 255; \
		source.lum_g = GETGREENPART(__light_color) / 255; \
		source.lum_b = GETBLUEPART(__light_color) / 255; \
	} else { \
		source.lum_r = 1; \
		source.lum_g = 1; \
		source.lum_b = 1; \
	}; \
} while (FALSE)

//Fake ambient occlusion filter
#define LIGHT_OK 0
#define LIGHT_EMPTY 1
#define LIGHT_BROKEN 2
#define LIGHT_BURNED 3

#define SUNLIGHT_RADIUS 9 //Tiles that sunlight penetrates into shade
#define SUNLIGHT_NONE 0
#define SUNLIGHT_POSSIBLE 1
#define SUNLIGHT_CURRENT 2
#define SUNLIGHT_OVERHEAD 3
#define SUNLIGHT_ONLY 4
#define SUNLIGHT_ONLY_SHADE 5

// Keep in mind. Lighting corners accept the bottom left (northwest) set of cords to them as input
// Handles dynamic light
#define GENERATE_MISSING_CORNERS(gen_for) \
	if (!gen_for.lighting_corner_NE) { \
		gen_for.lighting_corner_NE = new /datum/lighting_corner(gen_for.x, gen_for.y, gen_for.z, gen_for.has_dynamic_lighting()); \
	} \
	if (!gen_for.lighting_corner_SE) { \
		gen_for.lighting_corner_SE = new /datum/lighting_corner(gen_for.x, gen_for.y - 1, gen_for.z, gen_for.has_dynamic_lighting()); \
	} \
	if (!gen_for.lighting_corner_SW) { \
		gen_for.lighting_corner_SW = new /datum/lighting_corner(gen_for.x - 1, gen_for.y - 1, gen_for.z, gen_for.has_dynamic_lighting()); \
	} \
	if (!gen_for.lighting_corner_NW) { \
		gen_for.lighting_corner_NW = new /datum/lighting_corner(gen_for.x - 1, gen_for.y, gen_for.z, gen_for.has_dynamic_lighting()); \
	} \
	gen_for.lighting_corners_initialised = TRUE;

/// The awake sunlight handlers live in the membership store under this key (relations proposal D12): a deleted handler leaves it by itself.
#define SUNLIGHT_AWAKE_KEY "lighting:sunlight_awake"

/// A light fixture draws 2 W per luminosity * range (refresh_light(); the fixtures declare it per type, lighting_fixture_glow.dm).
#define LIGHTING_POWER_FACTOR 2

// Client lighting (code/content/lighting/client_*.dm).
/// Side of the chunks glowing lights are indexed by, in turfs.
#define CLIENT_GLOW_CHUNK 8
/// The longest reach a glow is drawn and indexed for, in turfs.
#define CLIENT_GLOW_MAX_RANGE 6
/// The chunk a turf coordinate (x or y) is in.
#define CLIENT_GLOW_CHUNK_OF(coord) round(((coord) - 1) / CLIENT_GLOW_CHUNK)
/// How far a light's glow reaches from its turf on each axis, in turfs: its reach box is the square of this radius about its turf. The chunk index, the holders'
/// boxes and the opacity lookups all measure a light by this one number.
#define CLIENT_GLOW_RADIUS(L) clamp(CEILING((L).light_range, 1), 1, CLIENT_GLOW_MAX_RANGE)
/// TRUE when the square of radius `r` about (sx, sy) lies clear of box list(x0, y0, x1, y1).
#define CLIENT_GLOW_CLEAR_OF(sx, sy, r, box) (((sx) + (r) < (box)[1]) || ((sx) - (r) > (box)[3]) || ((sy) + (r) < (box)[2]) || ((sy) - (r) > (box)[4]))
/// How many chunks past the reach box a held glow is kept before it is dropped (the keep box). A glow is acquired by the reach box alone, so this
/// widens only what is kept: a walk back over this many chunks makes and drops nothing. The held count grows with the keep box's area, which is
/// (chunk + 2 * view half + 2 * keep + 2 * reach range) squared: for the play log's 15x15 view, 2 chunks is 1.7 times the area of 1 (the 111-133 glows held
/// at 1 chunk come to about 190-230, under 460 client images) and 3 chunks would be 2.7 times (about 300-360 glows, 720 images), so 2 is the bound chosen.
#define CLIENT_GLOW_KEEP_CHUNKS 2
/// The most dropped glow images (and, apart, hide images) one holder keeps to reuse; past it a dropped image is simply let go.
#define CLIENT_GLOW_POOL_MAX 64
/// Server milliseconds one step of the stored-shape loader (disk reads) may spend before it leaves the rest of its queue to the next tick.
#define CLIENT_GLOW_STORE_BUDGET_MS 4
/// A store step (one shape read, or one warm-up step) at least this long is logged, whatever the lighting trace says.
#define CLIENT_GLOW_STORE_SLOW_MS 5
/// Server milliseconds one step of a client holder's acquire queue (the glow images a delta crossing makes for lights newly in reach) may spend before it leaves the rest to the next tick.
#define CLIENT_GLOW_ACQUIRE_BUDGET_MS 4
/// The longest a client's held glows wait to follow its eye's sight after it moved inside a chunk (a stand on a turf it no longer sees is a blink). Opacity changes
/// near the eye are followed once per tick (the lighting step).
#define CLIENT_GLOW_SIGHT_INTERVAL (2 TICKS)
/// Server milliseconds one step of a client holder's full scan (a login, a teleport) may spend before it leaves the rest of the chunks to the next ticks: nearest the eye first.
#define CLIENT_GLOW_SCAN_BUDGET_MS 10
/// Where iconforge writes baked shadow masks before they enter the resource cache.
#define CLIENT_GLOW_MASK_DIR "data/client_glow_masks/"
/// Baked shadow masks kept; shapes asked for at once; bakes running at once.
#define CLIENT_GLOW_MASK_CACHE_MAX 8192
#define CLIENT_GLOW_MASK_QUEUE_MAX 512
#define CLIENT_GLOW_MASK_BAKES_MAX 16
/// Baked glows kept on disk across rounds, by shape (bounded: past CLIENT_GLOW_STORE_MAX files the directory is emptied at first use).
#define CLIENT_GLOW_STORE_DIR "data/client_glow_store/"
#define CLIENT_GLOW_STORE_MAX 4096
/// Raise when the bake recipe (client_glow_mask_sprite()) changes: the stored shapes are named by it and by the glow sprites' contents.
#define CLIENT_GLOW_STORE_VERSION "1"
/// How long a client with no session (so no asset ack to wait for) is given to receive a new baked glow PNG before held glows swap to it.
#define CLIENT_GLOW_ICON_DELIVERY (0.5 SECONDS)
/// Iconforge's own limit on one sprite's transforms is 128; the mask stays under it.
#define CLIENT_GLOW_MASK_STEPS_MAX 126
/// The bloom that carries floor light about a tile onto the walls beside it: its blur, its growth before the blur (pixels), its strength.
#define CLIENT_GLOW_SPREAD_SIZE 20
#define CLIENT_GLOW_SPREAD_OFFSET 4
#define CLIENT_GLOW_SPREAD_ALPHA 160
/// The blur over the whole glow plane that softens every tile-shaped cut, so neighbouring colours blend (one filter per client, none per light).
/// Pixels each fade ring of a baked cut adds: wide enough that lights with different reach blend instead of leaving tile-shaped seams (client rig).
#define CLIENT_GLOW_MASK_RING_STEP 4
#define CLIENT_GLOW_SOFTEN_SIZE 4
/// A light this short (a wall device, a console) draws at CLIENT_GLOW_SMALL_SCALE of its power.
#define CLIENT_GLOW_SMALL_RANGE 2
#define CLIENT_GLOW_SMALL_SCALE 0.5
/// How long a light must stand on one turf before it goes back from the plain glow to its baked cut.
#define CLIENT_GLOW_SETTLE_TIME (5 SECONDS)

/// What a client's screen shows of client lighting (client.lighting_screen).
#define CLIENT_GLOW_SCREEN_NONE 0
#define CLIENT_GLOW_SCREEN_BASE 1
#define CLIENT_GLOW_SCREEN_COMPARE_DM 2
#define CLIENT_GLOW_SCREEN_COMPARE_GLOW 3
