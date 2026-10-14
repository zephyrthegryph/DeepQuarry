/// The hand mark of an item's worn or held look, left by the human-draw conversion where the state it stands for is not tracked yet: marks `E`
/// and what draws it for a re-derive. A call goes when the state behind it is a tracked var, a relation or a stat (the holder's draw watches it
/// and redraws by itself). No new call: the files that still carry one are the `changed_mark_pending` list of tools/ci/lint_scopes.toml.
/proc/changed(datum/E)
	return state_changed(E)
