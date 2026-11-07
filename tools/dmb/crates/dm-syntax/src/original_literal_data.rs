//! Source-free Original scalar/static VALUE owner. No source/model/body cache.
use crate::{OriginalTokenValue, SettingAdmission, SettingRootLease};
use std::{fmt, io, mem::{size_of, ManuallyDrop}, ops::Deref, ptr::NonNull, sync::Arc};

/// Actual producer-issued lexical form, distinct from the neutral String value.
/// Unknown is deliberately unissued; spelling and value never reconstruct it.
#[repr(u8)]
#[derive(Clone,Copy,Debug,Default,Eq,PartialEq,Hash)]
pub enum OriginalStringMode{#[default]Unknown=0,Normal=1,Raw=2,Generated=3}
#[repr(u8)]
#[derive(Clone, Copy)]
enum LiteralKind { Int, Float, String, Resource, InterpBegin, InterpPart, InterpEnd }

struct LiteralValue {
    kind: LiteralKind,
    scalar_bits: u32,
    string_mode:OriginalStringMode,
    // Exact UTF-8 subview: prefix bytes and (suffix bytes + 1).
    // Zero in the second byte selects the owned (or empty) typed text.
    value_in_raw: [u8; 2],
    raw: String,
    text: Box<str>,
}

/// Borrow the exact initialized raw spelling and its allocation capacity.
#[derive(Clone, Copy)]
pub struct LiteralRawStorage<'a> {
    text: &'a str,
    capacity: usize,
}

impl<'a> LiteralRawStorage<'a> {
    pub(crate) fn from_string(raw: &'a String) -> Self {
        Self { text: raw, capacity: raw.capacity() }
    }

    pub fn as_str(self) -> &'a str { self.text }
    pub fn as_ptr(self) -> *const u8 { self.text.as_ptr() }
    pub fn capacity(self) -> usize { self.capacity }
}

/// The exact same Global String allocation plus closed batch geometry.
#[repr(C)]
struct PackedBatchValue {
    pointer: NonNull<u8>,
    meta: u64,
}
#[cfg(target_pointer_width = "64")]
const _: () = assert!(size_of::<PackedBatchValue>() == 16);

// SAFETY: identical exclusive allocation ownership to String. Shared borrows
// expose immutable UTF-8 only, and last-owner destruction is thread-safe.
unsafe impl Send for PackedBatchValue {}
unsafe impl Sync for PackedBatchValue {}

struct BatchValues {
    rows: Vec<PackedBatchValue>,
    cooked: Box<[Box<str>]>,
}

struct LiteralValueView<'a> {
    kind: LiteralKind,
    scalar_bits: u32,
    value_in_raw: [u8; 2],
    raw: LiteralRawStorage<'a>,
    text: &'a str,
}

impl PackedBatchValue {
    const LEN_SHIFT: u32 = 32;
    const CAPACITY_SHIFT: u32 = 43;
    const KIND_SHIFT: u32 = 54;
    const MODE_SHIFT: u32 = 57;
    const WITHDRAWN: u64 = 1 << 59;
    const RAW_PROJECTED: u64 = 1 << 60;
    const RAW_MASK: u64 = (1 << 11) - 1;

    fn raw_geometry(len: usize, capacity: usize) -> Option<(u32, u32)> {
        if len > capacity || capacity > MAX_ROW_TEXT_BYTES {
            return None;
        }
        Some((len as u32, capacity as u32))
    }

    fn adopt(value: LiteralValue, cooked: &mut Vec<Box<str>>) -> Self {
        let LiteralValue { kind, scalar_bits, string_mode, value_in_raw, raw, text } = value;
        let (len, capacity) = Self::raw_geometry(raw.len(), raw.capacity())
            .expect("checked exact raw geometry before moving a batch row");
        let word = if matches!(kind, LiteralKind::Int | LiteralKind::Float) {
            debug_assert!(text.is_empty());
            debug_assert_eq!(value_in_raw, [0, 0]);
            scalar_bits
        } else {
            let slot = if text.is_empty() {
                0
            } else {
                debug_assert_eq!(value_in_raw, [0, 0]);
                assert!(cooked.len() < cooked.capacity(), "funded exact cooked-text roster");
                cooked.push(text);
                u8::try_from(cooked.len()).expect("closed cooked ordinal")
            };
            u32::from_le_bytes([value_in_raw[0], value_in_raw[1], slot, 0])
        };
        let meta = u64::from(word) | (u64::from(len) << Self::LEN_SHIFT)
            | (u64::from(capacity) << Self::CAPACITY_SHIFT)
            | ((kind as u64) << Self::KIND_SHIFT) | ((string_mode as u64) << Self::MODE_SHIFT);
        let mut raw = ManuallyDrop::new(raw);
        let pointer = NonNull::new(raw.as_mut_ptr()).expect("String backing is non-null");
        Self { pointer, meta }
    }

    fn kind(&self) -> LiteralKind {
        match (self.meta >> Self::KIND_SHIFT) & 7 {
            0 => LiteralKind::Int,
            1 => LiteralKind::Float,
            2 => LiteralKind::String,
            3 => LiteralKind::Resource,
            4 => LiteralKind::InterpBegin,
            5 => LiteralKind::InterpPart,
            6 => LiteralKind::InterpEnd,
            _ => unreachable!("issued literal kind"),
        }
    }

    fn string_mode(&self) -> OriginalStringMode {
        match (self.meta >> Self::MODE_SHIFT) & 3 {
            0 => OriginalStringMode::Unknown,
            1 => OriginalStringMode::Normal,
            2 => OriginalStringMode::Raw,
            3 => OriginalStringMode::Generated,
            _ => unreachable!("issued literal string mode"),
        }
    }

    fn scalar_or_text(&self) -> u32 {
        let word = self.meta as u32;
        if matches!(self.kind(), LiteralKind::Int | LiteralKind::Float) { word }
        else { u32::from(word.to_le_bytes()[2]) }
    }

    fn value_in_raw(&self) -> [u8; 2] {
        if matches!(self.kind(), LiteralKind::Int | LiteralKind::Float) {
            return [0, 0];
        }
        let [prefix, suffix, _, _] = (self.meta as u32).to_le_bytes();
        [prefix, suffix]
    }

    fn raw_len(&self) -> usize { ((self.meta >> Self::LEN_SHIFT) & Self::RAW_MASK) as usize }
    fn raw_capacity(&self) -> usize { ((self.meta >> Self::CAPACITY_SHIFT) & Self::RAW_MASK) as usize }
    fn is_withdrawn(&self) -> bool { self.meta & Self::WITHDRAWN != 0 }

    fn has_source_raw(&self) -> bool { self.meta & Self::RAW_PROJECTED != 0 }
    fn raw_is_gone(&self) -> bool { self.is_withdrawn() || self.has_source_raw() }

    fn raw_view(&self) -> LiteralRawStorage<'_> {
        assert!(!self.raw_is_gone(), "withdrawn packed spelling has no full view");
        // SAFETY: exclusive String ownership is still live. The exact
        // initialized UTF-8 prefix and allocation geometry never change.
        let bytes = unsafe { std::slice::from_raw_parts(self.pointer.as_ptr(), self.raw_len()) };
        let text = unsafe { std::str::from_utf8_unchecked(bytes) };
        LiteralRawStorage { text, capacity: self.raw_capacity() }
    }

    fn withdraw_raw(&mut self) { self.release_raw(Self::WITHDRAWN); }

    fn release_raw(&mut self, mode: u64) {
        if self.raw_is_gone() { return; }
        self.meta |= mode;
        // SAFETY: the allocation is uniquely adopted. Mark withdrawn before
        // rebuilding the one matching Global String, so no second free occurs.
        drop(unsafe { String::from_raw_parts(self.pointer.as_ptr(), self.raw_len(), self.raw_capacity()) });
    }

    fn source_raw_candidate(&self) -> Option<usize> {
        if self.raw_is_gone() || self.value_in_raw()[1] != 0 || self.raw_capacity() == 0 { return None; }
        match self.kind() {
            LiteralKind::String | LiteralKind::Resource if self.scalar_or_text() != 0 => Some(self.raw_capacity()),
            LiteralKind::InterpBegin | LiteralKind::InterpPart | LiteralKind::InterpEnd => Some(self.raw_capacity()),
            _ => None,
        }
    }

    fn cooked_value<'a>(&self, cooked: &'a [Box<str>]) -> OriginalTokenValue<&'a str> {
        assert!(self.has_source_raw() && self.value_in_raw()[1] == 0);
        let slot = self.scalar_or_text() as usize;
        let text = if slot == 0 { "" } else { cooked[slot - 1].as_ref() };
        match self.kind() {
            LiteralKind::String => OriginalTokenValue::String(text),
            LiteralKind::Resource => OriginalTokenValue::Resource(text),
            LiteralKind::InterpBegin => OriginalTokenValue::InterpBegin(text),
            LiteralKind::InterpPart => OriginalTokenValue::InterpPart(text),
            LiteralKind::InterpEnd => OriginalTokenValue::InterpEnd(text),
            _ => unreachable!("source raw retains a cooked packed value"),
        }
    }

    fn view<'a>(&'a self, cooked: &'a [Box<str>]) -> LiteralValueView<'a> {
        let kind = self.kind();
        let scalar_or_text = self.scalar_or_text();
        let text = if matches!(kind, LiteralKind::Int | LiteralKind::Float) || scalar_or_text == 0 {
            ""
        } else {
            cooked[scalar_or_text as usize - 1].as_ref()
        };
        LiteralValueView {
            kind, scalar_bits: scalar_or_text,
            value_in_raw: self.value_in_raw(), raw: self.raw_view(), text,
        }
    }
}

impl Drop for PackedBatchValue {
    fn drop(&mut self) { self.withdraw_raw(); }
}

enum LiteralStorage {
    Single(LiteralValue),
    Page(BatchValues),
    RawDetached(Box<DetachedRaw>),
    Projected(Box<crate::original_literal_projection::DetachedProjectedLiteral>),
}

struct DetachedRaw {
    raw: Box<str>,
    owner: OriginalLiteralOwner,
    ordinal: usize,
}

struct Payload {
    storage: LiteralStorage,
    // LAST: the exact String/Box buffers and any row allocation die before
    // the original counter is credited.
    credit: SettingRootLease,
}
/// No public Arc/Weak escape: final Arc::into_inner deallocates its control
/// before dropping payload buffers and then its SAME resource-only credit.
// A unique backing needs ordinal 0. The private producer pool can reuse
// a backing but mints a different nonzero ordinal for each occurrence.
pub struct OriginalLiteralData(Option<Arc<Payload>>, usize);

/// Borrow the actual issued payload and occurrence ordinal. A view owns
/// neither storage nor source authority, and has no independent constructor.
#[derive(Clone, Copy)]
pub struct OriginalLiteralRef<'a> {
    owner: Option<&'a Arc<Payload>>,
    ordinal: usize,
    projected: Option<crate::original_literal_projection::ProjectedLiteralRef<'a>>,
    source_raw: Option<LiteralRawStorage<'a>>,
}

/// One actual owner retained by a compact fact page. The credit follows the
/// same Arc and the last owner frees its control before its leased payload.
pub(crate) struct OriginalLiteralOwner(Option<Arc<Payload>>);
impl OriginalLiteralOwner {
    pub(crate) fn at(&self, ordinal: usize) -> OriginalLiteralRef<'_> {
        let owner = self.0.as_ref().expect("live bank owner");
        if let LiteralStorage::Page(page) = &owner.storage {
            assert!(!page.rows[ordinal].is_withdrawn(), "packed bank code must point at live spelling");
        }
        OriginalLiteralRef { owner: Some(owner), ordinal, projected: None, source_raw: None }
    }

    /// Retire the unique singleton after its projected descriptor is funded.
    /// Its sole compact code changes immediately after this returns.
    pub(crate) fn retire_projected_single_using(&mut self, ordinal: usize, a: &SettingAdmission<'_>) -> io::Result<usize> {
        let owner = self.0.as_ref().ok_or(io::ErrorKind::InvalidData)?;
        if !a.matches_lease_domain(&owner.credit) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        let Some((_, released)) = self.at(ordinal).projection_candidate() else {
            return Err(io::ErrorKind::InvalidData.into());
        };
        a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
        drop_owner(&mut self.0);
        Ok(released)
    }

    pub(crate) fn withdraw_source_raw_using(&mut self, mask: u32, a: &SettingAdmission<'_>) -> io::Result<usize> {
        let owner = self.0.as_mut().and_then(Arc::get_mut).ok_or(io::ErrorKind::InvalidData)?;
        if !a.matches_lease_domain(&owner.credit) { return Err(io::ErrorKind::InvalidInput.into()); }
        let LiteralStorage::Page(page) = &mut owner.storage else { return Err(io::ErrorKind::InvalidData.into()); };
        let mut bytes = 0;
        for at in 0..PAGE_ROWS {
            if mask & (1 << at) == 0 { continue; }
            let row = page.rows.get(at).ok_or(io::ErrorKind::InvalidData)?;
            bytes += row.source_raw_candidate().ok_or(io::ErrorKind::InvalidData)?;
        }
        let credit = a.split(&mut owner.credit, bytes)?;
        for (at, row) in page.rows.iter_mut().enumerate() {
            if mask & (1 << at) != 0 { row.release_raw(PackedBatchValue::RAW_PROJECTED); }
        }
        drop(credit);
        Ok(bytes)
    }

    /// Withdraw only after the caller has funded every replacement descriptor.
    /// No second handle or Weak can exist while this Arc is exclusively borrowed.
    pub(crate) fn withdraw_packed_using(
        &mut self,
        mask: u32,
        retire_owner: bool,
        a: &SettingAdmission<'_>,
    ) -> io::Result<usize> {
        let owner = self.0.as_mut().and_then(Arc::get_mut).ok_or(io::ErrorKind::InvalidData)?;
        if !a.matches_lease_domain(&owner.credit) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        let LiteralStorage::Page(page) = &mut owner.storage else {
            return Err(io::ErrorKind::InvalidData.into());
        };
        let mut raw_bytes = 0;
        for ordinal in 0..PAGE_ROWS {
            if mask & (1 << ordinal) == 0 {
                continue;
            }
            let row = page.rows.get(ordinal).ok_or(io::ErrorKind::InvalidData)?;
            if row.raw_is_gone() {
                return Err(io::ErrorKind::InvalidData.into());
            }
            raw_bytes += row.raw_capacity();
        }
        if retire_owner {
            let complete = u32::MAX >> (PAGE_ROWS - page.rows.len());
            if mask != complete {
                return Err(io::ErrorKind::InvalidData.into());
            }
            a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
            let released = owner.credit.bytes();
            drop_owner(&mut self.0);
            return Ok(released);
        }
        let credit = a.split(&mut owner.credit, raw_bytes)?;
        for (ordinal, row) in page.rows.iter_mut().enumerate() {
            if mask & (1 << ordinal) != 0 {
                row.withdraw_raw();
            }
        }
        drop(credit);
        Ok(raw_bytes)
    }
}
fn drop_owner(owner: &mut Option<Arc<Payload>>) {
    if let Some(owner) = owner.take() {
        if let Some(payload) = Arc::into_inner(owner) { drop(payload); }
    }
}
impl Drop for OriginalLiteralOwner {
    fn drop(&mut self) { drop_owner(&mut self.0); }
}
impl<'a> From<&'a OriginalLiteralData> for OriginalLiteralRef<'a> {
    fn from(data: &'a OriginalLiteralData) -> Self { data.as_view() }
}
impl Clone for OriginalLiteralData {
    fn clone(&self)->Self { Self(Some(Arc::clone(self.0.as_ref().expect("live literal DATA"))),self.1) }
}
impl Drop for OriginalLiteralData {
    fn drop(&mut self) {
        drop_owner(&mut self.0);
    }
}
impl fmt::Debug for OriginalLiteralData {
    fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result {
        f.debug_struct("OriginalLiteralData").field("raw",&self.raw()).field("kind",&self.kind()).finish()
    }
}
impl Deref for OriginalLiteralData {
    type Target=str;
    fn deref(&self)->&str { self.raw() }
}
fn fail(a:&SettingAdmission<'_>,e:io::Error)->io::Error {
    let kind=e.kind(); a.record_operational_error(e); kind.into()
}
fn bytes(a:&SettingAdmission<'_>,n:Option<usize>)->io::Result<usize> {
    n.ok_or_else(||fail(a,io::Error::new(io::ErrorKind::OutOfMemory,"Original literal DATA size overflow")))
}
fn copy_value_text(s:&str,a:&SettingAdmission<'_>,credit:&mut SettingRootLease)->io::Result<Box<str>> {
    a.checkpoint()?;
    if s.is_empty(){return Ok(Box::default())}
    let layout=std::alloc::Layout::array::<u8>(s.len()).map_err(|e|fail(a,io::Error::new(io::ErrorKind::OutOfMemory,e)))?;
    a.grow(credit,s.len())?;
    let pointer=std::ptr::NonNull::new(unsafe{std::alloc::alloc(layout)}).ok_or_else(||fail(a,io::ErrorKind::OutOfMemory.into()))?;
    // SAFETY: Global owns exactly s.len() bytes. Copying the entire &str
    // initializes the allocation with valid UTF-8 before Box takes ownership.
    // Box<str> drops with the same length-derived Global layout.
    let text = unsafe {
        std::ptr::copy_nonoverlapping(s.as_ptr(), pointer.as_ptr(), s.len());
        let raw = std::ptr::slice_from_raw_parts_mut(pointer.as_ptr(), s.len());
        Box::from_raw(raw as *mut str)
    };
    a.checkpoint()?;
    Ok(text)
}

fn store_issued_value(s: &str, pending: &mut LiteralValue, credit: &mut SettingRootLease, a: &SettingAdmission<'_>) -> io::Result<Box<str>> {
    // Bounded byte comparison only. The caller has already issued the VALUE
    // and the lossless spelling independently; no quote/escape rule is used.
    // Template segment kind, lexical mode, and occurrence remain separate.
    const MAX_PREFIX: usize = u8::MAX as usize;
    const MAX_SUFFIX: usize = (u8::MAX - 1) as usize;
    let slack = pending.raw.len().checked_sub(s.len())
        .filter(|slack| *slack <= MAX_PREFIX + MAX_SUFFIX && !s.is_empty());
    if let Some(slack) = slack {
        a.checkpoint()?;
        let mut first = slack.saturating_sub(MAX_SUFFIX);
        // An exact UTF-8 match cannot start inside a scalar. Find the first
        // encodable boundary before running the one bounded-slack search.
        while !pending.raw.is_char_boundary(first) {
            first += 1;
        }
        if let Some(start) = pending.raw[first..].find(s).map(|start| first + start)
            .filter(|start| *start <= MAX_PREFIX)
        {
            let suffix = slack - start;
            pending.value_in_raw = [start as u8, (suffix + 1) as u8];
            return Ok(Box::default());
        }
    }
    copy_value_text(s, a, credit)
}

impl OriginalLiteralData {
    fn owner(&self) -> &Payload { self.0.as_deref().expect("live literal DATA") }
    #[cfg(test)]
    fn payload(&self) -> LiteralValueView<'_> { self.as_view().payload() }

    pub fn as_view(&self) -> OriginalLiteralRef<'_> {
        let owner = self.0.as_ref().expect("live literal DATA");
        if let LiteralStorage::RawDetached(detached) = &owner.storage {
            return detached.owner.at(detached.ordinal).with_source_raw(Some(&detached.raw), detached.raw.len());
        }
        OriginalLiteralRef { owner: Some(owner), ordinal: self.1, projected: None, source_raw: None }
    }
    pub(crate) fn into_bank_owner(mut self) -> OriginalLiteralOwner {
        OriginalLiteralOwner(self.0.take())
    }

    /// Adopt a genuine caller-owned grammar spelling, explicitly paying its
    /// actual capacity here. A naked String is NEVER treated as prepaid. Typed
    /// values are actual issued lexer/macro values, not parsed from this raw.
    pub fn from_value_using(raw:String,value:OriginalTokenValue<&str>,a:&SettingAdmission<'_>)->io::Result<Self> {
        Self::from_value_with_mode_using(raw,value,OriginalStringMode::Unknown,a)
    }
    pub fn from_value_with_mode_using(raw:String,value:OriginalTokenValue<&str>,mode:OriginalStringMode,a:&SettingAdmission<'_>)->io::Result<Self>{
        a.checkpoint()?;
        let credit=a.reserve(raw.capacity())?;
        Self::from_admitted_raw_with_mode_using(raw,credit,value,mode,a)
    }
    /// Resource-only move from the SAME actual admitted raw spelling owner.
    /// Physical String and original reservation move together; no copy, credit
    /// minting, source identity or foreign-domain adoption follows this API.
    pub fn from_admitted_raw_using(raw:String,credit:SettingRootLease,value:OriginalTokenValue<&str>,a:&SettingAdmission<'_>)->io::Result<Self>{
        Self::from_admitted_raw_with_mode_using(raw,credit,value,OriginalStringMode::Unknown,a)
    }
    pub fn from_admitted_raw_with_mode_using(raw:String,credit:SettingRootLease,value:OriginalTokenValue<&str>,mode:OriginalStringMode,a:&SettingAdmission<'_>)->io::Result<Self>{
        // Failure cleanup also owns raw BEFORE credit. Validation never lets
        // an unsupported/foreign producer leak or refund a live raw buffer.
        struct Pending { value: LiteralValue, credit: SettingRootLease }
        let mut pending = Pending {
            value: LiteralValue { kind: LiteralKind::Int, scalar_bits: 0, string_mode: mode,
                value_in_raw: [0, 0], raw, text: Box::default() },
            credit,
        };
        a.checkpoint()?;
        if !a.matches_lease_domain(&pending.credit) || pending.credit.bytes() < pending.value.raw.capacity() {
            return Err(fail(a,io::Error::new(io::ErrorKind::InvalidInput,"Original raw literal storage lacks its actual SAME-domain capacity credit")));
        }
        if !matches!(&value,OriginalTokenValue::Int(_)|OriginalTokenValue::Float(_)|OriginalTokenValue::String(_)|OriginalTokenValue::Resource(_)|OriginalTokenValue::InterpBegin(_)|OriginalTokenValue::InterpPart(_)|OriginalTokenValue::InterpEnd(_)) {
            return Err(fail(a,io::Error::new(io::ErrorKind::Unsupported,"Original literal DATA requires an actual scalar/static or interpolation-part value")));
        }
        if mode!=OriginalStringMode::Unknown&&!matches!(&value,OriginalTokenValue::String(_)|OriginalTokenValue::InterpBegin(_)|OriginalTokenValue::InterpPart(_)|OriginalTokenValue::InterpEnd(_)){
            return Err(fail(a,io::Error::new(io::ErrorKind::InvalidInput,"Original lexical string mode attached to non-String literal DATA")));
        }
        let fixed=bytes(a,size_of::<Payload>().checked_add(2*size_of::<usize>()))?;
        a.grow(&mut pending.credit,fixed)?;
        pending.value.kind = match value {
            OriginalTokenValue::Int(n) => {
                pending.value.scalar_bits = n as u32;
                LiteralKind::Int
            }
            OriginalTokenValue::Float(n) => {
                pending.value.scalar_bits = n.to_bits();
                LiteralKind::Float
            }
            OriginalTokenValue::String(s) => {
                pending.value.text = store_issued_value(s, &mut pending.value, &mut pending.credit, a)?;
                LiteralKind::String
            }
            OriginalTokenValue::Resource(s) => {
                pending.value.text = store_issued_value(s, &mut pending.value, &mut pending.credit, a)?;
                LiteralKind::Resource
            }
            OriginalTokenValue::InterpBegin(s) => {
                pending.value.text = store_issued_value(s, &mut pending.value, &mut pending.credit, a)?;
                LiteralKind::InterpBegin
            }
            OriginalTokenValue::InterpPart(s) => {
                pending.value.text = store_issued_value(s, &mut pending.value, &mut pending.credit, a)?;
                LiteralKind::InterpPart
            }
            OriginalTokenValue::InterpEnd(s) => {
                pending.value.text = store_issued_value(s, &mut pending.value, &mut pending.credit, a)?;
                LiteralKind::InterpEnd
            }
            _ => unreachable!("closed scalar/static/template-part gate"),
        };
        a.checkpoint()?;
        let Pending { value, credit } = pending;
        Ok(Self(Some(Arc::new(Payload { storage: LiteralStorage::Single(value), credit })), 0))
    }
    pub fn string_mode(&self) -> OriginalStringMode { self.as_view().string_mode() }
    pub fn raw(&self) -> &str { self.as_view().raw().expect("owned literal spelling") }
    pub fn raw_storage(&self) -> LiteralRawStorage<'_> { self.as_view().raw_storage().expect("owned literal spelling") }
    pub fn value(&self) -> OriginalTokenValue<&str> { self.as_view().value().expect("owned literal VALUE") }
    pub fn same_owner<'b>(&self, other: impl Into<OriginalLiteralRef<'b>>) -> bool {
        self.as_view().same_owner(other)
    }
    pub fn kind(&self) -> &'static str { self.as_view().kind() }
    #[cfg(test)]
    fn page_storage_identity(&self) -> Option<usize> { self.as_view().page_storage_identity() }
    pub fn visit_storage(&self, mut visit: impl FnMut(usize,usize,usize)) {
        let owner = self.0.as_ref().expect("live literal DATA");
        if let LiteralStorage::RawDetached(detached) = &owner.storage {
            let fixed = size_of::<Payload>() + 2 * size_of::<usize>();
            visit(Arc::as_ptr(owner) as usize, fixed, fixed);
            let bytes = size_of::<DetachedRaw>();
            visit(detached.as_ref() as *const _ as usize, bytes, bytes);
            if !detached.raw.is_empty() {
                visit(detached.raw.as_ptr() as usize, detached.raw.len(), detached.raw.len());
            }
        }
        self.as_view().visit_storage(visit)
    }
}
impl fmt::Debug for OriginalLiteralRef<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("OriginalLiteralRef").field("raw", &self.raw()).field("kind", &self.kind()).finish()
    }
}
impl<'a> OriginalLiteralRef<'a> {
    fn full_owner(self)->&'a Arc<Payload>{self.owner.expect("full physical literal owner")}
    fn projection(self)->Option<crate::original_literal_projection::ProjectedLiteralRef<'a>>{
     self.projected.or_else(||match &self.owner?.storage{LiteralStorage::Projected(data)=>Some(data.view()),_=>None})
    }
    pub fn is_projected(self)->bool{self.projection().is_some() || self.has_source_raw()}
    pub(crate) fn has_source_raw(self) -> bool {
        self.owner.is_some_and(|owner| match &owner.storage {
            LiteralStorage::Page(page) => page.rows[self.ordinal].has_source_raw(),
            _ => false,
        })
    }
    pub(crate) fn with_source_raw(mut self, source: Option<&'a str>, capacity: usize) -> Self {
        debug_assert!(self.has_source_raw());
        self.source_raw = source.map(|text| LiteralRawStorage { text, capacity });
        self
    }
    pub(crate) fn packed_source_raw_candidate(self) -> Option<usize> {
        let owner = self.full_owner();
        if Arc::strong_count(owner) != 1 || Arc::weak_count(owner) != 0 { return None; }
        let LiteralStorage::Page(page) = &owner.storage else { return None; };
        page.rows.get(self.ordinal)?.source_raw_candidate()
    }
    pub(crate) fn from_projection(data:crate::original_literal_projection::ProjectedLiteralRef<'a>)->Self{
     Self{owner:None,ordinal:data.ordinal,projected:Some(data),source_raw:None}
    }
    pub(crate) fn projection_candidate(self)->Option<(crate::original_literal_projection::ProjectedLiteral,usize)>{
     let owner=self.full_owner();
     if Arc::strong_count(owner)!=1||Arc::weak_count(owner)!=0{return None}
     let LiteralStorage::Single(data)=&owner.storage else{return None};
     let kind=match data.kind{
      LiteralKind::Int=>0,LiteralKind::Float=>1,
      LiteralKind::String if data.value_in_raw[1]!=0||data.text.is_empty()=>2,
      LiteralKind::Resource if data.value_in_raw[1]!=0||data.text.is_empty()=>3,
      _=>return None,
     };
     Some((crate::original_literal_projection::ProjectedLiteral{bits:data.scalar_bits,kind,mode:data.string_mode,alias:data.value_in_raw},owner.credit.bytes()))
    }
    /// Descriptor and real raw bytes in this uniquely owned packed row.
    /// The total lease is separately reported for complete owner retirement.
    pub(crate) fn packed_projection_candidate(
        self,
    ) -> Option<(crate::original_literal_projection::ProjectedLiteral, usize, usize, u32)> {
        let owner = self.full_owner();
        if Arc::strong_count(owner) != 1 || Arc::weak_count(owner) != 0 {
            return None;
        }
        let LiteralStorage::Page(page) = &owner.storage else { return None };
        let row = page.rows.get(self.ordinal)?;
        if row.raw_is_gone() {
            return None;
        }
        let kind = match row.kind() {
            LiteralKind::Int => 0,
            LiteralKind::Float => 1,
            LiteralKind::String if row.value_in_raw()[1] != 0 || row.scalar_or_text() == 0 => 2,
            LiteralKind::Resource if row.value_in_raw()[1] != 0 || row.scalar_or_text() == 0 => 3,
            _ => return None,
        };
        Some((
            crate::original_literal_projection::ProjectedLiteral {
                bits: row.scalar_or_text(),
                kind,
                mode: row.string_mode(),
                alias: row.value_in_raw(),
            },
            row.raw_capacity(),
            owner.credit.bytes(),
            u32::MAX >> (PAGE_ROWS - page.rows.len()),
        ))
    }

    fn payload(self) -> LiteralValueView<'a> {
        match &self.full_owner().storage {
            LiteralStorage::Single(value) => LiteralValueView {
                kind: value.kind, scalar_bits: value.scalar_bits,
                value_in_raw: value.value_in_raw, raw: LiteralRawStorage::from_string(&value.raw), text: &value.text,
            },
            LiteralStorage::Page(values) => values.rows[self.ordinal].view(&values.cooked),
            LiteralStorage::Projected(_) | LiteralStorage::RawDetached(_)=>unreachable!("projection handled before payload view"),
        }
    }
    pub fn string_mode(self)->OriginalStringMode {
        if let Some(data)=self.projection(){return data.descriptor.mode}
        match &self.full_owner().storage {
            LiteralStorage::Single(value) => value.string_mode,
            LiteralStorage::Page(values) => values.rows[self.ordinal].string_mode(),
            LiteralStorage::Projected(_) | LiteralStorage::RawDetached(_)=>unreachable!("projection handled before mode"),
        }
    }
    pub fn raw(self)->io::Result<&'a str> { Ok(self.raw_storage()?.as_str()) }
    pub fn raw_storage(self)->io::Result<LiteralRawStorage<'a>> {
        if let Some(data)=self.projection(){return Ok(LiteralRawStorage{text:data.raw()?,capacity:data.raw_capacity})}
        if self.has_source_raw() {
            return self.source_raw.ok_or_else(|| io::Error::new(
                io::ErrorKind::NotConnected, "Original projected spelling has no authenticated source loan"));
        }
        Ok(self.full_raw_storage())
    }
    fn full_raw_storage(self)->LiteralRawStorage<'a> {
        match &self.full_owner().storage {
            LiteralStorage::Single(value) => LiteralRawStorage::from_string(&value.raw),
            LiteralStorage::Page(values) => values.rows[self.ordinal].raw_view(),
            LiteralStorage::Projected(_) | LiteralStorage::RawDetached(_)=>unreachable!("projection handled before spelling"),
        }
    }
    pub fn value(self)->io::Result<OriginalTokenValue<&'a str>> {
        if let Some(data)=self.projection(){return data.descriptor.value(data.raw()?)}
        if self.has_source_raw() {
            let LiteralStorage::Page(page) = &self.full_owner().storage else { unreachable!() };
            return Ok(page.rows[self.ordinal].cooked_value(&page.cooked));
        }
        Ok(self.full_value())
    }
    fn full_value(self)->OriginalTokenValue<&'a str> {
        let payload = self.payload();
        let [start, tail] = payload.value_in_raw;
        let text: &str = if tail != 0 {
            let raw = payload.raw.as_str();
            let end = raw.len() - usize::from(tail - 1);
            &raw[usize::from(start)..end]
        } else {
            payload.text
        };
        match payload.kind {
            LiteralKind::Int => OriginalTokenValue::Int(payload.scalar_bits as i32),
            LiteralKind::Float => OriginalTokenValue::Float(f32::from_bits(payload.scalar_bits)),
            LiteralKind::String => OriginalTokenValue::String(text),
            LiteralKind::Resource => OriginalTokenValue::Resource(text),
            LiteralKind::InterpBegin => OriginalTokenValue::InterpBegin(text),
            LiteralKind::InterpPart => OriginalTokenValue::InterpPart(text),
            LiteralKind::InterpEnd => OriginalTokenValue::InterpEnd(text),
        }
    }
    /// Issued literal occurrence identity, independent of storage reuse.
    pub fn same_owner<'b>(self, other: impl Into<OriginalLiteralRef<'b>>) -> bool {
        let other = other.into();
        match(self.projection(),other.projection()){
         (Some(left),Some(right))=>left.same(right),
         (None,None)=>self.ordinal == other.ordinal && Arc::ptr_eq(self.full_owner(), other.full_owner()),
         _=>false,
        }
    }
    pub fn detach_using(self,a:&SettingAdmission<'_>) -> io::Result<OriginalLiteralData> {
        if let Some(data)=self.projected{
         let (projected,mut credit)=crate::original_literal_projection::DetachedProjectedLiteral::new(data,a)?;
         if let Err(error)=a.grow(&mut credit,size_of::<Payload>()+2*size_of::<usize>()){
          let error=a.take_operational_error().unwrap_or(error);drop(projected);drop(credit);return Err(error)
         }
         return Ok(OriginalLiteralData(Some(Arc::new(Payload{storage:LiteralStorage::Projected(projected),credit})),0));
        }
        if self.has_source_raw() {
            if !a.matches_lease_domain(&self.full_owner().credit) { return Err(io::ErrorKind::InvalidInput.into()); }
            let raw = self.raw()?;
            let fixed = size_of::<Payload>() + 2 * size_of::<usize>() + size_of::<DetachedRaw>();
            let mut credit = a.reserve(fixed).map_err(|error| a.take_operational_error().unwrap_or(error))?;
            let raw = copy_value_text(raw, a, &mut credit)?;
            let detached = Box::new(DetachedRaw {
                raw, owner: OriginalLiteralOwner(Some(Arc::clone(self.full_owner()))), ordinal: self.ordinal,
            });
            return Ok(OriginalLiteralData(Some(Arc::new(Payload {
                storage: LiteralStorage::RawDetached(detached), credit,
            })), 0));
        }
        Ok(OriginalLiteralData(Some(Arc::clone(self.full_owner())), self.ordinal))
    }
    pub(crate) fn owner_key(self) -> usize { Arc::as_ptr(self.full_owner()) as usize }
    pub(crate) fn ordinal(self) -> usize { self.ordinal }
    pub fn kind(self)->&'static str {
        if let Some(data)=self.projection(){return data.descriptor.kind()}
        let kind = match &self.full_owner().storage {
            LiteralStorage::Single(value) => value.kind,
            LiteralStorage::Page(values) => values.rows[self.ordinal].kind(),
            LiteralStorage::Projected(_) | LiteralStorage::RawDetached(_)=>unreachable!("projection handled before kind"),
        };
        match kind {
            LiteralKind::Int => "Int",
            LiteralKind::Float => "Float",
            LiteralKind::String => "String",
            LiteralKind::Resource => "Resource",
            LiteralKind::InterpBegin => "InterpBegin",
            LiteralKind::InterpPart => "InterpPart",
            LiteralKind::InterpEnd => "InterpEnd",
        }
    }
    // The Arc reference itself is already in the primary row allocation.
    // Do not count shared admission-counter Arcs in this payload family.
    #[cfg(debug_assertions)]
    pub(crate) fn trace_payload(self)->(bool,usize){
        let owner=self.full_owner();
        (Arc::strong_count(owner)==1,owner.credit.bytes())
    }
    /// Estimates the potential spelling-only projection on this issued row.
    /// Shared backing is a per-row upper bound. A standalone owner can be
    /// counted separately only while its unique occurrence owns the payload.
    #[cfg(debug_assertions)]
    pub(crate) fn trace_source_projection(self) -> Option<(usize, Option<usize>)> {
        if self.has_source_raw() { return None; }
        let row = self.payload();
        let eligible = match row.kind {
            LiteralKind::Int | LiteralKind::Float => true,
            LiteralKind::String | LiteralKind::Resource => row.value_in_raw[1] != 0 || row.text.is_empty(),
            LiteralKind::InterpBegin | LiteralKind::InterpPart | LiteralKind::InterpEnd => false,
        };
        let standalone = (self.ordinal == 0 && self.page_storage_identity().is_none()
            && Arc::strong_count(self.full_owner()) == 1).then_some(self.full_owner().credit.bytes());
        eligible.then_some((row.raw.capacity(), standalone))
    }
    #[cfg(debug_assertions)]
    pub(crate) fn trace_numeric_raw(self) -> Option<usize> {
        if self.has_source_raw() { return None; }
        let payload = self.payload();
        matches!(payload.kind, LiteralKind::Int | LiteralKind::Float)
            .then_some(payload.raw.capacity())
    }

    /// Debug-only actual packed allocation geometry. Withdrawn rows have
    /// already released their spelling and cannot enter this live mask.
    #[cfg(debug_assertions)]
    pub(crate) fn trace_packed_owner(self) -> (u32, usize, usize, usize) {
        let owner = self.full_owner();
        let LiteralStorage::Page(batch) = &owner.storage else { unreachable!("actual batch owner") };
        let live = batch.rows.iter().enumerate().fold(0u32, |mask, (at, row)| {
            if row.is_withdrawn() { mask } else { mask | (1 << at) }
        });
        (live, Arc::strong_count(owner), Arc::weak_count(owner), owner.credit.bytes())
    }

    /// Inspect the physical owner, including siblings not yet delivered.
    #[cfg(debug_assertions)]
    pub(crate) fn trace_batch_physical_row_capacity(self) -> usize {
        let LiteralStorage::Page(batch) = &self.full_owner().storage else { unreachable!("actual batch owner") };
        batch.rows.capacity()
    }

    #[cfg(debug_assertions)]
    pub(crate) fn trace_batch_numeric_raw(self) -> (usize, usize, usize) {
        let LiteralStorage::Page(batch) = &self.full_owner().storage else { unreachable!("actual batch owner") };
        let mut rows = 0;
        let mut raw_bytes = 0usize;
        let mut live = 0;
        for row in &batch.rows {
            if row.is_withdrawn() {
                continue;
            }
            live += 1;
            if matches!(row.kind(), LiteralKind::Int | LiteralKind::Float) {
                rows += 1;
                raw_bytes += row.raw_capacity();
            }
        }
        (rows, live, raw_bytes)
    }

    pub(crate) fn page_storage_identity(self) -> Option<usize> {
        let owner = self.full_owner().as_ref();
        matches!(&owner.storage, LiteralStorage::Page(_)).then_some(owner as *const Payload as usize)
    }

    /// Exact known live allocations only, not reservations, parser caches or
    /// source authority. Caller performs address dedup across all aliases.
    pub fn visit_storage(self,mut visit:impl FnMut(usize,usize,usize)) {
        if self.owner.is_none(){
         if let Some(data)=self.projection(){data.owner.visit_storage(visit)}
         return
        }
        let owner = self.full_owner().as_ref();
        let fixed = size_of::<Payload>() + 2 * size_of::<usize>();
        visit(Arc::as_ptr(self.full_owner()) as usize, fixed, fixed);
        fn raw_storage(raw: LiteralRawStorage<'_>, visit: &mut impl FnMut(usize,usize,usize)) {
            if raw.capacity() != 0 { visit(raw.as_ptr() as usize, raw.as_str().len(), raw.capacity()); }
        }
        fn cooked_storage(text: &str, visit: &mut impl FnMut(usize,usize,usize)) {
            if !text.is_empty() { visit(text.as_ptr() as usize, text.len(), text.len()); }
        }
        match &owner.storage {
            LiteralStorage::Projected(data)=>{
             visit(data.as_ref() as *const _ as usize,size_of::<crate::original_literal_projection::DetachedProjectedLiteral>(),size_of::<crate::original_literal_projection::DetachedProjectedLiteral>());
             raw_storage(LiteralRawStorage{text:&data.raw,capacity:data.raw.len()},&mut visit);
             data.owner.visit_storage(&mut visit);
            }
            LiteralStorage::RawDetached(_) => unreachable!("detached raw view resolves original packed owner"),
            LiteralStorage::Single(value) => {
                raw_storage(LiteralRawStorage::from_string(&value.raw), &mut visit);
                cooked_storage(&value.text, &mut visit);
            }
            LiteralStorage::Page(page) => {
                let rows = &page.rows;
                visit(rows.as_ptr() as usize, rows.len() * size_of::<PackedBatchValue>(),
                    rows.capacity() * size_of::<PackedBatchValue>());
                for row in rows {
                    if !row.raw_is_gone() {
                        raw_storage(row.raw_view(), &mut visit);
                    }
                }
                // A detached row owns the whole bounded page, including the
                // exact roster of any cooked strings belonging to its siblings.
                if !page.cooked.is_empty() {
                    visit(page.cooked.as_ptr() as usize, page.cooked.len() * size_of::<Box<str>>(),
                        page.cooked.len() * size_of::<Box<str>>());
                    for text in page.cooked.iter() { cooked_storage(text, &mut visit); }
                }
            }
        }
        owner.credit.visit_counter_storage(|ptr,n|{let bytes=n+2*size_of::<usize>();visit(ptr,bytes,bytes)});
    }
}

const PAGE_ROWS: usize = 32;
const PAGE_TEXT_BYTES: usize = 8 * 1024;
const MAX_ROW_TEXT_BYTES: usize = 1024;
const _: () = assert!(MAX_ROW_TEXT_BYTES as u64 <= PackedBatchValue::RAW_MASK
    && PAGE_ROWS <= u8::MAX as usize);

struct PendingPage {
    // Each staged row has already transferred its credit. On error these
    // buffers die before the aggregate lease.
    rows: [Option<LiteralValue>; PAGE_ROWS],
    credit: SettingRootLease,
}

impl LiteralValue {
    fn owned_bytes(&self) -> Option<usize> {
        self.raw.capacity().checked_add(self.text.len())
    }
}

/// One unpublished delivery slot. The owner field already has a vacant
/// representation; keep that sentinel private so no invalid DATA can escape.
#[repr(transparent)]
pub struct OriginalLiteralDeliverySlot(OriginalLiteralData);

impl OriginalLiteralDeliverySlot {
    pub fn new(data: OriginalLiteralData) -> Self { Self(data) }

    pub fn take(&mut self) -> Option<OriginalLiteralData> {
        let owner = self.0.0.take()?;
        Some(OriginalLiteralData(Some(owner), std::mem::take(&mut self.0.1)))
    }

    /// On error discard the complete unpublished batch, including any slots
    /// already taken by the same packer used by the ordinary Option form.
    pub fn pack_using(slots: &mut [Self], a: &SettingAdmission<'_>) -> io::Result<()> {
        OriginalLiteralData::pack_delivery_batch_using_slots(slots, a)
    }
}

trait LiteralDeliverySlot {
    fn data(&self) -> Option<&OriginalLiteralData>;
    fn take_data(&mut self) -> Option<OriginalLiteralData>;
    fn fill(&mut self, data: OriginalLiteralData);
}

impl LiteralDeliverySlot for OriginalLiteralDeliverySlot {
    fn data(&self) -> Option<&OriginalLiteralData> { self.0.0.as_ref().map(|_| &self.0) }
    fn take_data(&mut self) -> Option<OriginalLiteralData> { self.take() }
    fn fill(&mut self, data: OriginalLiteralData) {
        debug_assert!(self.0.0.is_none());
        self.0 = data;
    }
}

impl LiteralDeliverySlot for Option<OriginalLiteralData> {
    fn data(&self) -> Option<&OriginalLiteralData> { self.as_ref() }
    fn take_data(&mut self) -> Option<OriginalLiteralData> { self.take() }
    fn fill(&mut self, data: OriginalLiteralData) {
        debug_assert!(self.is_none());
        *self = Some(data);
    }
}

impl OriginalLiteralData {
    /// Resource-only change at the real complete Analyze delivery-batch
    /// boundary. The caller lends its owned unpublished slots. Still-shared
    /// pool entries and already sealed rows are left alone. There is no raw
    /// source/provider call, new typed fact, or source/EOF authority here.
    ///
    /// On error the caller must discard the entire unpublished batch. Any
    /// removed slots and any newly sealed pages can never be delivered as a
    /// partial source. No layout pointer or raw spelling is used as authority.
    pub fn pack_delivery_batch_using(
        slots: &mut [Option<Self>], a: &SettingAdmission<'_>,
    ) -> io::Result<()> {
        Self::pack_delivery_batch_using_slots(slots, a)
    }

    fn pack_delivery_batch_using_slots(
        slots: &mut [impl LiteralDeliverySlot], a: &SettingAdmission<'_>,
    ) -> io::Result<()> {
        let result = Self::pack_delivery_batch_inner(slots, a);
        result.map_err(|status| a.take_operational_error().unwrap_or(status))
    }

    fn pack_delivery_batch_inner(slots: &mut [impl LiteralDeliverySlot], a: &SettingAdmission<'_>) -> io::Result<()> {
        // Fixed candidate-index array. Only one page and no input-row copy can
        // be in staging. No heap is allocated while selecting a page.
        let mut selection = None;
        let mut indices = [0; PAGE_ROWS];
        let mut count = 0;
        let mut total = 0usize;
        for index in 0..slots.len() {
            if index % 256 == 0 { a.checkpoint()?; }
            let Some(value) = slots[index].data() else { return Err(io::ErrorKind::InvalidInput.into()) };
            let owner = value.0.as_ref().expect("live literal DATA");
            if !a.matches_lease_domain(&owner.credit) {
                return Err(io::ErrorKind::InvalidInput.into());
            }
            let LiteralStorage::Single(literal) = &owner.storage else { continue };
            if Arc::strong_count(owner) != 1 || Arc::weak_count(owner) != 0 {
                continue;
            }
            let owned = literal.owned_bytes().ok_or(io::ErrorKind::OutOfMemory)?;
            if owned > MAX_ROW_TEXT_BYTES || PackedBatchValue::raw_geometry(literal.raw.len(), literal.raw.capacity()).is_none() {
                continue;
            }
            let fixed = size_of::<Payload>() + 2 * size_of::<usize>();
            if owner.credit.bytes() < fixed.checked_add(owned).ok_or(io::ErrorKind::OutOfMemory)? {
                return Err(io::ErrorKind::InvalidData.into());
            }
            if slots.len() >= 4 && selection.is_none() {
                let Some(credit) = a.try_reserve_optimization(size_of::<[usize; PAGE_ROWS]>())? else {
                    return Ok(());
                };
                selection = Some(credit);
            }
            if count == PAGE_ROWS || total > PAGE_TEXT_BYTES - owned {
                Self::seal_page_using(slots, &indices[..count], total, a)?;
                count = 0;
                total = 0;
            }
            indices[count] = index;
            count += 1;
            total += owned;
        }
        Self::seal_page_using(slots, &indices[..count], total, a)
    }

    fn seal_page_using(
        slots: &mut [impl LiteralDeliverySlot], indices: &[usize], text_bytes: usize, a: &SettingAdmission<'_>,
    ) -> io::Result<()> {
        use std::{alloc::{alloc, Layout}, ptr::NonNull};

        if indices.len() < 4 {
            return Ok(());
        }
        let cooked_count = indices.iter().try_fold(0usize, |count, &index| {
            let data = slots[index].data().ok_or(io::ErrorKind::InvalidData)?;
            let LiteralStorage::Single(value) = &data.owner().storage else {
                return Err(io::ErrorKind::InvalidData);
            };
            // Validate all raw geometry before the first occurrence is moved.
            if PackedBatchValue::raw_geometry(value.raw.len(), value.raw.capacity()).is_none() {
                return Err(io::ErrorKind::InvalidData);
            }
            Ok(count + usize::from(!value.text.is_empty()))
        })?;
        let layout = Layout::array::<PackedBatchValue>(indices.len())
            .map_err(|error| fail(a, io::Error::new(io::ErrorKind::OutOfMemory, error)))?;
        let cooked_layout = Layout::array::<Box<str>>(cooked_count)
            .map_err(|error| fail(a, io::Error::new(io::ErrorKind::OutOfMemory, error)))?;
        let fixed = size_of::<Payload>() + 2 * size_of::<usize>();
        let controls = fixed.checked_add(layout.size()).and_then(|n| n.checked_add(cooked_layout.size()))
            .ok_or(io::ErrorKind::OutOfMemory)?;
        let retained = controls.checked_add(text_bytes).ok_or(io::ErrorKind::OutOfMemory)?;
        let old_fixed = fixed.checked_mul(indices.len()).ok_or(io::ErrorKind::OutOfMemory)?;
        if controls >= old_fixed {
            return Ok(());
        }

        // The only actual old/new overlap is bounded stack staging. Admit it
        // while ALL old wrapper leases are still alive. The future row/Arc
        // heap overlap is zero: no page allocation occurs until old Arcs die.
        let Some(_staging) = a.try_reserve_optimization(size_of::<PendingPage>())? else {
            return Ok(());
        };
        let mut pending = PendingPage { rows: std::array::from_fn(|_| None), credit: a.reserve(0)? };
        for (row, index) in pending.rows.iter_mut().zip(indices.iter().copied()) {
            let mut occurrence = slots[index].take_data().ok_or(io::ErrorKind::InvalidData)?;
            let owner = occurrence.0.take().ok_or(io::ErrorKind::InvalidData)?;
            // The batch's private unpublished slot was the only strong/weak
            // owner. Arc::into_inner destroys that real allocation now.
            let mut single = Arc::into_inner(owner).ok_or(io::ErrorKind::InvalidData)?;
            a.absorb(&mut pending.credit, &mut single.credit)?;
            let LiteralStorage::Single(value) = single.storage else {
                unreachable!("only singleton candidates")
            };
            *row = Some(value);
        }
        let surplus = pending.credit.bytes().checked_sub(retained).ok_or(io::ErrorKind::InvalidData)?;
        a.checkpoint()?;
        // SAFETY: the exact positive Layout is funded above using only the
        // physically freed old wrapper leases and continuously held byte
        // backing. Global owns this allocation until the standard Vec drops it.
        fn allocate<T>(layout: Layout, count: usize) -> io::Result<Vec<T>> {
            if count == 0 { return Ok(Vec::new()); }
            debug_assert_eq!(Layout::array::<T>(count).ok(), Some(layout));
            let ptr = NonNull::new(unsafe { alloc(layout) }).ok_or(io::ErrorKind::OutOfMemory)?;
            // SAFETY: the exact positive Global layout is funded by pending
            // before either buffer is allocated, and all rows start uninitialized.
            Ok(unsafe { Vec::from_raw_parts(ptr.as_ptr().cast::<T>(), 0, count) })
        }
        let mut rows = allocate(layout, indices.len())?;
        let mut cooked = allocate(cooked_layout, cooked_count)?;
        for slot in &mut pending.rows[..indices.len()] {
            rows.push(PackedBatchValue::adopt(slot.take().expect("adopted literal staging"), &mut cooked));
        }
        debug_assert_eq!(cooked.len(), cooked_count);
        let page = BatchValues { rows, cooked: cooked.into_boxed_slice() };
        // The precharged Vec and all moved backing still live during the
        // shrink. Release only the exact bytes freed by the old controls.
        a.shrink(&mut pending.credit, surplus)?;
        let owner = Arc::new(Payload { storage: LiteralStorage::Page(page), credit: pending.credit });
        for (row, index) in indices.iter().copied().enumerate() {
            slots[index].fill(Self(Some(Arc::clone(&owner)), row));
        }
        Ok(())
    }
}

const NUMERIC_SLOTS:usize=16;
const SHORT_NUMERIC_BYTES:usize=16;
#[derive(Clone,Copy,PartialEq,Eq)]
enum NumericKey { Int(i32), Float(u32) }
impl NumericKey {
    fn from_value(value:&OriginalTokenValue<&str>)->Option<Self> {
        match value {
            OriginalTokenValue::Int(value)=>Some(Self::Int(*value)),
            OriginalTokenValue::Float(value)=>Some(Self::Float(value.to_bits())),
            _=>None,
        }
    }
    fn slot(self, raw:&str)->usize {
        // Slot selection is only a reuse hint. Full spelling and typed bits
        // are checked on every hit; a collision simply replaces one entry.
        let mut hash=match self {
            Self::Int(value)=>value as u32,
            Self::Float(bits)=>bits ^ 0xa9b4_e9e1,
        };
        for byte in raw.bytes() {
            hash=hash.wrapping_mul(16_777_619) ^ u32::from(byte);
        }
        (hash as usize) % NUMERIC_SLOTS
    }
}

const STATIC_SLOTS: usize = 128;
const STATIC_WAYS: usize = 4;
const STATIC_SETS: usize = STATIC_SLOTS / STATIC_WAYS;
const SHORT_STATIC_BYTES: usize = 128;

#[derive(Clone, Copy, PartialEq, Eq)]
enum StaticKey<'a> { String(&'a str), Resource(&'a str) }
impl<'a> StaticKey<'a> {
    fn from_value(value: &OriginalTokenValue<&'a str>, mode: OriginalStringMode) -> Option<Self> {
        match value {
            OriginalTokenValue::String(text) => Some(Self::String(*text)),
            OriginalTokenValue::Resource(text) if mode == OriginalStringMode::Unknown => Some(Self::Resource(*text)),
            _ => None,
        }
    }
    fn text(self) -> &'a str {
        match self { Self::String(text) | Self::Resource(text) => text }
    }
    fn slot(self, raw: &str, mode: OriginalStringMode) -> usize {
        // Collisions only select eviction. The hit path also compares the full
        // raw spelling, issued lexical mode and exact typed text and variant.
        let tag = match self { Self::String(_) => 0x8cf5_3331u32, Self::Resource(_) => 0x7a40_6b91 };
        let mut hash = tag ^ u32::from(mode as u8);
        for byte in raw.bytes().chain(self.text().bytes()) {
            hash = hash.wrapping_mul(16_777_619) ^ u32::from(byte);
        }
        (hash as usize) % STATIC_SLOTS
    }
}

/// Bounded producer-local reuse of short immutable VALUE storage. Numeric
/// slots keep their original geometry. The separate static bank is inline in
/// the output cursor and cannot issue spans, raw frames or parser authority.
pub struct OriginalLiteralPool {
    numeric: [Option<OriginalLiteralData>; NUMERIC_SLOTS],
    static_text: [[Option<OriginalLiteralData>; STATIC_WAYS]; STATIC_SETS],
    issued: usize,
    domain: SettingRootLease,
}
impl OriginalLiteralPool {
    #[cfg(test)]
    pub(crate) fn advance_empty_pool_for_test(&mut self, issued: usize) {
        assert_eq!(self.issued, 0);
        self.issued = issued;
    }

    pub fn new(a:&SettingAdmission<'_>)->io::Result<Self> {
        Ok(Self {
            numeric: std::array::from_fn(|_| None),
            static_text: std::array::from_fn(|_| std::array::from_fn(|_| None)),
            issued: 0,
            domain: a.reserve(0)?,
        })
    }

    pub fn issue_using(&mut self,raw:String,credit:SettingRootLease,value:OriginalTokenValue<&str>,mode:OriginalStringMode,a:&SettingAdmission<'_>)->io::Result<OriginalLiteralData> {
        // Actual borrowed raw bytes have already been copied by the caller
        // in its existing source IO order. Even a cache hit must authenticate
        // and drop that actual allocation before releasing its own credit.
        struct Pending { raw:String, credit:SettingRootLease }
        let pending=Pending{raw,credit};
        a.checkpoint()?;
        if !a.matches_lease_domain(&self.domain)||!a.matches_lease_domain(&pending.credit)||pending.credit.bytes()<pending.raw.capacity(){
            return Err(fail(a,io::Error::new(io::ErrorKind::InvalidInput,"literal reuse requires the actual SAME-domain raw literal allocation")));
        }
        let Some(ordinal) = self.issued.checked_add(1) else {
            return OriginalLiteralData::from_admitted_raw_with_mode_using(pending.raw,pending.credit,value,mode,a);
        };
        let numeric = NumericKey::from_value(&value)
            .filter(|_| mode == OriginalStringMode::Unknown && pending.raw.len() <= SHORT_NUMERIC_BYTES);
        let static_key = StaticKey::from_value(&value, mode)
            .filter(|key| pending.raw.len() <= SHORT_STATIC_BYTES && key.text().len() <= SHORT_STATIC_BYTES);
        let candidates: &mut [Option<OriginalLiteralData>] = if let Some(key) = numeric {
            std::slice::from_mut(&mut self.numeric[key.slot(&pending.raw)])
        } else if let Some(key) = static_key {
            // Same fixed bank size. A spelling collision can displace only
            // the least recently used value after the whole set fills.
            &mut self.static_text[key.slot(&pending.raw, mode) / STATIC_WAYS]
        } else {
            return OriginalLiteralData::from_admitted_raw_with_mode_using(pending.raw,pending.credit,value,mode,a);
        };
        let matching = candidates.iter().position(|candidate| {
            candidate.as_ref().is_some_and(|cached| {
                if cached.raw() != pending.raw || cached.string_mode() != mode {
                    return false;
                }
                let current = cached.value();
                if let Some(key) = numeric {
                    return NumericKey::from_value(&current) == Some(key);
                }
                StaticKey::from_value(&current, mode) == static_key
            })
        });
        if let Some(index) = matching {
            // Only this pool sees this backing. One serial covers both banks,
            // preserving each occurrence even after eviction and reinsertion.
            let mut occurrence = candidates[index].as_ref().expect("matched occupied slot").clone();
            occurrence.1 = ordinal;
            drop(pending);
            a.checkpoint()?;
            candidates[..=index].rotate_right(1);
            self.issued = ordinal;
            return Ok(occurrence);
        }
        let mut occurrence=OriginalLiteralData::from_admitted_raw_with_mode_using(pending.raw,pending.credit,value,mode,a)?;
        occurrence.1=ordinal;
        candidates.rotate_right(1);
        candidates[0] = Some(occurrence.clone());
        self.issued=ordinal;
        Ok(occurrence)
    }
}

impl PartialEq for OriginalLiteralData {
    fn eq(&self, other: &Self) -> bool { self.as_view().equal_data(other.as_view()).expect("owned literal DATA") }
}
impl Eq for OriginalLiteralData {}
impl OriginalLiteralRef<'_>{
 pub fn equal_data(self,other:OriginalLiteralRef<'_>)->io::Result<bool>{
  if self.raw()?!=other.raw()?||self.string_mode()!=other.string_mode(){return Ok(false)}
  Ok(match(self.value()?,other.value()?){
   (OriginalTokenValue::Int(a),OriginalTokenValue::Int(b))=>a==b,
   (OriginalTokenValue::Float(a),OriginalTokenValue::Float(b))=>a.to_bits()==b.to_bits(),
   (OriginalTokenValue::String(a),OriginalTokenValue::String(b))|(OriginalTokenValue::Resource(a),OriginalTokenValue::Resource(b))|(OriginalTokenValue::InterpBegin(a),OriginalTokenValue::InterpBegin(b))|(OriginalTokenValue::InterpPart(a),OriginalTokenValue::InterpPart(b))|(OriginalTokenValue::InterpEnd(a),OriginalTokenValue::InterpEnd(b))=>a==b,
   _=>false,
  })
 }
}

#[cfg(test)]mod tests {
 use super::*; use std::sync::atomic::{Ordering};
 #[test]
 fn compact_literal_payload_preserves_typed_bits_text_and_exact_admitted_storage() {
    #[cfg(target_pointer_width = "64")]
    {
        #[allow(dead_code)]
        struct PreviousShape {
            string_mode: OriginalStringMode,
            value_in_raw: [u8; 2],
            raw: String,
            value: OriginalTokenValue<String>,
            credit: SettingRootLease,
        }
        assert_eq!(size_of::<OriginalLiteralData>(), 2 * size_of::<usize>());
        assert_eq!(size_of::<LiteralValue>(), 48);
        assert!(size_of::<Payload>() <= size_of::<PreviousShape>());
        assert!(size_of::<Payload>() <= 72, "bounded standalone owner overhead");
    }
    let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let healthy = SettingAdmission::new(&counter, 1 << 20, &|| Ok(()));
    let raw = String::from("raw spelling");
    let fixed = size_of::<Payload>() + 2 * size_of::<usize>();
    let total = fixed + raw.capacity() + "typed Ã©".len();
    let tight = SettingAdmission::new(&counter, crate::SettingChargeCounter::root_allocation_bytes() + (total - 1), &|| Ok(()));
    assert_eq!(
        OriginalLiteralData::from_value_using(raw.clone(), OriginalTokenValue::InterpPart("typed Ã©"), &tight).unwrap_err().kind(),
        io::ErrorKind::OutOfMemory,
    );
    assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    let part = OriginalLiteralData::from_value_using(raw, OriginalTokenValue::InterpPart("typed Ã©"), &healthy).unwrap();
    assert!(matches!(part.value(), OriginalTokenValue::InterpPart("typed Ã©")));
    assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (total));
    let mut visited = false;
    let typed = part.payload().text.as_ptr() as usize;
    part.visit_storage(|ptr, used, capacity| {
        if ptr == typed {
            visited = true;
            assert_eq!(used, "typed Ã©".len());
            assert_eq!(capacity, used);
        }
    });
    assert!(visited);
    let alias = part.clone();
    drop(part);
    assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (total));
    drop(alias);
    assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());

    let n = OriginalLiteralData::from_value_using("raw".into(), OriginalTokenValue::Int(i32::MIN), &healthy).unwrap();
    let f = OriginalLiteralData::from_value_using("raw".into(), OriginalTokenValue::Float(f32::from_bits(0xffc00001)), &healthy).unwrap();
    assert!(matches!(n.value(), OriginalTokenValue::Int(i32::MIN)));
    assert!(matches!(f.value(), OriginalTokenValue::Float(value) if value.to_bits() == 0xffc00001));
    drop((n, f));
    assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn short_static_value_can_borrow_exact_utf8_bytes_from_its_own_raw_owner() {
  let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
  let raw = r#""Ã©\n""#;
  let same = OriginalLiteralData::from_value_with_mode_using(raw.into(), OriginalTokenValue::String(r"Ã©\n"), OriginalStringMode::Raw, &a).unwrap();
  let OriginalTokenValue::String(value) = same.value() else { panic!("same issued String variant") };
  assert_eq!(value, r"Ã©\n");
  assert_eq!(value.as_ptr(), same.raw()[1..].as_ptr());
  let fixed = size_of::<Payload>() + 2 * size_of::<usize>();
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (fixed + same.raw_storage().capacity()));
  assert_eq!(same.string_mode(), OriginalStringMode::Raw);
  let alias = same.clone();
  drop(same);
  assert!(matches!(alias.value(), OriginalTokenValue::String(r"Ã©\n")));
  drop(alias);
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());

  let changed = OriginalLiteralData::from_value_using(raw.into(), OriginalTokenValue::String("Ã©\n"), &a).unwrap();
  let OriginalTokenValue::String(value) = changed.value() else { panic!("same issued String variant") };
  assert_eq!(value, "Ã©\n");
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (fixed + changed.raw_storage().capacity() + value.len()));
  let resource = OriginalLiteralData::from_value_using("'icons/a.dmi'".into(), OriginalTokenValue::Resource("icons/a.dmi"), &a).unwrap();
  let OriginalTokenValue::Resource(value) = resource.value() else { panic!("same issued Resource variant") };
  assert_eq!(value.as_ptr(), resource.raw()[1..].as_ptr());
  drop((resource, changed));
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());

  let long = format!("'{}'", "x".repeat(256));
  let wide = OriginalLiteralData::from_value_using(long.clone(), OriginalTokenValue::Resource(&long[1..long.len()-1]), &a).unwrap();
  let OriginalTokenValue::Resource(value) = wide.value() else { panic!("same issued Resource variant") };
  assert_ne!(value.as_ptr(), wide.raw()[1..].as_ptr(), "wide spans keep the full-width owned path");
  assert_eq!(value.len(), 256);
  drop(wide);
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn exact_values_and_float_bits_are_data_not_raw_reparse(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);
  let values=[OriginalTokenValue::Int(0),OriginalTokenValue::Float(-0.0),OriginalTokenValue::Float(f32::from_bits(0x7fc00111)),OriginalTokenValue::String("[not interpolation]"),OriginalTokenValue::Resource("a\\b")];
  for value in values {let data=OriginalLiteralData::from_value_using("same spelling".into(),value,&a).unwrap();let copy=data.clone();assert_eq!(data,copy);assert!(data.same_owner(&copy));let mut capacity=0;data.visit_storage(|_,_,n|capacity+=n);assert!(capacity>data.raw().len());}
  let positive=OriginalLiteralData::from_value_using("0".into(),OriginalTokenValue::Float(0.0),&a).unwrap();let negative=OriginalLiteralData::from_value_using("0".into(),OriginalTokenValue::Float(-0.0),&a).unwrap();assert_ne!(positive,negative);drop((positive,negative));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_alias_lifetime_keeps_credit_until_last_data_and_ast_drop(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);
  let data=OriginalLiteralData::from_value_using("\"raw\"".into(),OriginalTokenValue::String("[static]"),&a).unwrap();let charged=counter.load(Ordering::Acquire);let literal=crate::LiteralText::from_original_data(&data,40,&a).unwrap();assert!(literal.original_data().unwrap().same_owner(&data));drop(data);assert_eq!(counter.load(Ordering::Acquire),charged);assert_eq!(literal.syntax_parts().unwrap(),None);drop(literal);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_quota_and_first_1450_leave_no_retained_data_and_fresh_admission_recovers(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let no=||Ok(());let small=SettingAdmission::new(&counter,crate::SettingChargeCounter::root_allocation_bytes(),&no);assert!(OriginalLiteralData::from_value_using("x".into(),OriginalTokenValue::String("value"),&small).is_err());assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let calls=std::cell::Cell::new(0);let stop=||{calls.set(calls.get()+1);if calls.get()==4{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};let a=SettingAdmission::new(&counter,1<<20,&stop);assert!(OriginalLiteralData::from_value_using("raw".into(),OriginalTokenValue::String("value"),&a).is_err());assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let fresh=SettingAdmission::new(&counter,1<<20,&no);drop(OriginalLiteralData::from_value_using("x".into(),OriginalTokenValue::Int(1),&fresh).unwrap());assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn interpolation_part_is_actual_typed_data_not_static_or_reconstructed(){let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&counter,1<<20,&||Ok(()));for value in[OriginalTokenValue::InterpBegin("[not a child]"),OriginalTokenValue::InterpPart("middle"),OriginalTokenValue::InterpEnd("last")]{let data=OriginalLiteralData::from_value_with_mode_using("unrelated raw spelling".into(),value,OriginalStringMode::Normal,&a).unwrap();let alias=data.clone();assert!(matches!(data.value(),OriginalTokenValue::InterpBegin("[not a child]")|OriginalTokenValue::InterpPart("middle")|OriginalTokenValue::InterpEnd("last")));assert!(data.same_owner(&alias));drop(data);assert!(counter.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());drop(alias);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}}
}

#[cfg(test)]mod admitted_raw_tests{
 use super::*;use std::sync::atomic::{Ordering};
 #[test]fn raw_spelling_moves_same_allocation_and_credit_without_a_second_capacity_charge(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);let mut raw=String::with_capacity(4096);raw.push_str("\"[static]\"");let ptr=raw.as_ptr();let capacity=raw.capacity();let credit=a.reserve(capacity).unwrap();let data=OriginalLiteralData::from_admitted_raw_using(raw,credit,OriginalTokenValue::Int(3),&a).unwrap();assert_eq!(data.raw_storage().as_ptr(),ptr);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (capacity+size_of::<Payload>()+2*size_of::<usize>()));drop(data);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn foreign_or_short_admitted_raw_credit_is_rejected_without_moving_domains_or_leaking_raw(){
  let own=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let other=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&own,1<<20,&poll);let foreign=SettingAdmission::new(&other,1<<20,&poll);let raw=String::from("raw");let credit=foreign.reserve(raw.capacity()).unwrap();assert!(OriginalLiteralData::from_admitted_raw_using(raw,credit,OriginalTokenValue::Int(1),&a).is_err());assert_eq!(own.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());assert_eq!(other.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());let fresh=SettingAdmission::new(&own,1<<20,&poll);let raw=String::from("raw");let short=fresh.reserve(raw.capacity()-1).unwrap();assert!(OriginalLiteralData::from_admitted_raw_using(raw,short,OriginalTokenValue::Int(1),&fresh).is_err());assert_eq!(own.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod string_mode_tests{
 use super::*;use std::sync::atomic::{Ordering};
 #[test]fn actual_modes_are_distinct_immutable_facts_without_spelling_inference_or_ast_cache(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let raw="\"same\\n[static]\"";let mut values=Vec::new();for mode in [OriginalStringMode::Unknown,OriginalStringMode::Normal,OriginalStringMode::Raw,OriginalStringMode::Generated]{let data=OriginalLiteralData::from_value_with_mode_using(raw.into(),OriginalTokenValue::String("same\\n[static]"),mode,&a).unwrap();assert_eq!(data.string_mode(),mode);let text=crate::LiteralText::from_original_data(&data,70,&a).unwrap();assert_eq!(text.original_string_mode(),Some(mode));assert_eq!(text.rebind_original_using(90,&a).unwrap().original_string_mode(),Some(mode));assert!(text.syntax_parts().unwrap().is_none());for old in &values{assert_ne!(&data,old);}values.push(data);}drop(values);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn existing_ctor_does_not_guess_mode_and_admitted_raw_keeps_pointer_credit_and_real_mode(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let old=OriginalLiteralData::from_value_using("@{raw}".into(),OriginalTokenValue::String("raw"),&a).unwrap();assert_eq!(old.string_mode(),OriginalStringMode::Unknown);drop(old);let raw=String::from("raw grammar");let ptr=raw.as_ptr();let credit=a.reserve(raw.capacity()).unwrap();let data=OriginalLiteralData::from_admitted_raw_with_mode_using(raw,credit,OriginalTokenValue::String("typed"),OriginalStringMode::Raw,&a).unwrap();assert_eq!(data.raw_storage().as_ptr(),ptr);assert_eq!(data.string_mode(),OriginalStringMode::Raw);drop(data);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
}


#[cfg(test)]
mod numeric_reuse_tests {
    use super::*;
    use std::sync::atomic::{Ordering};

    fn issue(pool:&mut OriginalLiteralPool, raw:&str, value:OriginalTokenValue<&str>, a:&SettingAdmission<'_>)->io::Result<OriginalLiteralData>{
        let raw=raw.to_owned();
        let credit=a.reserve(raw.capacity())?;
        pool.issue_using(raw,credit,value,OriginalStringMode::Unknown,a)
    }

    #[test]
    fn repeated_numeric_occurrences_share_payload_and_keep_their_own_identity(){
        let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
        let mut pool=OriginalLiteralPool::new(&a).unwrap();
        let first=issue(&mut pool,"7",OriginalTokenValue::Int(7),&a).unwrap();
        let first_bytes=used.load(Ordering::Acquire);
        let many:Vec<_>=(0..256).map(|_|issue(&mut pool,"7",OriginalTokenValue::Int(7),&a).unwrap()).collect();
        assert_eq!(used.load(Ordering::Acquire),first_bytes,"hits retain only the original payload");
        for next in &many {
            assert_eq!(next,&first);
            assert_eq!(next.raw_storage().as_ptr(),first.raw_storage().as_ptr());
            assert!(!next.same_owner(&first));
            assert!(next.same_owner(&next.clone()));
        }
        assert!(!many[0].same_owner(&many[1]));
        assert!(256*first_bytes>256*std::mem::size_of::<usize>(),"payload reuse also repays the occurrence word");
        drop(pool);
        drop(first);
        assert_eq!(used.load(Ordering::Acquire),first_bytes);
        drop(many);
        assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn numeric_reuse_keeps_raw_spelling_float_bits_and_pool_domains_exact(){
        let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
        let mut pool=OriginalLiteralPool::new(&a).unwrap();
        let zero=issue(&mut pool,"0",OriginalTokenValue::Int(0),&a).unwrap();
        let hex=issue(&mut pool,"0x0",OriginalTokenValue::Int(0),&a).unwrap();
        let positive=issue(&mut pool,"0",OriginalTokenValue::Float(0.0),&a).unwrap();
        let negative=issue(&mut pool,"0",OriginalTokenValue::Float(-0.0),&a).unwrap();
        assert_ne!(zero,hex);
        assert_ne!(zero,positive);
        assert_ne!(positive,negative);
        assert_eq!(hex.raw(),"0x0");
        let mut foreign=OriginalLiteralPool::new(&a).unwrap();
        let other=issue(&mut foreign,"0",OriginalTokenValue::Int(0),&a).unwrap();
        assert_eq!(zero,other);
        assert!(!zero.same_owner(&other));
        assert_ne!(zero.raw_storage().as_ptr(),other.raw_storage().as_ptr());
        let first=issue(&mut pool,"7",OriginalTokenValue::Int(7),&a).unwrap();
        let raw="7".to_owned();
        let credit=a.reserve(raw.capacity()).unwrap();
        let fault=||Err(io::Error::from_raw_os_error(1450));
        let failed=SettingAdmission::new(&used,1<<20,&fault);
        assert!(pool.issue_using(raw,credit,OriginalTokenValue::Int(7),OriginalStringMode::Unknown,&failed).is_err());
        assert_eq!(failed.take_operational_error().unwrap().raw_os_error(),Some(1450));
        let next=issue(&mut pool,"7",OriginalTokenValue::Int(7),&a).unwrap();
        assert_eq!(next.raw_storage().as_ptr(),first.raw_storage().as_ptr());
        assert!(!next.same_owner(&first));
        drop((next,first,zero,hex,positive,negative,other,foreign,pool));
        assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
    }
}

#[cfg(test)]
mod static_reuse_tests {
    use super::*;
    use std::sync::atomic::{Ordering};

    fn issue(pool: &mut OriginalLiteralPool, raw: &str, value: OriginalTokenValue<&str>,
        mode: OriginalStringMode, a: &SettingAdmission<'_>) -> OriginalLiteralData {
        let raw = raw.to_owned();
        let credit = a.reserve(raw.capacity()).unwrap();
        pool.issue_using(raw, credit, value, mode, a).unwrap()
    }

    #[test]
    fn short_static_values_share_only_exact_raw_typed_value_mode_and_producer() {
        use OriginalStringMode::{Generated, Normal, Raw, Unknown};
        use OriginalTokenValue::{InterpBegin, Resource, String};
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut pool = OriginalLiteralPool::new(&a).unwrap();
        let first = issue(&mut pool, r#""[static]""#, String("[static]"), Generated, &a);
        let paid = used.load(Ordering::Acquire);
        let aliases: Vec<_> = (0..64).map(|_| issue(&mut pool, r#""[static]""#, String("[static]"), Generated, &a)).collect();
        assert_eq!(used.load(Ordering::Acquire), paid);
        for next in &aliases {
            assert_eq!(first, *next);
            assert_eq!(first.raw().as_ptr(), next.raw().as_ptr());
            assert!(!first.same_owner(next));
            assert!(next.same_owner(&next.clone()));
        }
        assert!(!aliases[0].same_owner(&aliases[1]));

        let normal = issue(&mut pool, "same", String("typed"), Normal, &a);
        let raw = issue(&mut pool, "same", String("typed"), Raw, &a);
        let other_spelling = issue(&mut pool, "other", String("typed"), Normal, &a);
        let other_value = issue(&mut pool, "same", String("different"), Normal, &a);
        let resource = issue(&mut pool, "same", Resource("typed"), Unknown, &a);
        let resource_repeat = issue(&mut pool, "same", Resource("typed"), Unknown, &a);
        let unknown = issue(&mut pool, "same", String("typed"), Unknown, &a);
        for other in [&raw, &other_spelling, &other_value, &resource, &unknown] {
            assert_ne!(&normal, other);
            assert_ne!(normal.raw().as_ptr(), other.raw().as_ptr());
        }
        assert_ne!(resource, unknown);
        assert_eq!(resource.raw().as_ptr(), resource_repeat.raw().as_ptr());
        assert!(!resource.same_owner(&resource_repeat));
        let mut other = OriginalLiteralPool::new(&a).unwrap();
        let foreign = issue(&mut other, r#""[static]""#, String("[static]"), Generated, &a);
        assert_eq!(first, foreign);
        assert_ne!(first.raw().as_ptr(), foreign.raw().as_ptr());
        assert!(!first.same_owner(&foreign));

        let begin = issue(&mut pool, "fragment", InterpBegin("fragment"), Normal, &a);
        let begin_again = issue(&mut pool, "fragment", InterpBegin("fragment"), Normal, &a);
        assert_eq!(begin, begin_again);
        assert_ne!(begin.raw().as_ptr(), begin_again.raw().as_ptr());
        let long = "x".repeat(SHORT_STATIC_BYTES + 1);
        let wide = issue(&mut pool, &long, String("short"), Normal, &a);
        let wide_again = issue(&mut pool, &long, String("short"), Normal, &a);
        assert_ne!(wide.raw().as_ptr(), wide_again.raw().as_ptr());
        drop((first, aliases, normal, raw, other_spelling, other_value, resource, resource_repeat,
            unknown, foreign, begin, begin_again, wide, wide_again, other, pool));
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn static_pool_keeps_colliding_values_in_the_same_funded_bank() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut pool = OriginalLiteralPool::new(&a).unwrap();
        assert_eq!(size_of_val(&pool.static_text), size_of::<[Option<OriginalLiteralData>; STATIC_SLOTS]>());

        let mode = OriginalStringMode::Normal;
        let slot = StaticKey::String("anchor").slot("anchor", mode);
        let mut spellings = vec!["anchor".to_owned()];
        spellings.extend((0..4096).map(|n| format!("collision-{n}"))
            .filter(|s| StaticKey::String(s).slot(s, mode) == slot).take(STATIC_WAYS));
        assert_eq!(spellings.len(), STATIC_WAYS + 1);
        let add = |pool: &mut OriginalLiteralPool, name: &str| {
            issue(pool, name, OriginalTokenValue::String(name), mode, &a)
        };

        let issued: Vec<_> = spellings[..STATIC_WAYS].iter().map(|s| add(&mut pool, s)).collect();
        let paid = used.load(Ordering::Acquire);
        let recent = add(&mut pool, &spellings[0]);
        assert_eq!(recent.raw().as_ptr(), issued[0].raw().as_ptr());
        assert!(!recent.same_owner(&issued[0]));
        assert_eq!(used.load(Ordering::Acquire), paid);

        let extra = add(&mut pool, &spellings[STATIC_WAYS]);
        let still_recent = add(&mut pool, &spellings[0]);
        let evicted = add(&mut pool, &spellings[1]);
        assert_eq!(still_recent.raw().as_ptr(), recent.raw().as_ptr());
        assert_ne!(evicted.raw().as_ptr(), issued[1].raw().as_ptr());
        assert_eq!(evicted, issued[1]);
        drop((issued, recent, extra, still_recent, evicted, pool));
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

}

#[cfg(test)]
mod interpolation_backing_tests {
    use super::*;
    use std::sync::atomic::{Ordering};

    #[test]
    fn long_issued_literal_value_keeps_exact_utf8_slice_and_offset_limits() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let issued = "Ã©value".repeat(600);
        let fixed = size_of::<Payload>() + 2 * size_of::<usize>();
        for (prefix, suffix, aliases) in [
            ("\"".to_owned(), "\"".to_owned(), true),
            ("x".repeat(255), "y".repeat(254), true),
            ("â‚¬".to_owned(), "y".repeat(253), true),
            ("x".repeat(256), String::new(), false),
            (String::new(), "y".repeat(255), false),
            ("x".repeat(256), "y".repeat(254), false),
        ] {
            let raw = format!("{prefix}{issued}{suffix}");
            let pointer = raw.as_ptr();
            let literal = OriginalLiteralData::from_value_with_mode_using(
                raw, OriginalTokenValue::String(&issued), OriginalStringMode::Raw, &a,
            ).unwrap();
            let OriginalTokenValue::String(value) = literal.value() else { panic!("actual String") };
            assert_eq!(literal.raw().as_ptr(), pointer);
            assert_eq!(value, issued);
            assert_eq!(value.as_ptr() == literal.raw()[prefix.len()..].as_ptr(), aliases);
            assert_eq!(literal.string_mode(), OriginalStringMode::Raw);
            assert_eq!(used.load(Ordering::Acquire),
                crate::SettingChargeCounter::root_allocation_bytes() + (fixed + literal.raw_storage().capacity() + if aliases { 0 } else { issued.len() }));
            drop(literal);
            assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
        }

        let raw = format!("\"{}\\t\"", "a".repeat(400));
        let issued = format!("{}\t", "a".repeat(400));
        let literal = OriginalLiteralData::from_value_using(raw, OriginalTokenValue::String(&issued), &a).unwrap();
        assert!(matches!(literal.value(), OriginalTokenValue::String(value) if value == issued));
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (fixed + literal.raw_storage().capacity() + issued.len()));
        drop(literal);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn original_interpolation_segments_reuse_only_the_identical_issued_text() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let fixed = size_of::<Payload>() + 2 * size_of::<usize>();
        let cases = [
            ("\"front [", OriginalTokenValue::InterpBegin("front "), "InterpBegin", "front "),
            ("]caf\u{e9}[", OriginalTokenValue::InterpPart("caf\u{e9}"), "InterpPart", "caf\u{e9}"),
            ("]tail\"", OriginalTokenValue::InterpEnd("tail"), "InterpEnd", "tail"),
        ];
        for (raw, issued, kind, expected) in cases {
            let original = OriginalLiteralData::from_value_with_mode_using(
                raw.to_owned(), issued, OriginalStringMode::Normal, &a,
            ).unwrap();
            let clone = original.clone();
            assert_eq!(original.raw(), raw);
            assert_eq!(original.kind(), kind);
            assert_eq!(original.string_mode(), OriginalStringMode::Normal);
            assert!(clone.same_owner(&original));
            let text = match clone.value() {
                OriginalTokenValue::InterpBegin(text) | OriginalTokenValue::InterpPart(text)
                    | OriginalTokenValue::InterpEnd(text) => text,
                _ => panic!("actual interpolation VALUE kind changed"),
            };
            assert_eq!(text, expected);
            assert_eq!(text.as_ptr(), original.raw()[1..].as_ptr());
            assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (fixed + original.raw_storage().capacity()));
            drop(original);
            assert!(used.load(Ordering::Acquire) > crate::SettingChargeCounter::root_allocation_bytes(), "last occurrence alias retains the shared raw text");
            drop(clone);
            assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
        }

        // A value supplied by the real lexer is independent of spelling:
        // neither an escaped segment nor a wide spelling may guess a slice.
        let escaped = OriginalLiteralData::from_value_with_mode_using(
            "\"a\\tb[".to_owned(), OriginalTokenValue::InterpBegin("a\tb"), OriginalStringMode::Normal, &a,
        ).unwrap();
        assert!(matches!(escaped.value(), OriginalTokenValue::InterpBegin("a\tb")));
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (fixed + escaped.raw_storage().capacity() + "a\tb".len()));
        drop(escaped);
        let wide_raw = format!("]{}tail\"", "w".repeat(256));
        let wide = OriginalLiteralData::from_value_with_mode_using(
            wide_raw, OriginalTokenValue::InterpEnd("tail"), OriginalStringMode::Raw, &a,
        ).unwrap();
        assert!(matches!(wide.value(), OriginalTokenValue::InterpEnd("tail")));
        assert_eq!(wide.string_mode(), OriginalStringMode::Raw);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (fixed + wide.raw_storage().capacity() + 4));
        drop(wide);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
}

#[cfg(test)]
mod batch_page_controls {
    use super::*;
    use std::sync::atomic::{Ordering};

    fn literal(raw: &str, value: i32, a: &SettingAdmission<'_>) -> OriginalLiteralData {
        OriginalLiteralData::from_value_using(raw.to_owned(), OriginalTokenValue::Int(value), a).unwrap()
    }

    #[test]
    fn original_literal_batch_adopts_long_alias_without_cooked_side_storage() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let issued = "\u{00e9}".repeat(170);
        let mut raw = String::with_capacity(issued.len() + 2);
        raw.push('"');
        raw.push_str(&issued);
        raw.push('"');
        let long = OriginalLiteralData::from_value_using(
            raw, OriginalTokenValue::String(&issued), &a,
        ).unwrap();
        let pointer = long.raw().as_ptr();
        let mut rows = [Some(long), Some(literal("1", 1, &a)),
            Some(literal("2", 2, &a)), Some(literal("3", 3, &a))];
        let raw_bytes = rows.iter().flatten().map(|row| row.raw_storage().capacity()).sum::<usize>();
        OriginalLiteralData::pack_delivery_batch_using(&mut rows, &a).unwrap();
        let long = rows[0].take().unwrap();
        let LiteralStorage::Page(page) = &long.owner().storage else { panic!("actual batch page") };
        assert!(page.cooked.is_empty());
        let OriginalTokenValue::String(value) = long.value() else { panic!("actual String") };
        assert_eq!(value, issued);
        assert_eq!(long.raw().as_ptr(), pointer);
        assert_eq!(value.as_ptr(), long.raw()[1..].as_ptr());
        assert!(!long.same_owner(rows[1].as_ref().unwrap()));
        assert_eq!(used.load(Ordering::Acquire),
            crate::SettingChargeCounter::root_allocation_bytes() + (size_of::<Payload>() + 2 * size_of::<usize>() + 4 * size_of::<PackedBatchValue>() + raw_bytes));
        drop((rows,long));
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn packed_literal_raw_owner_keeps_spare_capacity_and_zero_length_allocations() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let make = |text: &str, capacity| {
            let mut raw = String::with_capacity(capacity);
            raw.push_str(text);
            Some(OriginalLiteralData::from_value_using(raw, OriginalTokenValue::Int(1), &a).unwrap())
        };
        let mut rows = [make("Ã©", 128), make("", 64), make("", 0), make("0", 9)];
        let before = rows.each_ref().map(|row| {
            let raw = row.as_ref().unwrap().raw_storage();
            (raw.as_ptr(), raw.capacity())
        });
        OriginalLiteralData::pack_delivery_batch_using(&mut rows, &a).unwrap();
        let page = rows[0].as_ref().unwrap().page_storage_identity().unwrap();
        for (i, row) in rows.iter().enumerate() {
            let row = row.as_ref().unwrap();
            let raw = row.raw_storage();
            assert_eq!((raw.as_ptr(), raw.capacity()), before[i]);
            assert_eq!(row.page_storage_identity(), Some(page));
        }
        let keep = rows[0].take().unwrap();
        drop(rows);
        let expected = size_of::<Payload>() + 2 * size_of::<usize>()
            + 4 * size_of::<PackedBatchValue>() + before.iter().map(|&(_, capacity)| capacity).sum::<usize>();
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (expected));
        std::thread::scope(|scope| scope.spawn(|| assert_eq!(keep.raw(), "Ã©")).join().unwrap());
        std::thread::scope(|scope| scope.spawn(move || drop(keep)).join().unwrap());
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn packed_literal_raw_geometry_checks_both_wide_fields_without_allocating() {
        assert_eq!(PackedBatchValue::raw_geometry(2, 128), Some((2, 128)));
        assert_eq!(PackedBatchValue::raw_geometry(2, 1), None);
        assert_eq!(PackedBatchValue::raw_geometry(1024, 1024), Some((1024, 1024)));
        assert_eq!(PackedBatchValue::raw_geometry(1, 1025), None);
        #[cfg(target_pointer_width = "64")]
        {
            let wide = u32::MAX as usize + 1;
            assert_eq!(PackedBatchValue::raw_geometry(0, wide), None);
            assert_eq!(PackedBatchValue::raw_geometry(wide, wide), None);
        }
    }

    #[test]
    fn packed_literal_metadata_preserves_maximal_alias_and_cooked_slot() {
        let fixed = crate::SettingChargeCounter::root_allocation_bytes();
        let used = crate::SettingChargeCounter::try_new(fixed).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut raw = String::with_capacity(MAX_ROW_TEXT_BYTES);
        raw.push_str(&"a".repeat(255));
        raw.push_str("é");
        raw.push_str(&"b".repeat(254));
        let ptr = raw.as_ptr();
        let make = |raw, value| OriginalLiteralData::from_value_using(raw,value,&a).unwrap();
        let mut rows = [
            Some(make(raw, OriginalTokenValue::String("é"))),
            Some(make("n".into(), OriginalTokenValue::Float(f32::from_bits(0xffc01234)))),
            Some(make("z".into(), OriginalTokenValue::Float(-0.0))),
            Some(make("m".into(), OriginalTokenValue::Int(i32::MIN))),
        ];
        OriginalLiteralData::pack_delivery_batch_using(&mut rows,&a).unwrap();
        let data = rows[0].as_ref().unwrap();
        let LiteralStorage::Page(page) = &data.owner().storage else { panic!("actual compact batch"); };
        let row = &page.rows[0];
        assert_eq!(row.value_in_raw(),[255,255]);
        assert_eq!(row.raw_view().as_ptr(),ptr);
        assert_eq!(row.raw_capacity(),MAX_ROW_TEXT_BYTES);
        assert_eq!(rows[1].as_ref().unwrap().payload().scalar_bits,0xffc01234);
        assert_eq!(rows[2].as_ref().unwrap().payload().scalar_bits,(-0.0f32).to_bits());
        assert_eq!(rows[3].as_ref().unwrap().payload().scalar_bits,i32::MIN as u32);
        drop(rows);

        let mut cooked: Vec<_> = (0..PAGE_ROWS).map(|i|
            Some(make("raw".into(),OriginalTokenValue::String(if i+1==PAGE_ROWS{"last"}else{"cooked"})))).collect();
        OriginalLiteralData::pack_delivery_batch_using(&mut cooked,&a).unwrap();
        let last = cooked.last().unwrap().as_ref().unwrap();
        let LiteralStorage::Page(page) = &last.owner().storage else { panic!("actual cooked batch"); };
        assert_eq!(page.rows[PAGE_ROWS-1].scalar_or_text() as usize,PAGE_ROWS);
        assert_eq!(last.payload().text,"last");
        drop(cooked);
        assert_eq!(used.load(Ordering::Acquire),fixed);
    }

    #[test]
    fn original_literal_batch_page_moves_existing_text_and_funds_one_escaped_page() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut rows: Vec<_> = (0..PAGE_ROWS).map(|_| Some(literal("7", 7, &a))).collect();
        let first = rows[0].as_ref().unwrap().raw().as_ptr();
        let raw_capacity: usize = rows.iter().flatten().map(|data| data.raw_storage().capacity()).sum();
        let before = used.load(Ordering::Acquire);
        let scratch = size_of::<PendingPage>() + size_of::<[usize; PAGE_ROWS]>();
        // At most the old allocations and the bounded stack can overlap.
        // A second funded page while the old wrappers live would fail.
        let full = SettingAdmission::new(&used, before, &|| Ok(()));
        OriginalLiteralData::pack_delivery_batch_using(&mut rows, &full).unwrap();
        assert_eq!(used.load(Ordering::Acquire), before);
        assert!(!full.is_stopped(), "unavailable optimization scratch is not an operation error");
        let tight = SettingAdmission::new(&used, before + scratch, &|| Ok(()));
        OriginalLiteralData::pack_delivery_batch_using(&mut rows, &tight).unwrap();
        let keep = rows[0].take().unwrap();
        let sibling = rows[1].as_ref().unwrap();
        assert!(std::ptr::eq(keep.owner(), sibling.owner()));
        assert!(!keep.same_owner(sibling), "equal values remain distinct occurrences");
        assert!(matches!(keep.value(), OriginalTokenValue::Int(7)));
        assert_eq!(keep.raw().as_ptr(), first, "the original String allocation moved");
        assert!(keep.same_owner(&keep.clone()));
        let expected = size_of::<Payload>() + 2 * size_of::<usize>()
            + PAGE_ROWS * size_of::<PackedBatchValue>() + raw_capacity;
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (expected));
        assert!(expected < before);
        drop(rows);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (expected));
        let mut payload = 0;
        keep.visit_storage(|_, _, capacity| payload += capacity);
        assert!(payload >= expected, "a detached row reports all retained page storage");
        drop(keep);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn original_literal_batch_rows_move_only_actual_cooked_boxes_and_keep_exact_values() {
        #[allow(dead_code)]
        enum PreviousStorage { Single(LiteralValue), Page(Vec<LiteralValue>) }
        assert_eq!(size_of::<LiteralStorage>(), size_of::<PreviousStorage>());
        #[cfg(target_pointer_width = "64")]
        assert_eq!(size_of::<PackedBatchValue>(), 16);

        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut rows = [
            OriginalLiteralData::from_value_using("-0".into(), OriginalTokenValue::Float(-0.0), &a),
            OriginalLiteralData::from_value_using("\"aÃ©\"".into(), OriginalTokenValue::String("aÃ©"), &a),
            OriginalLiteralData::from_value_with_mode_using("raw".into(), OriginalTokenValue::InterpPart("changed"), OriginalStringMode::Raw, &a),
            OriginalLiteralData::from_value_using("''".into(), OriginalTokenValue::Resource(""), &a),
        ].map(|value| Some(value.unwrap()));
        let raw = rows.each_ref().map(|row| row.as_ref().unwrap().raw().as_ptr());
        let cooked = rows[2].as_ref().unwrap().payload().text.as_ptr();
        let raw_bytes = rows.iter().flatten().map(|row| row.raw_storage().capacity()).sum::<usize>();

        OriginalLiteralData::pack_delivery_batch_using(&mut rows, &a).unwrap();
        let [scalar, string, part, empty] = rows.each_ref().map(|row| row.as_ref().unwrap());
        assert!(matches!(scalar.value(), OriginalTokenValue::Float(value) if value.to_bits()==(-0.0f32).to_bits()));
        assert!(matches!(string.value(), OriginalTokenValue::String("aÃ©")));
        assert!(matches!(part.value(), OriginalTokenValue::InterpPart("changed")));
        assert_eq!(part.string_mode(), OriginalStringMode::Raw);
        assert_eq!(part.payload().text.as_ptr(), cooked);
        assert!(matches!(empty.value(), OriginalTokenValue::Resource("")));
        assert_eq!(rows.each_ref().map(|row| row.as_ref().unwrap().raw().as_ptr()), raw);
        assert_eq!(scalar.page_storage_identity(), part.page_storage_identity());
        let expected = size_of::<Payload>() + 2 * size_of::<usize>() + 4 * size_of::<PackedBatchValue>()
            + size_of::<Box<str>>() + raw_bytes + "changed".len();
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (expected));

        let detached = rows[0].take().unwrap();
        drop(rows);
        let mut saw_cooked = false;
        detached.visit_storage(|address, len, capacity| {
            if address == cooked as usize {
                assert_eq!((len, capacity), ("changed".len(), "changed".len()));
                saw_cooked = true;
            }
        });
        assert!(saw_cooked, "a detached row still funds a sibling's exact box");
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (expected));
        drop(detached);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn original_literal_batch_page_text_bound_keeps_separate_escaped_owners() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut rows: Vec<_> = (0..16).map(|_| {
            let raw = String::from_utf8(vec![b'6'; MAX_ROW_TEXT_BYTES]).unwrap();
            assert_eq!(raw.capacity(), MAX_ROW_TEXT_BYTES);
            Some(OriginalLiteralData::from_value_using(raw, OriginalTokenValue::Int(6), &a).unwrap())
        }).collect();
        OriginalLiteralData::pack_delivery_batch_using(&mut rows, &a).unwrap();
        let first = rows[0].take().unwrap();
        let next = rows[8].take().unwrap();
        let last_in_first = rows[7].as_ref().unwrap();
        assert_eq!(first.page_storage_identity(), last_in_first.page_storage_identity());
        assert_ne!(first.page_storage_identity(), next.page_storage_identity());
        let first_bytes = first.owner().credit.bytes();
        let next_bytes = next.owner().credit.bytes();
        drop(rows);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (first_bytes + next_bytes));
        drop(next);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (first_bytes));
        drop(first);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn original_literal_batch_page_preserves_shared_wide_and_foreign_rows() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let foreign = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let b = SettingAdmission::new(&foreign, 1 << 20, &|| Ok(()));
        let retained = literal("4", 4, &a);
        let wide = literal(&"5".repeat(MAX_ROW_TEXT_BYTES + 1), 5, &a);
        let wide_raw = wide.raw().as_ptr();
        let mut rows = vec![Some(retained.clone()), Some(wide), Some(literal("9", 9, &b))];
        assert_eq!(OriginalLiteralData::pack_delivery_batch_using(&mut rows, &a).unwrap_err().kind(), io::ErrorKind::InvalidInput);
        drop(rows.pop());
        rows.extend((0..PAGE_ROWS).map(|_| Some(literal("8", 8, &a))));
        OriginalLiteralData::pack_delivery_batch_using(&mut rows, &a).unwrap();
        assert!(rows[0].as_ref().unwrap().same_owner(&retained));
        assert!(matches!(&rows[1].as_ref().unwrap().owner().storage, LiteralStorage::Single(_)));
        assert_eq!(rows[1].as_ref().unwrap().raw().as_ptr(), wide_raw);
        assert!(matches!(&rows[2].as_ref().unwrap().owner().storage, LiteralStorage::Page(_)));
        drop((rows, retained));
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
        assert_eq!(foreign.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn original_literal_batch_page_failure_releases_partial_stage_and_preserves_first_io() {
        use std::cell::Cell;
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut rows: Vec<_> = (0..PAGE_ROWS).map(|_| Some(literal("6", 6, &a))).collect();
        let calls = Cell::new(0);
        let poll = || {
            let next = calls.get() + 1;
            calls.set(next);
            if next == 7 { Err(io::Error::from_raw_os_error(1450)) } else { Ok(()) }
        };
        let fault = SettingAdmission::new(&used, 1 << 20, &poll);
        let failure = OriginalLiteralData::pack_delivery_batch_using(&mut rows, &fault).unwrap_err();
        assert_eq!(failure.raw_os_error(), Some(1450));
        assert!(rows.iter().any(Option::is_none), "a real transfer was in progress");
        drop(rows);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
}
