//! Shared reactive result rows, not a semantic tree or source receipt.
//! Producers retain their own original input authority; these rows grant none.
use std::collections::{BTreeMap,BTreeSet};
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord,serde::Serialize)]
pub struct Untracked {
    pub what: String,
    /// The type that declares the var read (empty when the finding is not a var read).
    pub owner: String,
    pub rel: String,
    pub line: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord,serde::Serialize)]
pub struct Leaf {
    pub owner: String,
    pub var: String,
    pub rel: String,
    pub line: u32,
}

pub struct DepsAnalysis {
    /// "<type>::<proc>" -> its untracked reads.
    pub consumers: BTreeMap<String, Vec<Untracked>>,
    /// The consumers that are draw() procs (the lint reports them as `draw_untracked`).
    pub draws: BTreeSet<String>,
    /// Untracked leaves, per declaring type.
    pub leaves: Vec<Leaf>,
    /// "<type>" -> the holder vars its own draw() reads.
    pub draw_reads: BTreeMap<String, BTreeSet<String>>,
    /// "<type>" -> the published keys its own draw() reads through a READS_AS accessor (`nutrition_of(src)` stands for MOB_KEY_NUTRITION), as the
    /// DM text of the key (a define is written `[MOB_KEY_NUTRITION]` so the compile resolves it): a PUBLISH_CHANGE of one redraws the thing.
    pub draw_keys: BTreeMap<String, BTreeSet<String>>,
    /// "<type>" -> what its own draw() reads one container, turf or area hop away, as "<hop>.<var>".
    pub draw_hops: BTreeMap<String, BTreeSet<String>>,
    /// "<type>" -> the first segment of every hop chain its own draw() reads (a link var on the holder, `cell` of `cell.charge`): a write of the
    /// link changes what the draw sees. The change graph's plans (`gen plans`) mark these PLAN_DRAW too.
    pub draw_links: BTreeMap<String, BTreeSet<String>>,
    /// "<type>::hidden_verbs" / "<type>::granted_verbs" -> the holder vars (and hop chains' first segments) that proc reads, and whether its
    /// walk left a read unresolved: the verb outputs share the draw's refresh bit, so the plans need them before a write may skip a redraw.
    pub verb_reads: BTreeMap<String, (BTreeSet<String>, bool)>,
    /// The var names contribution and condition handlers and STAT formulas read (a holder var, each link of a hop chain, a system var): the
    /// over-inclusive stat input set `gen plans` writes takes them beside the declared names.
    pub stat_reads: BTreeSet<String>,
    /// Every `(declaring type, var)` a consumer reads off the holder (or through a declared relation hop), whatever its class: the read
    /// set `gens::auto_tracked` turns into tracked vars.
    pub reads: BTreeSet<(String, String)>,
    /// The reads of `reads` no declaration makes reactive (see `gens::auto_tracked::candidate`): the vars the inference tracks.
    pub candidates: BTreeSet<(String, String)>,
    /// "<type>::<proc>" of a draw, a contribution or a STAT formula -> where it samples with `read_once()` (rule `sampled_in_look`).
    pub sampled: BTreeMap<String, BTreeSet<(String, u32)>>,
}
