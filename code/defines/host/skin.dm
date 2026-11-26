// Control ids of interface/skin.dmf. Every string here must name a window or a
// "window.control" that exists in the skin: tools/ci/check_skin_defines.py checks it.
// Use these instead of string literals in winset()/winget()/winshow()/output().

// Windows
#define SKIN_MAINWINDOW "mainwindow"
#define SKIN_TGUI_SHOCK "tgui_shock"
#define SKIN_ASSET_CACHE_BROWSER "asset_cache_browser"
#define SKIN_OUTPUT_PANE "outputwindow"
#define SKIN_STAT_PANE "statwindow"

// Controls
#define SKIN_MAIN_SPLIT "mainwindow.mainvsplit"
#define SKIN_MAP "mapwindow.map"
#define SKIN_RPANE_SPLIT "rpane.rpanewindow"
#define SKIN_BELLY_OVERLAY "mapwindow.belly_overlay"
#define SKIN_LOBBY_BROWSER "lobby_browser"
#define SKIN_LEGACY_OUTPUT_SELECTOR "outputwindow.legacy_output_selector"
#define SKIN_CHAT_BROWSER "browseroutput"
#define SKIN_STAT_BROWSER "statbrowser"
#define SKIN_COMMANDBAR_SPY "commandbar_spy"

// Viewport fit (client/verb/fit_viewport): the chat/stat side keeps the larger of these pixels and this share of
// the window (unless the window is too narrow, then the two sides split evenly), and the splitter share the fit may pick.
#define FIT_VIEWPORT_MIN_SIDE 480
#define FIT_VIEWPORT_MIN_SIDE_PCT 30
#define FIT_VIEWPORT_MIN_PCT 10
#define FIT_VIEWPORT_MAX_PCT 90
