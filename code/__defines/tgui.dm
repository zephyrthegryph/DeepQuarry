/// Maximum number of windows that can be suspended/reused
#define TGUI_WINDOW_SOFT_LIMIT 5
/// Maximum number of open windows
#define TGUI_WINDOW_HARD_LIMIT 9

/// Maximum ping timeout allowed to detect zombie windows
#define TGUI_PING_TIMEOUT (4 SECONDS)
/// Used for rate-limiting to prevent DoS by excessively refreshing a TGUI window
#define TGUI_REFRESH_FULL_UPDATE_COOLDOWN (1 SECONDS)

/// Local-development TGUI diagnostics: server startup telemetry in /datum/tgui/open(),
/// native shell transition logging, and unconditional acceptance of browser perf/...
/// telemetry topics from any address. Deliberately NOT tied to the codebase-wide
/// `DEBUG` define (which is always on), so production builds enforce the localhost
/// gate on perf/... topics. Auto-enabled under CIBUILDING; uncomment to opt in locally.
// #define TGUI_DEV_DIAGNOSTICS
#if defined(CIBUILDING) && !defined(TGUI_DEV_DIAGNOSTICS)
#define TGUI_DEV_DIAGNOSTICS
#endif

/// Minimum spacing between accepted browser perf/... telemetry topics per window.
#define TGUI_PERF_LOG_COOLDOWN (1 SECONDS)
/// Maximum number of chunked (oversized) browser payloads a window may be assembling at once.
#define TGUI_MAX_OVERSIZED_PAYLOADS 4
/// Maximum payloadChunk topics accepted per window per second. The browser sends
/// chunks serially (each waits for an acknowledgement), so legitimate traffic sits
/// well under this.
#define TGUI_MAX_PAYLOAD_CHUNKS_PER_SECOND 100
/// How long an idle prewarmed shell may remain LOADING before it is torn down and replaced.
#define TGUI_PREWARM_LOAD_TIMEOUT (30 SECONDS)

/// Window does not exist
#define TGUI_WINDOW_CLOSED 0
/// Window was just opened, but is still not ready to be sent data
#define TGUI_WINDOW_LOADING 1
/// Window is free and ready to receive data
#define TGUI_WINDOW_READY 2

/// Get a window id based on the provided pool index
#define TGUI_WINDOW_ID(index) "tgui-window-[index]"
/// Get a pool index of the provided window id
#define TGUI_WINDOW_INDEX(window_id) text2num(copytext(window_id, 13))

/// Creates a message packet for sending via output()
// This is {"type":type,"payload":payload}, but pre-encoded. This is much faster
// than doing it the normal way.
// To ensure this is correct, this is unit tested in tgui_create_message.
#define TGUI_CREATE_MESSAGE(type, payload) ( \
	"%7b%22type%22%3a%22[type]%22%2c%22payload%22%3a[url_encode(json_encode(payload))]%7d" \
)

/// Though not the maximum renderable ByondUis within tgui, this is the maximum that the server will manage per-UI
#define TGUI_MANAGED_BYONDUI_LIMIT 10

// These are defines instead of being inline, as they're being sent over
// from tgui-core, so can't be easily played with
#define TGUI_MANAGED_BYONDUI_TYPE_RENDER "renderByondUi"
#define TGUI_MANAGED_BYONDUI_TYPE_UNMOUNT "unmountByondUi"

#define TGUI_MANAGED_BYONDUI_PAYLOAD_ID "renderByondUi"

/// Max length for Modal Input
#define TGUI_MODAL_INPUT_MAX_LENGTH 1024
/// Max length for Modal Input for names
#define TGUI_MODAL_INPUT_MAX_LENGTH_NAME 64 // Names for generally anything don't go past 32, let alone 64.

#define TGUI_MODAL_OPEN 1
#define TGUI_MODAL_DELEGATE 2
#define TGUI_MODAL_ANSWER 3
#define TGUI_MODAL_CLOSE 4

/**
 * Gets a ui_state that checks to see if the user has specific admin permissions.
 *
 * Arguments:
 * * required_perms: Which admin permission flags to check the user for, such as [R_ADMIN]
 */
#define ADMIN_STATE(required_perms) (GLOB.admin_states[required_perms] ||= new /datum/tgui_state/admin_state(required_perms))

/// What a queued window is owed in phase R (code/modules/tgui/ui_push.dm): its data, a re-run of the host's interact (an update_uis() request), a status re-check.
#define UI_PUSH_DATA (1<<0)
#define UI_PUSH_INTERACT (1<<1)
#define UI_PUSH_STATUS (1<<2)
