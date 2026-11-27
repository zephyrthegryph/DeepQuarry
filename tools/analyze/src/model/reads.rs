//! Read receipts: what a judgement read of the model, under the front end's stable identities, so a kept result can be reused while
//! the next revision's delta names none of it (doc/rewrite/proposals/lean_unified.md, 2a, "Read recording").
//!
//! A judgement runs under [`recording`]; every accessor of the view that answers from another declaration, body, type, parent chain or
//! override chain notes one [`Read`] ([`note`]). With no recording open on the thread a note is one thread-local check. The receipt is
//! the set of reads; [`Receipt::holds`] says whether a result made under it is still current after a [`dm_tree::frontend::FrontendDelta`].

use std::cell::RefCell;
use std::collections::BTreeSet;
use std::sync::Arc;

use dm_tree::frontend::{Change, DeclarationKey, FrontendDelta};
use dm_tree::MemberKind;

/// One thing a judgement read.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Read {
    /// A declaration's content: a var's declared type, flags or initializer, a proc's header (parameters, return type), a type's block.
    Declaration(DeclarationKey),
    /// A proc's body (its statements).
    Body(DeclarationKey),
    /// Where a declaration is (its file and line): changes when it moves, too.
    Site(DeclarationKey),
    /// A lookup by name from a type through its parents: `var_declaration`, `proc`, `proc_definitions`, a member listing by name. Its
    /// answer, a miss included, depends on every declaration of `name` of that kind on the type and its ancestors, and on the parent
    /// chain; recorded whether it found something or not.
    Lookup { owner: Arc<str>, name: Arc<str>, kind: LookupKind },
    /// The parent chain of a type (`parent()`, `is_subtype_of`).
    Parents(Arc<str>),
    /// An enumeration of the whole model (every type, every member of a type): any added or removed declaration can change it.
    Everything,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum LookupKind {
    Var,
    Proc,
}

/// What one judgement read.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Receipt {
    pub reads: BTreeSet<Read>,
}

thread_local! {
    static OPEN: RefCell<Vec<BTreeSet<Read>>> = const { RefCell::new(Vec::new()) };
}

/// Runs `judge` with a receipt open on this thread; returns its result and what it read. Recordings nest (an inner judgement's reads are
/// the outer one's too). Work `judge` hands to other threads is not recorded: a recorded judgement reads on its own thread.
pub fn recording<R>(judge: impl FnOnce() -> R) -> (R, Receipt) {
    OPEN.with(|o| o.borrow_mut().push(BTreeSet::new()));
    let r = judge();
    let reads = OPEN.with(|o| o.borrow_mut().pop()).unwrap_or_default();
    OPEN.with(|o| {
        if let Some(outer) = o.borrow_mut().last_mut() {
            outer.extend(reads.iter().cloned());
        }
    });
    (r, Receipt { reads })
}

/// Whether a recording is open on this thread (the accessors build a [`Read`] only then).
#[inline]
pub fn active() -> bool {
    OPEN.with(|o| !o.borrow().is_empty())
}

/// Notes `read` in the innermost open recording; `read` is built only when one is open.
#[inline]
pub fn note(read: impl FnOnce() -> Read) {
    if !active() {
        return;
    }
    let r = read();
    OPEN.with(|o| {
        if let Some(top) = o.borrow_mut().last_mut() {
            top.insert(r);
        }
    });
}

impl Receipt {
    /// Whether a result made under this receipt still holds after `delta` (the change from the revision it was made on to the current
    /// one): none of its declarations or bodies changed, none of its sites moved, no declaration of a looked-up name appeared, went or
    /// changed on a type, and no type declaration changed (a parent chain or the type set) where a lookup, a parent chain or an
    /// enumeration could see it.
    pub fn holds(&self, delta: &FrontendDelta) -> bool {
        if delta.is_empty() {
            return true;
        }
        let structural = |c: Change| c != Change::Moved;
        let type_changed = delta.declarations.iter().any(|(k, c)| k.member.is_none() && structural(*c));
        let membership_changed = delta.declarations.iter().any(|(_, c)| matches!(c, Change::Added | Change::Removed));
        for read in &self.reads {
            let ok = match read {
                Read::Declaration(key) => !delta.declarations.iter().any(|(k, c)| k == key && structural(*c)),
                Read::Body(key) => !delta.bodies.iter().any(|(k, c)| k == key && structural(*c)),
                Read::Site(key) => !delta.declarations.iter().any(|(k, _)| k == key) && !delta.bodies.iter().any(|(k, _)| k == key),
                Read::Lookup { name, kind, .. } => {
                    !type_changed
                        && !delta.declarations.iter().any(|(k, c)| {
                            structural(*c)
                                && k.member.as_ref().is_some_and(|(n, mk)| n == name && matches!((kind, mk), (LookupKind::Var, MemberKind::Var) | (LookupKind::Proc, MemberKind::Proc | MemberKind::Verb)))
                        })
                }
                Read::Parents(_) => !type_changed,
                Read::Everything => !membership_changed && !type_changed,
            };
            if !ok {
                return false;
            }
        }
        true
    }
}
