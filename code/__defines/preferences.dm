// Modes for examine text output
#define EXAMINE_MODE_SLIM		 "Slim"
#define EXAMINE_MODE_VERBOSE	 "Verbose"
#define EXAMINE_MODE_SWITCH_TO_PANEL "Switch To Panel"


// Modes for parsing multilingual speech
#define MULTILINGUAL_DEFAULT			"Default"
#define MULTILINGUAL_SPACE				"Space"
#define MULTILINGUAL_DOUBLE_DELIMITER	"Double Delimiter"
#define MULTILINGUAL_OFF				"Single Language"

#define MULTILINGUAL_MODE_MAX			4

#define SAVE_RESET -1

//randomised elements
#define RANDOM_ANTAG_ONLY 1
#define RANDOM_DISABLED 2
#define RANDOM_ENABLED 3

// randomise_appearance_prefs() and randomize_human_appearance() proc flags
#define RANDOMIZE_SPECIES (1<<0)
#define RANDOMIZE_NAME (1<<1)

// Values for /datum/preference/savefile_identifier
/// This preference is character specific.
#define PREFERENCE_CHARACTER "character"
/// This preference is account specific.
#define PREFERENCE_PLAYER "player"

/// Auto-pick the widget based on the pref subtype.
#define PREF_WIDGET_AUTO        "auto"
/// Plain text input.
#define PREF_WIDGET_TEXT        "text"
/// Multi-line text editor.
#define PREF_WIDGET_LONGTEXT    "longtext"
/// Numeric input with optional min/max/step in widget_props.
#define PREF_WIDGET_NUMBER      "number"
/// Numeric slider (uses min/max/step from widget_props).
#define PREF_WIDGET_SLIDER      "slider"
/// Boolean toggle.
#define PREF_WIDGET_BOOLEAN     "boolean"
/// Single hex color with a picker.
#define PREF_WIDGET_COLOR       "color"
/// Single-pick from a dropdown.
#define PREF_WIDGET_DROPDOWN    "dropdown"
/// Single-pick from a thumbnail grid (icons + names).
#define PREF_WIDGET_THUMBGRID   "thumbgrid"
/// Render through a registered /datum/preference_editor by key.
#define PREF_WIDGET_EDITOR      "editor"
/// Server-managed; not rendered as an editable control.
#define PREF_WIDGET_HIDDEN      "hidden"

#define PREF_UPDATE_ACCEPTED    1
#define PREF_UPDATE_REJECTED    2
#define PREF_UPDATE_UNCHANGED   3

#define PREF_CONSTRAINT_MAX_DEPTH 8
#define PREF_TRANSACTION_BEGIN(prefs) prefs.begin_update_batch()
#define PREF_TRANSACTION_END(prefs)   prefs.end_update_batch()

#define AUTOHISS_OFF    0
#define AUTOHISS_BASIC  1
#define AUTOHISS_FULL   2

// Values for /datum/preferences/current_tab
/// Open the character preference window
#define PREFERENCE_TAB_CHARACTER_PREFERENCES 0

/// Open the game preferences window
#define PREFERENCE_TAB_GAME_PREFERENCES 1

/// These will be shown in the character sidebar, but at the bottom.
#define PREFERENCE_CATEGORY_FEATURES "features"

/// Any preferences that will show to the sides of the character in the setup menu.
#define PREFERENCE_CATEGORY_CLOTHING "clothing"

/// Preferences that will be put into the 3rd list, and are not contextual.
#define PREFERENCE_CATEGORY_NON_CONTEXTUAL "non_contextual"

/// Will be put under the game preferences window.
#define PREFERENCE_CATEGORY_GAME_PREFERENCES "game_preferences"

/// These will show in the list to the right of the character preview.
#define PREFERENCE_CATEGORY_SECONDARY_FEATURES "secondary_features"

/// These are preferences that are supplementary for main features,
/// such as hair color being affixed to hair.
#define PREFERENCE_CATEGORY_SUPPLEMENTAL_FEATURES "supplemental_features"

/// These preferences will not be rendered on the preferences page, and are practically invisible unless specifically rendered. Used for quirks, currently.
#define PREFERENCE_CATEGORY_MANUALLY_RENDERED "manually_rendered_features"

/// Emote switch preferences
#define EMOTE_SOUND_NO_FREQ "Default"
#define EMOTE_SOUND_VOICE_FREQ "Voice Frequency"
#define EMOTE_SOUND_VOICE_LIST "Voice Sound"

// Choose grid or list TGUI layouts for UI's, when possible.
/// Force grid layout, even if default is a list.
#define TGUI_LAYOUT_GRID "grid"
/// Force list layout, even if default is a grid.
#define TGUI_LAYOUT_LIST "list"

#define WRITE_PREF_NORMAL 1
#define WRITE_PREF_INSTANT 2
#define WRITE_PREF_MANUAL 3

#define PAI_UNSET "None Set"
#define PAI_DEFAULT_CHASSIS "Drone"
#define PAI_DEFAULT_EMAGGED_CHASSIS "Syndicate Fox"

#define DEFAULT_LATEJOIN_LOCATION /datum/spawnpoint/arrivals
