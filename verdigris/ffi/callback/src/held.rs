//! Owned Byondapi values: the one place a reference the API creates is released.
//!
//! Every reference a Byondapi call hands native code (a list element, a var read, a proc result, a created list) is
//! persistent since BYOND 516.1674 and stays pinned until `ByondValue_DecRef()`. `byondapi-rs`'s `ByondValue` is `Copy`
//! with no `Drop`, so forgetting the release silently pins the DM object forever: a map atom read out of a turf's
//! contents kept one reference a `new` one did not and showed up as a GC LEAK. [`Held`] makes the release automatic.
//!
//! Rules (checked by `tools/ci/check_byond_refs.sh`, wired into `check_ratchets.sh`):
//! - Outside this module the API's reading methods (`read_var`, `read_var_id`, `get_list_values`, `get_list`,
//!   `read_list_index`, `call`, `call_id`, `call_global*`, `read_list`, ...) are not called. Use the [`HeldRead`]
//!   methods, which return a [`Held`] / [`HeldList`] that releases on drop.
//! - Arguments a DM caller passes to a bind are the caller's: they are plain `ByondValue`s and not released here.
//! - A value Rust must keep past the current call, or hand back to DM as a return value, leaves through
//!   [`Held::leak`]; whoever receives the raw value then owns the release (a return value goes to DM).
//!
//! Numbers, null and turfs are not refcounted ([`needs_release`]); releasing a [`Held`] of those kinds does nothing.

use std::convert::TryInto;
use std::ops::{Deref, DerefMut};

use byondapi::prelude::*;
use byondapi::value::types::ValueType;

#[cfg(test)]
thread_local! {
    /// Releases the unit tests observed (the real `ByondValue_DecRef` needs a running BYOND).
    static RELEASED: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// Whether a value of this raw type carries a reference that must be released. Null, numbers and turfs (which BYOND
/// does not refcount) do not; every other kind (objects, mobs, datums, lists, strings, clients, images, ...) does.
#[must_use]
pub fn needs_release(raw_type: u8) -> bool {
    raw_type != ValueType::Null as u8
        && raw_type != ValueType::Number as u8
        && raw_type != ValueType::Turf as u8
}

fn release(value: &mut ByondValue) {
    #[cfg(test)]
    RELEASED.with(|c| c.set(c.get() + 1));
    #[cfg(not(test))]
    value.decrement_ref();
    #[cfg(test)]
    let _ = value;
}

/// A value the Byondapi created for us, released when it goes out of scope. Not `Copy`, not `Clone`: one owner, one
/// release. Reads that do not return references (`get_number`, `get_type`, `read_number_id`, ...) go through `Deref`.
pub struct Held(ByondValue);

impl Held {
    /// Takes ownership of a value the API just returned. Call it only on a value fresh from a Byondapi call (the
    /// [`HeldRead`] methods do), never on an argument DM passed in.
    #[must_use]
    pub fn adopt(value: ByondValue) -> Held {
        Held(value)
    }

    /// A newly created DM list, owned (it is released on drop unless it leaves through [`Held::leak`]).
    pub fn new_list() -> Result<Held, byondapi::Error> {
        ByondValue::new_list().map(Held)
    }

    /// A newly created DM string, owned (released on drop unless it leaves through [`Held::leak`]). Strings are
    /// refcounted references like any object.
    pub fn new_str<T: Into<Vec<u8>>>(text: T) -> Result<Held, byondapi::Error> {
        ByondValue::new_str(text).map(Held)
    }

    /// Gives up ownership without releasing. The caller (or DM, for a bind's return value) now owns the reference.
    #[must_use]
    pub fn leak(self) -> ByondValue {
        let value = self.0;
        std::mem::forget(self);
        value
    }

    /// The raw value, to pass as an argument to another API call. It is borrowed: it is invalid after this `Held` drops.
    #[must_use]
    pub fn raw(&self) -> ByondValue {
        self.0
    }
}

impl Deref for Held {
    type Target = ByondValue;
    fn deref(&self) -> &ByondValue {
        &self.0
    }
}

/// For writes through the reference (`write_var_id`); never assign a different value through it.
impl DerefMut for Held {
    fn deref_mut(&mut self) -> &mut ByondValue {
        &mut self.0
    }
}

impl Drop for Held {
    fn drop(&mut self) {
        if needs_release(self.0.0.type_) {
            release(&mut self.0);
        }
    }
}

impl std::fmt::Debug for Held {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Held(type {:#04x})", self.0.0.type_)
    }
}

/// The values of a DM list, each owned by the list. It derefs to `&[ByondValue]` so the values read like a slice (they are
/// borrowed: invalid once the list drops); the list releases every one when it drops. Consuming it yields owned [`Held`]s.
#[derive(Debug, Default)]
pub struct HeldList(Vec<ByondValue>);

impl HeldList {
    fn adopt_all(values: Vec<ByondValue>) -> HeldList {
        HeldList(values)
    }
}

impl Deref for HeldList {
    type Target = [ByondValue];
    fn deref(&self) -> &[ByondValue] {
        &self.0
    }
}

impl Drop for HeldList {
    fn drop(&mut self) {
        for value in &mut self.0 {
            if needs_release(value.0.type_) {
                release(value);
            }
        }
    }
}

/// The owned values of a consumed [`HeldList`]; any left unvisited when it drops are released.
pub struct HeldIntoIter(std::vec::IntoIter<ByondValue>);

impl Iterator for HeldIntoIter {
    type Item = Held;
    fn next(&mut self) -> Option<Held> {
        self.0.next().map(Held)
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        self.0.size_hint()
    }
}

impl Drop for HeldIntoIter {
    fn drop(&mut self) {
        for value in &mut self.0 {
            drop(Held(value));
        }
    }
}

impl IntoIterator for HeldList {
    type Item = Held;
    type IntoIter = HeldIntoIter;
    fn into_iter(mut self) -> HeldIntoIter {
        HeldIntoIter(std::mem::take(&mut self.0).into_iter())
    }
}

impl<'a> IntoIterator for &'a HeldList {
    type Item = &'a ByondValue;
    type IntoIter = std::slice::Iter<'a, ByondValue>;
    fn into_iter(self) -> Self::IntoIter {
        self.0.iter()
    }
}

/// A new DM list holding `values`, handed to DM as a bind's return value. The reference the API created for the list
/// is not released here: it goes back to DM with the return, which owns it from there. Values that are themselves
/// owned lists must be released by the caller after this call (the list holds its own reference to each).
pub fn hand_list(values: &[ByondValue]) -> Result<ByondValue, byondapi::Error> {
    let list = Held::new_list()?;
    list.write_list(values)?;
    Ok(list.leak())
}

/// A new DM list holding owned `values`, handed to DM as a bind's return value. The list takes its own reference to
/// each element, so ours are released once the list is written (on success or failure): a string or object built in
/// Rust and placed in a returned list is not pinned forever.
pub fn hand_owned_list(values: Vec<Held>) -> Result<ByondValue, byondapi::Error> {
    let raws: Vec<ByondValue> = values.iter().map(Held::raw).collect();
    let result = hand_list(&raws);
    release_all(values);
    result
}

/// Releases each owned element (split out so the release count is testable without BYOND).
fn release_all(values: Vec<Held>) {
    drop(values);
}

/// Reads that return references, handing each one back owned. Implemented for every `ByondValue`, so it also applies
/// through a [`Held`].
pub trait HeldRead {
    /// `get_list_values()`: the list's values (for an assoc list the keys), each released on drop.
    fn held_list(&self) -> Result<HeldList, byondapi::Error>;
    /// `values()`: the list's numbered positions walked one by one (a null entry is a value, not the end), each released on drop.
    fn held_values(&self) -> Result<HeldList, byondapi::Error>;
    /// `iter()`: `(key, value)` per entry (`value` is null in a list without associations), each side released on drop.
    fn held_pairs(&self) -> Result<Vec<(Held, Held)>, byondapi::Error>;
    /// `read_var_id()`.
    fn held_var_id(&self, name: u32) -> Result<Held, byondapi::Error>;
    /// `read_var()`.
    fn held_var(&self, name: &str) -> Result<Held, byondapi::Error>;
    /// `read_list_index()` (1-based DM index or an assoc key).
    fn held_index<I: TryInto<ByondValue>>(&self, index: I) -> Result<Held, byondapi::Error>;
    /// `call_id()`: the proc's result.
    fn held_call_id(&self, name: u32, args: &[ByondValue]) -> Result<Held, byondapi::Error>;
    /// `call()`: the proc's result.
    fn held_call(&self, name: &str, args: &[ByondValue]) -> Result<Held, byondapi::Error>;
}

impl HeldRead for ByondValue {
    fn held_list(&self) -> Result<HeldList, byondapi::Error> {
        self.get_list_values().map(HeldList::adopt_all)
    }
    fn held_values(&self) -> Result<HeldList, byondapi::Error> {
        self.values().map(|it| HeldList::adopt_all(it.collect()))
    }
    fn held_pairs(&self) -> Result<Vec<(Held, Held)>, byondapi::Error> {
        self.iter()
            .map(|it| it.map(|(k, v)| (Held(k), Held(v))).collect())
    }
    fn held_var_id(&self, name: u32) -> Result<Held, byondapi::Error> {
        self.read_var_id(name).map(Held)
    }
    fn held_var(&self, name: &str) -> Result<Held, byondapi::Error> {
        self.read_var(name).map(Held)
    }
    fn held_index<I: TryInto<ByondValue>>(&self, index: I) -> Result<Held, byondapi::Error> {
        self.read_list_index(index).map(Held)
    }
    fn held_call_id(&self, name: u32, args: &[ByondValue]) -> Result<Held, byondapi::Error> {
        self.call_id(name, args).map(Held)
    }
    fn held_call(&self, name: &str, args: &[ByondValue]) -> Result<Held, byondapi::Error> {
        self.call(name, args).map(Held)
    }
}

/// `call_global_id()`: a global proc's result, owned.
pub fn held_call_global_id(name: u32, args: &[ByondValue]) -> Result<Held, byondapi::Error> {
    byondapi::global_call::call_global_id(name, args).map(Held)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn released() -> usize {
        RELEASED.with(std::cell::Cell::get)
    }

    #[test]
    fn refcounted_kinds_release_and_the_rest_do_not() {
        for t in [
            ValueType::Obj,
            ValueType::Mob,
            ValueType::Datum,
            ValueType::List,
            ValueType::TurfContents,
            ValueType::String,
            ValueType::Client,
        ] {
            assert!(needs_release(t as u8), "{:?} is refcounted", t);
        }
        for t in [ValueType::Null, ValueType::Number, ValueType::Turf] {
            assert!(!needs_release(t as u8), "{:?} is not refcounted", t);
        }
    }

    #[test]
    fn drop_releases_an_object_once() {
        let before = released();
        {
            let _held = Held::adopt(ByondValue::new_ref(ValueType::Obj, 7));
        }
        assert_eq!(released() - before, 1);
    }

    #[test]
    fn drop_skips_numbers_null_and_turfs() {
        let before = released();
        drop(Held::adopt(ByondValue::new_num(3.0)));
        drop(Held::adopt(ByondValue::null()));
        drop(Held::adopt(ByondValue::new_ref(ValueType::Turf, 9)));
        assert_eq!(released(), before);
    }

    #[test]
    fn leak_hands_the_reference_on_unreleased() {
        let before = released();
        let raw = Held::adopt(ByondValue::new_ref(ValueType::Datum, 11)).leak();
        assert_eq!(released(), before);
        assert_eq!(raw.0.type_, ValueType::Datum as u8);
    }

    #[test]
    fn a_list_releases_every_element_even_when_not_consumed() {
        let before = released();
        let list = HeldList::adopt_all(vec![
            ByondValue::new_ref(ValueType::Obj, 1),
            ByondValue::new_num(2.0),
            ByondValue::new_ref(ValueType::Mob, 3),
        ]);
        assert_eq!(list.len(), 3);
        drop(list);
        assert_eq!(released() - before, 2);
    }

    #[test]
    fn consuming_a_list_releases_each_element_once() {
        let before = released();
        let list = HeldList::adopt_all(vec![
            ByondValue::new_ref(ValueType::Obj, 1),
            ByondValue::new_ref(ValueType::Obj, 2),
        ]);
        let mut seen = 0;
        for held in list {
            assert!(held.raw().0.type_ == ValueType::Obj as u8);
            seen += 1;
        }
        assert_eq!(seen, 2);
        assert_eq!(released() - before, 2);
    }

    #[test]
    fn owned_list_elements_release_after_the_hand_off() {
        let before = released();
        let values = vec![
            Held::adopt(ByondValue::new_ref(ValueType::String, 1)),
            Held::adopt(ByondValue::new_num(2.0)),
            Held::adopt(ByondValue::new_ref(ValueType::String, 3)),
        ];
        release_all(values);
        assert_eq!(released() - before, 2);
    }

    #[test]
    fn an_abandoned_consuming_walk_still_releases_the_rest() {
        let before = released();
        let list = HeldList::adopt_all(vec![
            ByondValue::new_ref(ValueType::Obj, 1),
            ByondValue::new_ref(ValueType::Obj, 2),
            ByondValue::new_ref(ValueType::Obj, 3),
        ]);
        let mut walk = list.into_iter();
        let first = walk.next().expect("first element");
        drop(first);
        assert_eq!(released() - before, 1);
        drop(walk);
        assert_eq!(released() - before, 3);
    }
}
