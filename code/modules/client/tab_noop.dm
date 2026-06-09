// DreamSeeker's built-in TAB key handler toggles hotkey mode client-side
// when the active macro has no TAB binding (or an empty one). We've
// already removed the non-hotkey "macro" / "borgmacro" skin elements
// the toggle used to focus on, so the toggle's destination is broken —
// the result is a UI that visually breaks when the player presses TAB.
//
// The fix is to bind TAB to a real, no-op server-side verb. A verb
// dispatch is unambiguously "the macro consumed the key", so
// DreamSeeker doesn't fall back to its built-in toggle. The verb does
// nothing.

/client/verb/quarry_tab_noop()
	set hidden = TRUE
	set name = ".dq-tab-noop"
	return
