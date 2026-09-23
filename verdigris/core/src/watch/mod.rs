//! Watches (`rust_core.md` §6.2–§6.4): conditions on channels, checked at
//! registration, evaluated inside the frame next to their data, and turned
//! into wakes in the domain's [`Outbox`].
//!
//! `rust_architecture.md` §4.7: "There is one module, watch, and
//! revision.rs merges into it as the 'read-directly' variant" -- see
//! [`revision`]. This module and its `revision` submodule are the *only*
//! change-tracking primitives; a domain keeping its own revision counter or
//! dirty set is exactly what `rust_architecture.md` §2 and the
//! `check_rust_core_consolidation` CI check forbid.
//!
//! # Semantics
//!
//! Watches see **frame-end states**: each frame's evaluation compares the
//! new state with the state the watch last saw. A value that crosses a
//! limit and comes back within one frame never fires, because no view (and
//! so no DM read) ever showed it on the other side.
//!
//! | Kind | Fires when |
//! |---|---|
//! | `Changed(cell, mask)` | a listed channel moves more than its declared hysteresis from the baseline (the value at the last fire). Vector channels compare per component; enum channels fire on any change. The reason is the mask of channels that moved. Never fires at registration. |
//! | `Threshold(cell, level)` | `Above` enters at `v >= limit` and leaves at `v < limit - h`; `Below` enters at `v <= limit` and leaves at `v > limit + h`. Fires on entering (and, with `Edge::Both`, on leaving). If the condition already holds at registration, the first evaluation fires. |
//! | `Band(cell, ch, levels)` | the band (the number of levels `<= v`) changes. Moving up takes effect at the level; moving down needs `v < level - h`. Always fires once at registration, to report the starting band. |
//! | `Difference(a, b, level, abs)` | `a - b` (or `|a - b|`) crosses `level` exactly as a `Threshold` would. |
//! | `ThresholdSet(cell, ch)` | any of its entries crosses (each entry is a `Threshold` with a payload and generation). Every crossing emits an [`EventKind::ThresholdCrossed`] event plus one wake. Entries are added and removed by command without touching the others. |
//! | `Any([..])` | any child fires; the reasons are merged. |
//! | `All([..])` | the conjunction of its children's conditions becomes true. Children must be level conditions (`Threshold`, `Difference`, `All`). |
//!
//! Each watch fires at most once per frame, with its reasons merged, and
//! non-finite channel values are ignored (the state holds).
//!
//! # Where they run
//!
//! [`WatchState`] is a frame resource. Its task runs after every physics
//! task of the frame and finds changed cells by chunk: a chunk that is still
//! the same allocation as at the last evaluation cannot have changed
//! (copy-on-write, §3.3), so only watches with a cell in a changed chunk are
//! evaluated. Watches are bucketed by the chunk of their first cell and the
//! buckets are evaluated in parallel; outputs are concatenated in bucket
//! order, so results never depend on thread timing (§3.9).
//!
//! Registration goes through the main-thread [`WatchPort`], which checks the
//! condition against the channel table (§6.3), hands DM a [`WatchId`] at
//! once, and queues the watch for the next frame like any command.

pub mod revision;

use std::fmt;

use crate::channel::{ChannelId, ChannelInfo, Channels, MAX_WIDTH, Quantity, Unit, ValueKind};
use crate::cow::{ChunkLayout, CowStore};
use crate::outbox::{
    Event, EventKind, Lane, MAX_SUBSCRIBER, Outbox, Subscriber, Wake, WatchId, reason,
};
use crate::owner::DomainState;

/// Which side of a limit a level condition is about.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cmp {
    Above,
    Below,
}

/// Which crossings fire.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Edge {
    /// Only entering the condition.
    Enter,
    /// Entering and leaving.
    Both,
}

/// A limit on one scalar channel.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Level {
    pub ch: ChannelId,
    pub cmp: Cmp,
    pub limit: Quantity,
    /// `None` takes the channel's declared hysteresis.
    pub hysteresis: Option<f32>,
    pub edge: Edge,
}

impl Level {
    #[must_use]
    pub const fn above(ch: ChannelId, limit: Quantity) -> Self {
        Self {
            ch,
            cmp: Cmp::Above,
            limit,
            hysteresis: None,
            edge: Edge::Enter,
        }
    }

    #[must_use]
    pub const fn below(ch: ChannelId, limit: Quantity) -> Self {
        Self {
            ch,
            cmp: Cmp::Below,
            limit,
            hysteresis: None,
            edge: Edge::Enter,
        }
    }

    #[must_use]
    pub const fn hysteresis(mut self, h: f32) -> Self {
        self.hysteresis = Some(h);
        self
    }

    #[must_use]
    pub const fn both_edges(mut self) -> Self {
        self.edge = Edge::Both;
        self
    }
}

/// A watch condition (§6.2).
#[derive(Clone, Debug, PartialEq)]
pub enum Cond {
    Changed {
        cell: u32,
        mask: u32,
    },
    Threshold {
        cell: u32,
        level: Level,
    },
    Band {
        cell: u32,
        ch: ChannelId,
        unit: Unit,
        /// Strictly increasing, and further apart than the hysteresis.
        levels: Vec<f32>,
        hysteresis: Option<f32>,
    },
    Difference {
        a: u32,
        b: u32,
        level: Level,
        abs: bool,
    },
    ThresholdSet {
        cell: u32,
        ch: ChannelId,
    },
    Any(Vec<Cond>),
    All(Vec<Cond>),
}

/// Deepest nesting of `Any`/`All`.
pub const MAX_DEPTH: usize = 4;

/// One entry of a `ThresholdSet` (a container's latent contents, one
/// reaction temperature, ...).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SetEntry {
    /// Identifies the entry within its set; returned in events.
    pub payload: u32,
    /// The ledger's generation for the payload; a crossing reported for an
    /// older generation is stale and dropped on the main thread.
    pub generation: u32,
    pub cmp: Cmp,
    pub limit: Quantity,
    pub hysteresis: Option<f32>,
    pub edge: Edge,
}

/// Why a condition is rejected (§6.3). Raised as a DM runtime with context
/// at registration, or failing the boot for declared conditions.
#[derive(Clone, Debug, PartialEq)]
pub enum WatchError {
    UnknownChannel(ChannelId),
    NotScalar {
        channel: &'static str,
    },
    UnitMismatch {
        channel: &'static str,
        expected: Unit,
        got: Unit,
    },
    BadHysteresis {
        hysteresis: f32,
    },
    NonFinite {
        value: f32,
    },
    BandLevels {
        reason: &'static str,
    },
    CellOutOfRange {
        cell: u32,
        len: u32,
    },
    SameCell {
        cell: u32,
    },
    BadMask {
        mask: u32,
    },
    EmptyCombination,
    NotALevel,
    TooDeep,
    BadSubscriber(Subscriber),
    /// No such watch (never registered, or already removed).
    StaleWatch(WatchId),
    /// Set entries go on `ThresholdSet` watches only.
    NotASet(WatchId),
}

impl fmt::Display for WatchError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnknownChannel(ch) => write!(f, "channel {} is not declared", ch.0),
            Self::NotScalar { channel } => {
                write!(
                    f,
                    "channel {channel} is not a scalar; only Changed can watch it"
                )
            }
            Self::UnitMismatch {
                channel,
                expected,
                got,
            } => write!(
                f,
                "channel {channel} is in {expected:?}, the limit is in {got:?}"
            ),
            Self::BadHysteresis { hysteresis } => {
                write!(f, "hysteresis {hysteresis} must be finite and >= 0")
            }
            Self::NonFinite { value } => write!(f, "limit {value} is not finite"),
            Self::BandLevels { reason } => write!(f, "band levels {reason}"),
            Self::CellOutOfRange { cell, len } => {
                write!(f, "cell {cell} is outside the domain (0..{len})")
            }
            Self::SameCell { cell } => write!(f, "difference of cell {cell} with itself"),
            Self::BadMask { mask } => write!(f, "mask {mask:#x} names undeclared channels"),
            Self::EmptyCombination => write!(f, "Any/All needs at least one condition"),
            Self::NotALevel => write!(
                f,
                "All combines level conditions only (Threshold, Difference, All)"
            ),
            Self::TooDeep => write!(f, "conditions nest at most {MAX_DEPTH} deep"),
            Self::BadSubscriber(s) => write!(f, "subscriber {s} is out of range"),
            Self::StaleWatch(id) => {
                write!(f, "watch {}:{} does not exist", id.index, id.generation)
            }
            Self::NotASet(id) => write!(f, "watch {} is not a ThresholdSet", id.index),
        }
    }
}

impl std::error::Error for WatchError {}

/// Checks `cond` against a channel table. `cells` is the domain's cell
/// count, or `None` to skip cell checks (declared rule templates at boot).
///
/// # Errors
/// The first problem found.
pub fn validate(cond: &Cond, chans: &[ChannelInfo], cells: Option<u32>) -> Result<(), WatchError> {
    compile(cond, chans, cells, 0).map(|_| ())
}

fn check_cell(cell: u32, cells: Option<u32>) -> Result<(), WatchError> {
    match cells {
        Some(len) if cell >= len => Err(WatchError::CellOutOfRange { cell, len }),
        _ => Ok(()),
    }
}

fn scalar_channel(
    chans: &[ChannelInfo],
    ch: ChannelId,
    unit: Unit,
) -> Result<ChannelInfo, WatchError> {
    let info = *chans
        .get(ch.index())
        .ok_or(WatchError::UnknownChannel(ch))?;
    if info.kind != ValueKind::Scalar {
        return Err(WatchError::NotScalar { channel: info.name });
    }
    if info.unit != unit {
        return Err(WatchError::UnitMismatch {
            channel: info.name,
            expected: info.unit,
            got: unit,
        });
    }
    Ok(info)
}

fn check_hysteresis(h: f32) -> Result<f32, WatchError> {
    if h.is_finite() && h >= 0.0 {
        Ok(h)
    } else {
        Err(WatchError::BadHysteresis { hysteresis: h })
    }
}

fn check_finite(v: f32) -> Result<f32, WatchError> {
    if v.is_finite() {
        Ok(v)
    } else {
        Err(WatchError::NonFinite { value: v })
    }
}

fn compile_thresh(
    chans: &[ChannelInfo],
    ch: ChannelId,
    cmp: Cmp,
    limit: Quantity,
    hysteresis: Option<f32>,
    edge: Edge,
) -> Result<Thresh, WatchError> {
    let info = scalar_channel(chans, ch, limit.unit)?;
    Ok(Thresh {
        ch,
        cmp,
        limit: check_finite(limit.value)?,
        hyst: check_hysteresis(hysteresis.unwrap_or(info.hysteresis))?,
        edge,
        inside: None,
    })
}

fn compile(
    cond: &Cond,
    chans: &[ChannelInfo],
    cells: Option<u32>,
    depth: usize,
) -> Result<Node, WatchError> {
    Ok(match cond {
        Cond::Changed { cell, mask } => {
            check_cell(*cell, cells)?;
            let declared = if chans.len() >= 32 {
                u32::MAX
            } else {
                (1u32 << chans.len()) - 1
            };
            if *mask == 0 || mask & !declared != 0 {
                return Err(WatchError::BadMask { mask: *mask });
            }
            let width = (0..chans.len())
                .filter(|i| mask & (1 << i) != 0)
                .map(|i| chans[i].kind.width())
                .sum();
            Node::Changed {
                cell: *cell,
                mask: *mask,
                baseline: Baseline::new(width),
                primed: false,
            }
        }
        Cond::Threshold { cell, level } => {
            check_cell(*cell, cells)?;
            Node::Threshold {
                cell: *cell,
                t: compile_thresh(
                    chans,
                    level.ch,
                    level.cmp,
                    level.limit,
                    level.hysteresis,
                    level.edge,
                )?,
            }
        }
        Cond::Band {
            cell,
            ch,
            unit,
            levels,
            hysteresis,
        } => {
            check_cell(*cell, cells)?;
            let info = scalar_channel(chans, *ch, *unit)?;
            let hyst = check_hysteresis(hysteresis.unwrap_or(info.hysteresis))?;
            if levels.is_empty() {
                return Err(WatchError::BandLevels {
                    reason: "are empty",
                });
            }
            for &l in levels {
                check_finite(l)?;
            }
            if levels.windows(2).any(|w| w[1] <= w[0]) {
                return Err(WatchError::BandLevels {
                    reason: "must be strictly increasing",
                });
            }
            if levels.windows(2).any(|w| w[1] - w[0] <= hyst) {
                return Err(WatchError::BandLevels {
                    reason: "must be further apart than the hysteresis",
                });
            }
            Node::Band {
                cell: *cell,
                ch: *ch,
                levels: levels.clone().into_boxed_slice(),
                hyst,
                band: None,
            }
        }
        Cond::Difference { a, b, level, abs } => {
            check_cell(*a, cells)?;
            check_cell(*b, cells)?;
            if a == b {
                return Err(WatchError::SameCell { cell: *a });
            }
            Node::Difference {
                a: *a,
                b: *b,
                abs: *abs,
                t: compile_thresh(
                    chans,
                    level.ch,
                    level.cmp,
                    level.limit,
                    level.hysteresis,
                    level.edge,
                )?,
            }
        }
        Cond::ThresholdSet { cell, ch } => {
            check_cell(*cell, cells)?;
            let info = *chans
                .get(ch.index())
                .ok_or(WatchError::UnknownChannel(*ch))?;
            if info.kind != ValueKind::Scalar {
                return Err(WatchError::NotScalar { channel: info.name });
            }
            Node::Set {
                cell: *cell,
                ch: *ch,
                entries: Vec::new(),
            }
        }
        Cond::Any(children) | Cond::All(children) => {
            if depth >= MAX_DEPTH {
                return Err(WatchError::TooDeep);
            }
            if children.is_empty() {
                return Err(WatchError::EmptyCombination);
            }
            let all = matches!(cond, Cond::All(_));
            let nodes = children
                .iter()
                .map(|c| {
                    if all
                        && !matches!(
                            c,
                            Cond::Threshold { .. } | Cond::Difference { .. } | Cond::All(_)
                        )
                    {
                        return Err(WatchError::NotALevel);
                    }
                    compile(c, chans, cells, depth + 1)
                })
                .collect::<Result<Vec<_>, _>>()?;
            if all {
                Node::All {
                    children: nodes,
                    on: None,
                }
            } else {
                Node::Any(nodes)
            }
        }
    })
}

/// `Changed` baselines. Most watches cover a few scalar channels, so the
/// baseline lives inline in the watch (no pointer chase per evaluation).
#[derive(Clone, Debug)]
enum Baseline {
    Inline([f32; 4]),
    Heap(Box<[f32]>),
}

impl Baseline {
    fn new(width: usize) -> Self {
        if width <= 4 {
            Self::Inline([0.0; 4])
        } else {
            Self::Heap(vec![0.0; width].into_boxed_slice())
        }
    }

    fn as_mut(&mut self) -> &mut [f32] {
        match self {
            Self::Inline(a) => a,
            Self::Heap(b) => b,
        }
    }
}

/// A compiled threshold with its state.
#[derive(Clone, Debug)]
struct Thresh {
    ch: ChannelId,
    cmp: Cmp,
    limit: f32,
    hyst: f32,
    edge: Edge,
    /// `None` until first evaluated.
    inside: Option<bool>,
}

impl Thresh {
    /// Updates the state with a new value; `Some(entered)` if that fires.
    fn update(&mut self, v: f32) -> Option<bool> {
        if !v.is_finite() {
            return None;
        }
        let was = self.inside.unwrap_or(false);
        let now = if was {
            match self.cmp {
                Cmp::Above => v >= self.limit - self.hyst,
                Cmp::Below => v <= self.limit + self.hyst,
            }
        } else {
            match self.cmp {
                Cmp::Above => v >= self.limit,
                Cmp::Below => v <= self.limit,
            }
        };
        self.inside = Some(now);
        (now != was && (now || self.edge == Edge::Both)).then_some(now)
    }
}

#[derive(Clone, Debug)]
struct SetSlot {
    entry: SetEntry,
    t: Thresh,
}

/// A compiled condition with its evaluation state.
#[derive(Clone, Debug)]
enum Node {
    Changed {
        cell: u32,
        mask: u32,
        baseline: Baseline,
        primed: bool,
    },
    Threshold {
        cell: u32,
        t: Thresh,
    },
    Band {
        cell: u32,
        ch: ChannelId,
        levels: Box<[f32]>,
        hyst: f32,
        band: Option<usize>,
    },
    Difference {
        a: u32,
        b: u32,
        abs: bool,
        t: Thresh,
    },
    Set {
        cell: u32,
        ch: ChannelId,
        entries: Vec<SetSlot>,
    },
    Any(Vec<Node>),
    All {
        children: Vec<Node>,
        on: Option<bool>,
    },
}

/// What one evaluation produced.
#[derive(Default)]
struct Fired {
    reason: u32,
    source: Option<u32>,
}

impl Fired {
    fn add(&mut self, reason: u32, source: u32) {
        self.reason |= reason;
        self.source.get_or_insert(source);
    }
}

/// Read access to channel values during evaluation.
struct Reader<'a, D: Channels> {
    store: &'a CowStore<D::Value>,
}

impl<D: Channels> Reader<'_, D> {
    fn scalar(&self, cell: u32, ch: ChannelId) -> f32 {
        self.store
            .with(cell, |v| D::scalar(v, ch))
            .unwrap_or(f32::NAN)
    }

    fn components(&self, cell: u32, ch: usize, out: &mut [f32]) {
        let decl = &D::CHANNELS[ch];
        self.store.with(cell, |v| (decl.extract)(v, out));
    }
}

impl Node {
    fn cells(&self, out: &mut Vec<u32>) {
        match self {
            Self::Changed { cell, .. }
            | Self::Threshold { cell, .. }
            | Self::Band { cell, .. }
            | Self::Set { cell, .. } => out.push(*cell),
            Self::Difference { a, b, .. } => out.extend([*a, *b]),
            Self::Any(c) | Self::All { children: c, .. } => c.iter().for_each(|n| n.cells(out)),
        }
    }

    /// The level of a level condition (for `All`).
    fn level(&self) -> bool {
        match self {
            Self::Threshold { t, .. } | Self::Difference { t, .. } => t.inside.unwrap_or(false),
            Self::All { on, .. } => on.unwrap_or(false),
            _ => false,
        }
    }

    fn eval<D: Channels>(
        &mut self,
        r: &Reader<'_, D>,
        watch: WatchId,
        fired: &mut Fired,
        events: &mut Vec<Event>,
    ) {
        match self {
            Self::Changed {
                cell,
                mask,
                baseline,
                primed,
            } => {
                let mut buf = [0.0f32; MAX_WIDTH];
                let mut at = 0;
                let mut moved = 0;
                let mut m = *mask;
                while m != 0 {
                    let ch = m.trailing_zeros() as usize;
                    m &= m - 1;
                    let decl = &D::CHANNELS[ch];
                    let w = decl.kind.width();
                    r.components(*cell, ch, &mut buf[..w]);
                    let base = &mut baseline.as_mut()[at..at + w];
                    let past = *primed
                        && buf[..w].iter().zip(base.iter()).any(|(&v, &b)| {
                            v.is_finite()
                                && match decl.kind {
                                    ValueKind::Enum(_) => v != b,
                                    _ => (v - b).abs() > decl.hysteresis || (!b.is_finite()),
                                }
                        });
                    if !*primed || past {
                        base.copy_from_slice(&buf[..w]);
                    }
                    if past {
                        moved |= 1 << ch;
                    }
                    at += w;
                }
                *primed = true;
                if moved != 0 {
                    fired.add(moved, *cell);
                }
            }
            Self::Threshold { cell, t } => {
                if t.update(r.scalar(*cell, t.ch)).is_some() {
                    fired.add(reason::CONDITION | t.ch.bit(), *cell);
                }
            }
            Self::Band {
                cell,
                ch,
                levels,
                hyst,
                band,
            } => {
                let v = r.scalar(*cell, *ch);
                if !v.is_finite() {
                    return;
                }
                let raw = levels.partition_point(|&l| l <= v);
                let next = match *band {
                    None => raw,
                    Some(cur) if raw >= cur => raw,
                    Some(cur) => {
                        // Leaving downward needs v below level - h.
                        let held = levels.partition_point(|&l| l - *hyst <= v);
                        held.min(cur)
                    }
                };
                if *band != Some(next) {
                    *band = Some(next);
                    fired.add(reason::CONDITION | ch.bit(), *cell);
                }
            }
            Self::Difference { a, b, abs, t } => {
                let d = r.scalar(*a, t.ch) - r.scalar(*b, t.ch);
                let d = if *abs { d.abs() } else { d };
                if t.update(d).is_some() {
                    fired.add(reason::CONDITION | t.ch.bit(), *a);
                }
            }
            Self::Set { cell, ch, entries } => {
                let v = r.scalar(*cell, *ch);
                for slot in entries.iter_mut() {
                    if let Some(entered) = slot.t.update(v) {
                        fired.add(reason::CONDITION | ch.bit(), *cell);
                        events.push(Event {
                            kind: EventKind::ThresholdCrossed,
                            key: watch.index,
                            value: if entered { 1.0 } else { 0.0 },
                            extra: slot.entry.payload,
                            generation: slot.entry.generation,
                        });
                    }
                }
            }
            Self::Any(children) => {
                for c in children {
                    c.eval(r, watch, fired, events);
                }
            }
            Self::All { children, on } => {
                let mut ignored = Fired::default();
                for c in children.iter_mut() {
                    c.eval(r, watch, &mut ignored, events);
                }
                let now = children.iter().all(Node::level);
                let was = on.unwrap_or(false);
                *on = Some(now);
                if now && !was {
                    fired.add(
                        reason::CONDITION | ignored.reason,
                        ignored.source.unwrap_or(0),
                    );
                }
            }
        }
    }
}

/// A queued change to a domain's watches.
#[derive(Clone, Debug)]
enum WatchCmd {
    Add(Box<Watch>),
    Remove(WatchId),
    AddEntry(WatchId, SetEntry, Thresh),
    RemoveEntry(WatchId, u32),
}

#[derive(Clone, Debug)]
struct Watch {
    id: WatchId,
    subscriber: Subscriber,
    lane: Lane,
    node: Node,
    /// Chunks of its cells other than the home chunk.
    remote: Vec<u32>,
    /// Not yet evaluated.
    fresh: bool,
}

#[derive(Clone, Debug, Default)]
struct Bucket {
    watches: Vec<Watch>,
    remote: u32,
    fresh: bool,
}

/// Counters from the last evaluation.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct WatchStats {
    pub watches: usize,
    pub changed_chunks: usize,
    pub evaluated: usize,
    pub wakes: usize,
}

/// A domain's watches, owned by the frame world.
pub struct WatchState<D: Channels> {
    layout: ChunkLayout,
    buckets: Vec<Bucket>,
    /// Where each watch index lives: `(bucket, position)`.
    loc: Vec<Option<(u32, u32)>>,
    prev: Option<CowStore<D::Value>>,
    pending: Vec<WatchCmd>,
    changed: Vec<bool>,
    stats: WatchStats,
}

impl<D: Channels> WatchState<D> {
    #[must_use]
    pub fn new(layout: ChunkLayout) -> Self {
        Self {
            layout,
            buckets: vec![Bucket::default(); layout.chunk_count()],
            loc: Vec::new(),
            prev: None,
            pending: Vec::new(),
            changed: vec![false; layout.chunk_count()],
            stats: WatchStats::default(),
        }
    }

    #[must_use]
    pub const fn stats(&self) -> WatchStats {
        self.stats
    }

    fn chunk_of(&self, cell: u32) -> u32 {
        u32::try_from(
            self.layout
                .locate(cell)
                .expect("validated at registration")
                .0,
        )
        .expect("chunk count fits u32")
    }

    fn find(&mut self, id: WatchId) -> Option<&mut Watch> {
        let (b, p) = (*self.loc.get(id.index as usize)?)?;
        let w = &mut self.buckets[b as usize].watches[p as usize];
        (w.id == id).then_some(w)
    }

    fn apply(&mut self, cmd: WatchCmd) {
        match cmd {
            WatchCmd::Add(mut w) => {
                let mut cells = Vec::new();
                w.node.cells(&mut cells);
                let home = self.chunk_of(cells[0]);
                let mut remote: Vec<u32> = cells
                    .iter()
                    .map(|&c| self.chunk_of(c))
                    .filter(|&c| c != home)
                    .collect();
                remote.sort_unstable();
                remote.dedup();
                w.remote = remote;
                let bucket = &mut self.buckets[home as usize];
                if !w.remote.is_empty() {
                    bucket.remote += 1;
                }
                bucket.fresh = true;
                let index = w.id.index as usize;
                if self.loc.len() <= index {
                    self.loc.resize(index + 1, None);
                }
                self.loc[index] = Some((home, u32::try_from(bucket.watches.len()).expect("fits")));
                bucket.watches.push(*w);
            }
            WatchCmd::Remove(id) => {
                let Some(Some((b, p))) = self.loc.get(id.index as usize).copied() else {
                    return;
                };
                let bucket = &mut self.buckets[b as usize];
                if bucket.watches[p as usize].id != id {
                    return;
                }
                let gone = bucket.watches.swap_remove(p as usize);
                if !gone.remote.is_empty() {
                    bucket.remote -= 1;
                }
                if let Some(moved) = bucket.watches.get(p as usize) {
                    self.loc[moved.id.index as usize] = Some((b, p));
                }
                self.loc[id.index as usize] = None;
            }
            WatchCmd::AddEntry(id, entry, t) => {
                if let Some(w) = self.find(id) {
                    if let Node::Set { entries, .. } = &mut w.node {
                        entries.push(SetSlot { entry, t });
                        w.fresh = true;
                    }
                    let (b, _) = self.loc[id.index as usize].expect("found");
                    self.buckets[b as usize].fresh = true;
                }
            }
            WatchCmd::RemoveEntry(id, payload) => {
                if let Some(w) = self.find(id)
                    && let Node::Set { entries, .. } = &mut w.node
                    && let Some(i) = entries.iter().position(|s| s.entry.payload == payload)
                {
                    entries.swap_remove(i);
                }
            }
        }
    }

    fn enqueue(&mut self, cmds: Vec<WatchCmd>) {
        self.pending.extend(cmds);
    }

    /// Applies queued registrations, then evaluates every watch with a cell
    /// in a chunk that changed since the last evaluation (and every new
    /// watch), writing wakes and events to `out`.
    pub fn evaluate(&mut self, store: &CowStore<D::Value>, out: &mut Outbox<D::Value>) {
        use rayon::prelude::*;
        for cmd in std::mem::take(&mut self.pending) {
            self.apply(cmd);
        }
        match &self.prev {
            None => self.changed.fill(true),
            Some(prev) => {
                self.changed.fill(false);
                for c in store.chunks_differing_from(prev) {
                    self.changed[c] = true;
                }
            }
        }
        let changed = &self.changed;
        let reader = Reader::<D> { store };
        let results: Vec<(usize, Vec<Wake>, Vec<Event>)> = self
            .buckets
            .par_iter_mut()
            .enumerate()
            .filter(|(i, b)| !b.watches.is_empty() && (changed[*i] || b.fresh || b.remote > 0))
            .map(|(i, bucket)| {
                let home = changed[i];
                bucket.fresh = false;
                let mut wakes = Vec::new();
                let mut events = Vec::new();
                let mut evaluated = 0;
                for w in &mut bucket.watches {
                    if !(home || w.fresh || w.remote.iter().any(|&c| changed[c as usize])) {
                        continue;
                    }
                    w.fresh = false;
                    evaluated += 1;
                    let mut fired = Fired::default();
                    w.node.eval(&reader, w.id, &mut fired, &mut events);
                    if fired.reason != 0 {
                        wakes.push(Wake {
                            subscriber: w.subscriber,
                            lane: w.lane,
                            reason: fired.reason,
                            source: fired.source.unwrap_or(0),
                            watch: w.id,
                        });
                    }
                }
                (evaluated, wakes, events)
            })
            .collect();
        let mut stats = WatchStats {
            watches: self.buckets.iter().map(|b| b.watches.len()).sum(),
            changed_chunks: self.changed.iter().filter(|&&c| c).count(),
            ..WatchStats::default()
        };
        for (evaluated, wakes, events) in results {
            stats.evaluated += evaluated;
            stats.wakes += wakes.len();
            for w in wakes {
                out.push_wake(w);
            }
            for e in events {
                out.push_event(e);
            }
        }
        self.stats = stats;
        self.prev = Some(store.snapshot());
    }

    /// The frame task body: evaluate against the domain's live store and
    /// write into its outbox.
    pub fn run(&mut self, state: &mut DomainState<D>) {
        let (store, out) = state.store_and_outbox();
        self.evaluate(store, out);
    }
}

/// A live watch as the main thread knows it.
#[derive(Clone, Debug)]
struct LiveWatch {
    generation: u32,
    alive: bool,
    /// The channel of a `ThresholdSet` watch.
    set_ch: Option<ChannelId>,
    /// Set entries: payload -> generation.
    entries: Vec<(u32, u32)>,
}

/// The main-thread side of a domain's watches: checks conditions (§6.3),
/// hands out [`WatchId`]s, queues registrations for the next frame, and
/// drops stale records from the outbox.
///
/// S1 binds this through `#[auxmacros::bind]`, roughly:
///
/// ```text
/// vg_watch_changed(domain, subscriber, lane, cell, mask)          -> watch id | runtime
/// vg_watch_threshold(domain, subscriber, lane, cell, ch, cmp, value, unit, hysteresis, edge)
/// vg_watch_band(domain, subscriber, lane, cell, ch, unit, levels_list, hysteresis)
/// vg_watch_difference(domain, subscriber, lane, a, b, ch, cmp, value, unit, hysteresis, abs)
/// vg_watch_set(domain, subscriber, lane, cell, ch)
/// vg_watch_set_add(domain, watch, payload, generation, cmp, value, unit, hysteresis)
/// vg_watch_set_remove(domain, watch, payload)
/// vg_watch_remove(domain, watch)
/// ```
///
/// Watch ids cross as `index * 16 + (generation & 15)`, like handles (§4).
pub struct WatchPort<D: Channels> {
    chans: Vec<ChannelInfo>,
    cells: u32,
    live: Vec<LiveWatch>,
    free: Vec<u32>,
    queued: Vec<WatchCmd>,
    _domain: std::marker::PhantomData<fn() -> D>,
}

impl<D: Channels> WatchPort<D> {
    #[must_use]
    pub fn new(layout: ChunkLayout) -> Self {
        Self {
            chans: crate::channel::channel_infos::<D>(),
            cells: layout.len(),
            live: Vec::new(),
            free: Vec::new(),
            queued: Vec::new(),
            _domain: std::marker::PhantomData,
        }
    }

    /// Checks `cond` without registering it.
    ///
    /// # Errors
    /// As [`validate`].
    pub fn check(&self, cond: &Cond) -> Result<(), WatchError> {
        validate(cond, &self.chans, Some(self.cells))
    }

    /// Registers a watch. It is evaluated from the next dispatched frame on.
    ///
    /// # Errors
    /// If the condition or subscriber is invalid (§6.3).
    pub fn watch(
        &mut self,
        subscriber: Subscriber,
        lane: Lane,
        cond: &Cond,
    ) -> Result<WatchId, WatchError> {
        if subscriber > MAX_SUBSCRIBER {
            return Err(WatchError::BadSubscriber(subscriber));
        }
        let node = compile(cond, &self.chans, Some(self.cells), 0)?;
        let set_ch = match node {
            Node::Set { ch, .. } => Some(ch),
            _ => None,
        };
        let id = match self.free.pop() {
            Some(index) => {
                let slot = &mut self.live[index as usize];
                slot.alive = true;
                slot.set_ch = set_ch;
                slot.entries.clear();
                WatchId {
                    index,
                    generation: slot.generation,
                }
            }
            None => {
                let index = u32::try_from(self.live.len()).expect("watch count fits u32");
                self.live.push(LiveWatch {
                    generation: 0,
                    alive: true,
                    set_ch,
                    entries: Vec::new(),
                });
                WatchId {
                    index,
                    generation: 0,
                }
            }
        };
        self.queued.push(WatchCmd::Add(Box::new(Watch {
            id,
            subscriber,
            lane,
            node,
            remote: Vec::new(),
            fresh: true,
        })));
        Ok(id)
    }

    fn live_mut(&mut self, id: WatchId) -> Result<&mut LiveWatch, WatchError> {
        self.live
            .get_mut(id.index as usize)
            .filter(|w| w.alive && w.generation == id.generation)
            .ok_or(WatchError::StaleWatch(id))
    }

    /// Whether `id` is registered.
    #[must_use]
    pub fn is_live(&self, id: WatchId) -> bool {
        self.live
            .get(id.index as usize)
            .is_some_and(|w| w.alive && w.generation == id.generation)
    }

    /// Removes a watch. Wakes it already produced are dropped at drain.
    ///
    /// # Errors
    /// If `id` is not live.
    pub fn unwatch(&mut self, id: WatchId) -> Result<(), WatchError> {
        let w = self.live_mut(id)?;
        w.alive = false;
        w.generation = w.generation.wrapping_add(1);
        w.entries.clear();
        self.free.push(id.index);
        self.queued.push(WatchCmd::Remove(id));
        Ok(())
    }

    /// Adds an entry to a `ThresholdSet` watch. Re-adding a payload with a
    /// new generation replaces the old entry.
    ///
    /// # Errors
    /// If `id` is not a live set, or the entry is invalid.
    pub fn add_entry(&mut self, id: WatchId, entry: SetEntry) -> Result<(), WatchError> {
        let set_ch = self.live_mut(id)?.set_ch.ok_or(WatchError::NotASet(id))?;
        let t = compile_thresh(
            &self.chans,
            set_ch,
            entry.cmp,
            entry.limit,
            entry.hysteresis,
            entry.edge,
        )?;
        let w = self.live_mut(id)?;
        if let Some(e) = w.entries.iter_mut().find(|e| e.0 == entry.payload) {
            e.1 = entry.generation;
            self.queued.push(WatchCmd::RemoveEntry(id, entry.payload));
        } else {
            w.entries.push((entry.payload, entry.generation));
        }
        self.queued.push(WatchCmd::AddEntry(id, entry, t));
        Ok(())
    }

    /// Removes a `ThresholdSet` entry.
    ///
    /// # Errors
    /// If `id` is not live or has no such payload.
    pub fn remove_entry(&mut self, id: WatchId, payload: u32) -> Result<(), WatchError> {
        let w = self.live_mut(id)?;
        let i = w
            .entries
            .iter()
            .position(|e| e.0 == payload)
            .ok_or(WatchError::StaleWatch(id))?;
        w.entries.swap_remove(i);
        self.queued.push(WatchCmd::RemoveEntry(id, payload));
        Ok(())
    }

    /// Drops wakes of removed watches and crossings of removed or
    /// superseded set entries (§6.4). Main thread, at drain.
    pub fn filter<V>(&self, out: &mut Outbox<V>) {
        out.wakes_mut()
            .retain(|w| w.watch == WatchId::NONE || self.is_live(w.watch));
        out.events_mut().retain(|e| {
            e.kind != EventKind::ThresholdCrossed
                || self.live.get(e.key as usize).is_some_and(|w| {
                    w.alive
                        && w.entries
                            .iter()
                            .any(|&(p, g)| p == e.extra && g == e.generation)
                })
        });
    }

    #[must_use]
    pub fn queued(&self) -> usize {
        self.queued.len()
    }

    /// Moves queued registrations into the worker-side state (the sim does
    /// this at each frame dispatch).
    pub fn dispatch(&mut self, state: &mut WatchState<D>) {
        state.enqueue(std::mem::take(&mut self.queued));
    }
}
