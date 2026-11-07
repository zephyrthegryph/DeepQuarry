//! Neutral facts on the SAME primary product. No public constructor, Weak,
//! parser, body cache, current-source grant, or independently rebased roster.
use super::*;
use std::{alloc::{alloc,Layout},io,mem,ops::Range,ptr::NonNull,sync::Arc};

type LiteralRow = (Span, crate::OriginalLiteralData);
type BorrowedLiteralRow<'a> = (Span, crate::OriginalLiteralRef<'a>);
use crate::original_literal_data::OriginalLiteralOwner;
use crate::original_literal_projection::{ProjectedLiteral, ProjectedLiteralRef};
const LITERAL_PAGE_LEN: usize = 256;
const DIRECTORY_CHUNK_LEN: usize = 64;

// Common literal spans are page-relative, independently of the absolute
// source extent. The high bit distinguishes exact page-local wide ordinals.
const WIDTH_BITS: u32 = 11;
const MAX_WIDTH: usize = (1 << WIDTH_BITS) - 1;
const WIDE_BIT: u32 = 1 << 31;
const MAX_START_DELTA: usize = ((WIDE_BIT - 1) >> WIDTH_BITS) as usize;
#[cfg(test)]
const LITERAL_ROW_BYTES: usize = mem::size_of::<u32>() + mem::size_of::<crate::OriginalLiteralData>();

struct LiteralPage {
    body:[u64;4],
    // Split columns avoid per-row padding without moving or copying any
    // issued literal backing. Both allocations die before their shared credit.
    spans: Vec<u32>,
    data: LiteralPageData,
    start_base: usize,
    span_credit: crate::SettingRootLease,
    wide: Vec<Span>,
    wide_credit: Option<crate::SettingRootLease>,
}
struct DenseLiteralData {
    rows: Vec<crate::OriginalLiteralData>,
    credit: crate::SettingRootLease,
}
struct CompactLiteralData {
    codes: Vec<u32>,
    owners: Vec<OriginalLiteralOwner>,
    wide: Vec<crate::OriginalLiteralData>,
    projections: Option<Box<Vec<ProjectedLiteral>>>,
    credit: crate::SettingRootLease,
}
enum LiteralPageData {
    Dense(DenseLiteralData),
    Compact(CompactLiteralData),
    Projected(ProjectedLiteralData),
}

struct ProjectedLiteralData{
 codes:Vec<u16>,
 full:Vec<crate::OriginalLiteralData>,
 descriptors:Vec<crate::original_literal_projection::ProjectedLiteral>,
 credit:crate::SettingRootLease,
}
const PROJECTED_BIT:u16=1<<15;
const WIDE_LITERAL_ORDINAL: u32 = 0x00ff_ffff;
const PROJECTED_COMPACT_ORDINAL: u32 = WIDE_LITERAL_ORDINAL - 1;
const OWNER_CACHE_LEN: usize = 64;
struct LiteralPagePlan {
    codes: [u32; LITERAL_PAGE_LEN],
    // A bounded reuse hint, never identity. It stores input row + 1.
    recent: [u16; OWNER_CACHE_LEN],
    owners: usize,
    wide: usize,
}
impl LiteralPagePlan {
    fn new(rows: &[crate::OriginalLiteralData]) -> Self {
        let mut plan = Self {
            codes: [0; LITERAL_PAGE_LEN], recent: [0; OWNER_CACHE_LEN], owners: 0, wide: 0,
        };
        let mut previous = None;
        for (index, data) in rows.iter().enumerate() {
            let data = data.as_view();
            if data.ordinal() >= PROJECTED_COMPACT_ORDINAL as usize {
                plan.codes[index] = (WIDE_LITERAL_ORDINAL << 8) | plan.wide as u32;
                plan.wide += 1;
                continue;
            }
            let key = data.owner_key();
            let bucket = ((key >> 4) ^ (key >> 12)) % OWNER_CACHE_LEN;
            let cached = usize::from(plan.recent[bucket]).checked_sub(1);
            let owner = previous.filter(|&(last, _)| last == key).map(|(_, owner)| owner)
                .or_else(|| cached.filter(|&last| rows[last].as_view().owner_key() == key)
                    .map(|last| plan.codes[last] & 0xff))
                .unwrap_or_else(|| {
                    let next = plan.owners as u32;
                    plan.owners += 1;
                    next
                });
            plan.recent[bucket] = u16::try_from(index + 1).expect("bounded literal row");
            plan.codes[index] = ((data.ordinal() as u32) << 8) | owner;
            previous = Some((key, owner));
        }
        plan
    }
}
fn projected_ref<'a>(
    descriptor: ProjectedLiteral,
    span: Span,
    ordinal: usize,
    loan: Option<ProjectionLoan<'a>>,
    owner: Option<&'a crate::OriginalLiteralProjectionOwner>,
) -> crate::OriginalLiteralRef<'a> {
    let raw = loan.and_then(|loan| {
        loan.source.get(span.start.checked_sub(loan.origin)?..span.end.checked_sub(loan.origin)?)
    });
    crate::OriginalLiteralRef::from_projection(ProjectedLiteralRef {
        descriptor, raw, raw_capacity: 0,
        owner: owner.expect("projected page has actual output DATA"),
        ordinal,
    })
}

impl LiteralPageData {
    fn get<'a>(&'a self,index:usize,span:Span,ordinal:usize,loan:Option<ProjectionLoan<'a>>,owner:Option<&'a crate::OriginalLiteralProjectionOwner>)->crate::OriginalLiteralRef<'a>{
        match self {
            Self::Projected(data)=>{
             let code=data.codes[index];
             if code&PROJECTED_BIT==0{return data.full[code as usize].as_view()}
             let descriptor=data.descriptors[(code&!PROJECTED_BIT)as usize];
             projected_ref(descriptor, span, ordinal, loan, owner)
            },
            Self::Dense(data) => data.rows[index].as_view(),
            Self::Compact(data) => {
                let code = data.codes[index];
                let key = (code & 0xff) as usize;
                let packed_ordinal = code >> 8;
                match packed_ordinal {
                    WIDE_LITERAL_ORDINAL => data.wide[key].as_view(),
                    PROJECTED_COMPACT_ORDINAL => projected_ref(
                        data.projections.as_ref().expect("issued compact descriptors")[key],
                        span, ordinal, loan, owner,
                    ),
                    _ => data.owners[key].at(packed_ordinal as usize),
                }
            }
        }
    }

    fn reservation_bytes(&self) -> usize {
        match self {
            Self::Dense(data) => data.credit.bytes(),
            Self::Compact(data) => data.credit.bytes(),
            Self::Projected(data)=>data.credit.bytes(),
        }
    }

    fn visit_storage(&self, visit: &mut impl FnMut(usize, usize, usize)) {
        fn buffer<T>(rows: &Vec<T>, visit: &mut impl FnMut(usize, usize, usize)) {
            if rows.capacity() != 0 {
                visit(rows.as_ptr() as usize, rows.len() * mem::size_of::<T>(),
                    rows.capacity() * mem::size_of::<T>());
            }
        }
        match self {
            Self::Dense(data) => buffer(&data.rows, visit),
            Self::Projected(data)=>{buffer(&data.codes,visit);buffer(&data.full,visit);buffer(&data.descriptors,visit)},
            Self::Compact(data) => {
                buffer(&data.codes, visit);
                buffer(&data.owners, visit);
                buffer(&data.wide, visit);
                if let Some(projections) = &data.projections {
                    let control = mem::size_of::<Vec<ProjectedLiteral>>();
                    visit(projections.as_ref() as *const _ as usize, control, control);
                    buffer(projections, visit);
                }
            }
        }
    }

    // Only after all reservations and allocations have succeeded do the
    // original payload owners move. There are no source pulls or token changes.
    fn settle_full_using(&mut self, a: &crate::SettingAdmission<'_>) -> io::Result<()> {
        let Self::Dense(dense) = self else { return Ok(()) };
        assert_eq!(dense.rows.len(), LITERAL_PAGE_LEN);
        if !a.matches_lease_domain(&dense.credit) { return Err(io::ErrorKind::InvalidInput.into()); }
        let Some(_work) = a.try_reserve_optimization(mem::size_of::<LiteralPagePlan>())
            .map_err(|proxy| a.take_operational_error().unwrap_or(proxy))? else {
            return Ok(());
        };
        let plan = LiteralPagePlan::new(&dense.rows);
        let codes_layout = Layout::array::<u32>(LITERAL_PAGE_LEN).expect("bounded codes");
        let owner_layout = Layout::array::<OriginalLiteralOwner>(plan.owners).expect("bounded owners");
        let wide_layout = Layout::array::<crate::OriginalLiteralData>(plan.wide).expect("bounded wide literals");
        let bytes = codes_layout.size() + owner_layout.size() + wide_layout.size();
        if bytes >= dense.credit.bytes() { return Ok(()); }
        let Some(credit) = a.try_reserve_optimization(bytes)
            .map_err(|proxy| a.take_operational_error().unwrap_or(proxy))? else { return Ok(()); };
        let mut compact = CompactLiteralData {
            codes: alloc_funded_literal_rows(LITERAL_PAGE_LEN, codes_layout)?,
            owners: alloc_funded_literal_rows(plan.owners, owner_layout)?,
            wide: alloc_funded_literal_rows(plan.wide, wide_layout)?,
            projections: None,
            credit,
        };
        a.checkpoint().map_err(|proxy| a.take_operational_error().unwrap_or(proxy))?;
        compact.codes.extend_from_slice(&plan.codes);
        for (value, code) in dense.rows.drain(..).zip(plan.codes) {
            let key = (code & 0xff) as usize;
            if code >> 8 == WIDE_LITERAL_ORDINAL {
                debug_assert_eq!(key, compact.wide.len());
                compact.wide.push(value);
            } else if key == compact.owners.len() {
                compact.owners.push(value.into_bank_owner());
            } else {
                debug_assert!(key < compact.owners.len());
                debug_assert_eq!(value.as_view().owner_key(),
                    compact.owners[key].at(value.as_view().ordinal()).owner_key());
                drop(value);
            }
        }
        debug_assert_eq!(compact.owners.len(), plan.owners);
        debug_assert_eq!(compact.wide.len(), plan.wide);
        // The old dense allocation drops before returning its own credit.
        drop(mem::replace(self, Self::Compact(compact)));
        Ok(())
    }
}

struct LiteralDirectoryChunk {
    pages: Vec<LiteralPage>,
    credit: crate::SettingRootLease,
}
struct LiteralPages {
    chunks: Vec<LiteralDirectoryChunk>,
    len: usize,
    directory_credit: crate::SettingRootLease,
}

fn allocate_literal_rows<T>(capacity: usize, a: &crate::SettingAdmission<'_>)
    -> io::Result<(Vec<T>, crate::SettingRootLease)>
{
    let layout = Layout::array::<T>(capacity).map_err(|_| io::ErrorKind::OutOfMemory)?;
    assert_ne!(layout.size(), 0);
    let credit = a.reserve(layout.size()).map_err(|e| a.take_operational_error().unwrap_or(e))?;
    Ok((alloc_funded_literal_rows(capacity, layout)?, credit))
}

fn alloc_funded_literal_rows<T>(capacity: usize, layout: Layout) -> io::Result<Vec<T>> {
    debug_assert_eq!(Layout::array::<T>(capacity).ok(), Some(layout));
    if capacity == 0 { return Ok(Vec::new()); }
    let raw = NonNull::new(unsafe { alloc(layout) }.cast::<T>())
        .ok_or(io::ErrorKind::OutOfMemory)?;
    // SAFETY: Global owns this exact, nonempty layout. No rows are initialized.
    Ok(unsafe { Vec::from_raw_parts(raw.as_ptr(), 0, capacity) })
}

impl LiteralPage {
 #[cfg(test)]
 fn get(&self,index:usize)->Option<BorrowedLiteralRow<'_>>{self.get_data(index,0,None,None)}
 fn settle_body_projection(&mut self,source:&str,base:usize,owner:&crate::OriginalLiteralProjectionOwner,a:&crate::SettingAdmission<'_>)->io::Result<Option<(usize,usize,usize,usize)>>{
  if matches!(self.data,LiteralPageData::Projected(_))
   || matches!(&self.data,LiteralPageData::Compact(data) if data.projections.is_some())
  {return Ok(None)}
  let Some(_scratch)=a.try_reserve_optimization(LITERAL_PAGE_LEN+LITERAL_PAGE_LEN*std::mem::size_of::<u16>()).map_err(|e|a.take_operational_error().unwrap_or(e))?else{return Ok(None)};
  let mut candidates=[false;LITERAL_PAGE_LEN];
  let mut references=[0u16;LITERAL_PAGE_LEN];
  if let LiteralPageData::Compact(data)=&self.data{
   for code in &data.codes{if code>>8!=WIDE_LITERAL_ORDINAL{references[(code&255)as usize]+=1;}}
  }
  let mut count=0usize;let mut released=0usize;
  for at in 0..self.spans.len(){
   a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
   if self.body[at/64]&(1u64<<(at%64))==0{continue}
   if let LiteralPageData::Compact(data)=&self.data{
    let code=data.codes[at];if code>>8!=WIDE_LITERAL_ORDINAL&&references[(code&255)as usize]!=1{continue}
   }
   let(span,data)=self.get_data(at,base,None,Some(owner)).ok_or(io::ErrorKind::InvalidData)?;
   if data.raw()?!=source.get(span.range()).ok_or(io::ErrorKind::InvalidInput)?{return Err(io::ErrorKind::InvalidData.into())}
   if let Some((_,bytes))=data.projection_candidate(){candidates[at]=true;count+=1;released=released.checked_add(bytes).ok_or(io::ErrorKind::OutOfMemory)?;}
  }
  if count==0{return Ok(None)}
  let len=self.spans.len();
  let code_layout=Layout::array::<u16>(len).map_err(|_|io::ErrorKind::OutOfMemory)?;
  let full_layout=Layout::array::<crate::OriginalLiteralData>(len-count).map_err(|_|io::ErrorKind::OutOfMemory)?;
  let descriptor_layout=Layout::array::<crate::original_literal_projection::ProjectedLiteral>(count).map_err(|_|io::ErrorKind::OutOfMemory)?;
  let bytes=code_layout.size()+full_layout.size()+descriptor_layout.size();
  let old_rows=self.data.reservation_bytes();
  if bytes>=old_rows.saturating_add(released){return Ok(None)}
  let Some(credit)=a.try_reserve_optimization(bytes).map_err(|e|a.take_operational_error().unwrap_or(e))?else{return Ok(None)};
  let mut next=ProjectedLiteralData{
   codes:alloc_funded_literal_rows(len,code_layout)?,
   full:alloc_funded_literal_rows(len-count,full_layout)?,
   descriptors:alloc_funded_literal_rows(count,descriptor_layout)?,
   credit,
  };
  for at in 0..len{
   let(_,data)=self.get_data(at,base,None,Some(owner)).ok_or(io::ErrorKind::InvalidData)?;
   if candidates[at]{
    let (descriptor,_)=data.projection_candidate().ok_or(io::ErrorKind::InvalidData)?;
    next.codes.push(PROJECTED_BIT|u16::try_from(next.descriptors.len()).map_err(|_|io::ErrorKind::InvalidData)?);
    next.descriptors.push(descriptor);
   }else{
    next.codes.push(u16::try_from(next.full.len()).map_err(|_|io::ErrorKind::InvalidData)?);
    next.full.push(data.detach_using(a)?);
   }
  }
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  // Old physical DATA and row buffers die before returning their real leases.
  // New columns are already complete, paid, and no operation below can fail.
  drop(mem::replace(&mut self.data,LiteralPageData::Projected(next)));
  Ok(Some((count,released,old_rows,bytes)))
 }
    /// Reuse the original compact owner bank. A mixed bank entry keeps its
    /// existing Arc and any Full rows, while individual raw allocations die.
    fn settle_packed_body_projection(
        &mut self,
        source: &str,
        a: &crate::SettingAdmission<'_>,
    ) -> io::Result<Option<(usize, usize, usize, usize)>> {
        if self.body.iter().all(|word| *word == 0) {
            return Ok(None);
        }
        self.data.settle_full_using(a)?;
        let LiteralPageData::Compact(compact) = &self.data else { return Ok(None) };
        if compact.projections.is_some() {
            return Ok(None);
        }

        #[derive(Clone, Copy, Default)]
        struct Group {
            references: u32,
            eligible: u32,
            duplicates: bool,
            raw_bytes: usize,
            owner_bytes: usize,
            owner_mask: u32,
        }
        let scratch_bytes = mem::size_of::<[Group; LITERAL_PAGE_LEN]>()
            + mem::size_of::<[Option<ProjectedLiteral>; LITERAL_PAGE_LEN]>();
        let Some(_scratch) = a.try_reserve_optimization(scratch_bytes)
            .map_err(|error| a.take_operational_error().unwrap_or(error))? else {
            return Ok(None);
        };
        let mut groups = [Group::default(); LITERAL_PAGE_LEN];
        let mut candidates = [None; LITERAL_PAGE_LEN];
        for (index, &code) in compact.codes.iter().enumerate() {
            if index % 32 == 0 {
                a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
            }
            let ordinal = code >> 8;
            // Packed payloads have at most 32 physical rows. Wide codes are
            // never packed, and shared standalone occurrences are ineligible.
            if ordinal >= u32::BITS {
                continue;
            }
            let bank = (code & 255) as usize;
            let group = &mut groups[bank];
            let bit = 1 << ordinal;
            group.duplicates |= group.references & bit != 0;
            group.references |= bit;
            if self.body[index / 64] & (1 << (index % 64)) == 0 {
                continue;
            }
            let data = compact.owners[bank].at(ordinal as usize);
            let Some((descriptor, raw_bytes, owner_bytes, owner_mask)) = data.packed_projection_candidate() else {
                continue;
            };
            let span = self.span_at(index).ok_or(io::ErrorKind::InvalidData)?;
            if data.raw()? != source.get(span.range()).ok_or(io::ErrorKind::InvalidData)? {
                return Err(io::ErrorKind::InvalidData.into());
            }
            candidates[index] = Some(descriptor);
            group.eligible |= bit;
            group.raw_bytes += raw_bytes;
            group.owner_bytes = owner_bytes;
            group.owner_mask = owner_mask;
        }
        let mut count = 0;
        let mut gross = 0;
        for group in &mut groups {
            let rows = group.eligible.count_ones() as usize;
            let bytes = if group.eligible == group.references {
                group.owner_bytes
            } else {
                group.raw_bytes
            };
            let incomplete_retirement = group.eligible == group.references
                && group.eligible != group.owner_mask;
            if group.duplicates || incomplete_retirement || bytes <= rows * mem::size_of::<ProjectedLiteral>() {
                group.eligible = 0;
            } else {
                count += rows;
                gross += bytes;
            }
        }
        let layout = Layout::array::<ProjectedLiteral>(count).map_err(|_| io::ErrorKind::OutOfMemory)?;
        let control = Layout::new::<Vec<ProjectedLiteral>>();
        let metadata_bytes = layout.size() + control.size();
        // Include the optional pointer carried by the compact representation.
        if gross <= metadata_bytes + mem::size_of::<Option<Box<Vec<ProjectedLiteral>>>>() {
            return Ok(None);
        }
        let Some(mut credit) = a.try_reserve_optimization(metadata_bytes)
            .map_err(|error| a.take_operational_error().unwrap_or(error))? else {
            return Ok(None);
        };
        let mut descriptors = alloc_funded_literal_rows(count, layout)?;
        for (index, candidate) in candidates.iter().enumerate() {
            let code = compact.codes[index];
            let group = &groups[(code & 255) as usize];
            if let Some(descriptor) = candidate {
                if group.eligible & (1 << (code >> 8)) != 0 {
                    descriptors.push(*descriptor);
                }
            }
        }
        debug_assert_eq!(descriptors.len(), count);
        let pointer = NonNull::new(unsafe { alloc(control) }.cast::<Vec<ProjectedLiteral>>())
            .ok_or(io::ErrorKind::OutOfMemory)?;
        // SAFETY: the exact nonempty Global Box layout and descriptor buffer
        // have been funded. The initialized Vec moves once into its Box.
        let boxed = unsafe {
            pointer.as_ptr().write(descriptors);
            Box::from_raw(pointer.as_ptr())
        };
        let LiteralPageData::Compact(compact) = &mut self.data else { unreachable!() };
        let old_bytes = compact.credit.bytes();
        a.absorb(&mut compact.credit, &mut credit)?;
        compact.projections = Some(boxed);

        let mut released = 0;
        for (bank, group) in groups.iter().enumerate().filter(|(_, group)| group.eligible != 0) {
            // Either preflight fails with this entry untouched, or physical
            // withdrawal succeeds and all its old codes are replaced immediately.
            released += compact.owners[bank].withdraw_packed_using(
                group.eligible, group.eligible == group.references, a,
            )?;
            let mut descriptor_index = 0;
            for (index, candidate) in candidates.iter().enumerate() {
                let code = compact.codes[index];
                let old_bank = (code & 255) as usize;
                let ordinal = code >> 8;
                if candidate.is_none() {
                    continue;
                }
                if ordinal == PROJECTED_COMPACT_ORDINAL {
                    // Already projected by an earlier bank. Its descriptor
                    // still occupies this ordinal in the common column.
                    descriptor_index += 1;
                } else if groups[old_bank].eligible & (1 << ordinal) != 0 {
                    if old_bank == bank {
                        compact.codes[index] = (PROJECTED_COMPACT_ORDINAL << 8)
                            | descriptor_index as u32;
                    }
                    descriptor_index += 1;
                }
            }
        }
        debug_assert_eq!(released, gross);
        Ok(Some((count, released, old_bytes, compact.credit.bytes())))
    }

    fn new(start_base: usize, a: &crate::SettingAdmission<'_>) -> io::Result<Self> {
        let (spans, span_credit) = allocate_literal_rows(LITERAL_PAGE_LEN, a)?;
        let (rows, credit) = allocate_literal_rows(LITERAL_PAGE_LEN, a)?;
        let data = LiteralPageData::Dense(DenseLiteralData { rows, credit });
        Ok(Self { body:[0;4],spans, data, start_base, span_credit, wide: Vec::new(), wide_credit: None })
    }

    fn span_at(&self, index: usize) -> Option<Span> {
        let word = *self.spans.get(index)?;
        Some(if word & WIDE_BIT != 0 {
            self.wide[(word & !WIDE_BIT) as usize]
        } else {
            let start = self.start_base + (word >> WIDTH_BITS) as usize;
            Span::new(start, start + (word as usize & MAX_WIDTH))
        })
    }

    fn get_data<'a>(&'a self,index:usize,base:usize,loan:Option<ProjectionLoan<'a>>,owner:Option<&'a crate::OriginalLiteralProjectionOwner>)->Option<BorrowedLiteralRow<'a>>{
        let span = self.span_at(index)?;
        Some((span, self.data.get(index,span,base+index,loan,owner)))
    }

    fn push(&mut self, (span, data): LiteralRow, a: &crate::SettingAdmission<'_>) -> io::Result<()> {
        assert!(self.spans.len() < self.spans.capacity());
        let LiteralPageData::Dense(page) = &mut self.data else {
            return Err(io::ErrorKind::InvalidInput.into());
        };
        debug_assert_eq!(self.spans.len(), page.rows.len());
        debug_assert_eq!(self.spans.capacity(), page.rows.capacity());
        let delta = span.start.checked_sub(self.start_base).ok_or(io::ErrorKind::InvalidInput)?;
        let width = span.end - span.start;
        let word = if delta <= MAX_START_DELTA && width <= MAX_WIDTH {
            ((delta as u32) << WIDTH_BITS) | width as u32
        } else {
            if self.wide.len() == self.wide.capacity() {
                let capacity = self.wide.capacity().max(1) * 2;
                debug_assert!(capacity <= LITERAL_PAGE_LEN);
                let (mut rows, credit) = allocate_literal_rows(capacity, a)?;
                rows.append(&mut self.wide);
                drop(mem::replace(&mut self.wide, rows));
                self.wide_credit = Some(credit);
            }
            let index = u32::try_from(self.wide.len()).expect("wide ordinals fit one literal page");
            self.wide.push(span);
            WIDE_BIT | index
        };
        self.spans.push(word);
        page.rows.push(data);
        Ok(())
    }
}

impl LiteralPages {
    fn get<'a>(&'a self,index:usize,loan:Option<ProjectionLoan<'a>>,owner:Option<&'a crate::OriginalLiteralProjectionOwner>)->Option<BorrowedLiteralRow<'a>>{
        let page = index / LITERAL_PAGE_LEN;
        self.chunks.get(page / DIRECTORY_CHUNK_LEN)?.pages.get(page % DIRECTORY_CHUNK_LEN)?
            .get_data(index % LITERAL_PAGE_LEN,page*LITERAL_PAGE_LEN,loan,owner)
    }

    fn window(&self) -> OriginalLiteralRows<'_> {
        OriginalLiteralRows { storage: LiteralRowStorage::Pages(self), first: 0, last: self.len,loan:None,owner:None }
    }

    fn push(&mut self, row: LiteralRow, a: &crate::SettingAdmission<'_>) -> io::Result<()> {
        let len = self.len.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
        if self.len % LITERAL_PAGE_LEN == 0 {
            let mut page = LiteralPage::new(row.0.start, a)?;
            page.push(row, a)?;
            if self.chunks.last().is_none_or(|chunk| chunk.pages.len() == DIRECTORY_CHUNK_LEN) {
                let (pages, credit) = allocate_literal_rows(DIRECTORY_CHUNK_LEN, a)?;
                let replacement = if self.chunks.len() == self.chunks.capacity() {
                    let capacity = self.chunks.capacity().max(1).checked_mul(2)
                        .ok_or(io::ErrorKind::OutOfMemory)?;
                    Some(allocate_literal_rows(capacity, a)?)
                } else { None };
                self.settle_previous_using(a)?;
                if let Some((mut chunks, directory_credit)) = replacement {
                    chunks.append(&mut self.chunks);
                    drop(mem::replace(&mut self.chunks, chunks));
                    self.directory_credit = directory_credit;
                }
                self.chunks.push(LiteralDirectoryChunk { pages, credit });
            } else {
                self.settle_previous_using(a)?;
            }
            self.chunks.last_mut().expect("funded literal directory").pages.push(page);
        } else {
            self.chunks.last_mut().and_then(|chunk| chunk.pages.last_mut())
                .expect("funded literal page").push(row, a)?;
        }
        self.len = len;
        Ok(())
    }

    fn settle_previous_using(&mut self, a: &crate::SettingAdmission<'_>) -> io::Result<()> {
        if let Some(last) = self.chunks.last_mut().and_then(|chunk| chunk.pages.last_mut()) {
            last.data.settle_full_using(a)?;
        }
        Ok(())
    }

    #[cfg(debug_assertions)]
    fn reservation_bytes(&self) -> usize {
        self.chunks.iter().fold(self.directory_credit.bytes(), |bytes, chunk| {
            chunk.pages.iter().fold(bytes.saturating_add(chunk.credit.bytes()), |bytes, page| {
                bytes.saturating_add(page.span_credit.bytes()).saturating_add(page.data.reservation_bytes())
                    .saturating_add(page.wide_credit.as_ref().map_or(0, |credit| credit.bytes()))
            })
        })
    }

    fn visit_storage(&self, visit: &mut impl FnMut(usize,usize,usize)) {
        if self.chunks.capacity() != 0 {
            let width = mem::size_of::<LiteralDirectoryChunk>();
            visit(self.chunks.as_ptr() as usize, self.chunks.len() * width,
                self.chunks.capacity() * width);
        }
        for chunk in &self.chunks {
            let width = mem::size_of::<LiteralPage>();
            debug_assert_eq!(chunk.credit.bytes(), chunk.pages.capacity() * width);
            visit(chunk.pages.as_ptr() as usize, chunk.pages.len() * width, chunk.credit.bytes());
        }
        let mut last_payload_page = None;
        for page in self.chunks.iter().flat_map(|chunk| &chunk.pages) {
            let span_width = mem::size_of::<u32>();
            let span_bytes = page.spans.capacity() * span_width;
            debug_assert_eq!(page.span_credit.bytes(), span_bytes);
            visit(page.spans.as_ptr() as usize, page.spans.len() * span_width, span_bytes);
            page.data.visit_storage(visit);
            if page.wide.capacity() != 0 {
                let bytes = page.wide.capacity() * mem::size_of::<Span>();
                debug_assert_eq!(page.wide_credit.as_ref().map_or(0, |credit| credit.bytes()), bytes);
                visit(page.wide.as_ptr() as usize, page.wide.len() * mem::size_of::<Span>(), bytes);
            }
            if let LiteralPageData::Projected(data)=&page.data{
                for value in &data.full{value.visit_storage(&mut *visit);}continue
            }
            for index in 0..page.spans.len() {
                if matches!(&page.data, LiteralPageData::Compact(data)
                    if data.codes[index] >> 8 == PROJECTED_COMPACT_ORDINAL)
                {
                    continue;
                }
                let data = page.get_data(index,0,None,None).expect("issued literal row").1;
                if let Some(current) = data.page_storage_identity() {
                    if last_payload_page == Some(current) {
                        continue;
                    }
                    // Literal payload pages are delivered in row order.
                    // Individual payloads between page rows are independent.
                    last_payload_page = Some(current);
                }
                data.visit_storage(&mut *visit);
            }
        }
        self.directory_credit.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));
    }
}

#[derive(Clone, Copy)]
enum LiteralRowStorage<'a> {
    Pages(&'a LiteralPages),
    Slice(&'a [LiteralRow]),
}

/// A bounded borrowed interval of literal DATA. Creating an interval carries
/// no source or issuance authority. The actual parser/source role still
/// requires an OriginalLiteralFactsView from the authenticated owner.
#[derive(Clone,Copy)]
struct ProjectionLoan<'a>{source:&'a str,origin:usize}
#[derive(Clone,Copy)]
pub struct OriginalLiteralRows<'a> {
    storage: LiteralRowStorage<'a>,
    first: usize,
    last: usize,
    loan:Option<ProjectionLoan<'a>>,
    owner:Option<&'a crate::OriginalLiteralProjectionOwner>,
}
impl<'a> OriginalLiteralRows<'a> {
    #[doc(hidden)]
    pub fn from_slice(rows: &'a [(Span,crate::OriginalLiteralData)]) -> Self {
        Self { storage: LiteralRowStorage::Slice(rows), first: 0, last: rows.len(),loan:None,owner:None }
    }

    pub fn len(self) -> usize { self.last - self.first }
    pub fn is_empty(self) -> bool { self.len() == 0 }

    pub fn get(self, ordinal: usize) -> Option<BorrowedLiteralRow<'a>> {
        if ordinal >= self.len() { return None; }
        let index = self.first + ordinal;
        match self.storage {
            LiteralRowStorage::Pages(rows) => rows.get(index,self.loan,self.owner),
            LiteralRowStorage::Slice(rows) => rows.get(index).map(|(span,data)| (*span,data.as_view())),
        }
    }

    pub fn iter(self) -> impl DoubleEndedIterator<Item=BorrowedLiteralRow<'a>> + ExactSizeIterator {
        (0..self.len()).map(move |index| self.get(index).expect("issued literal fact ordinal"))
    }

    pub fn partition_point(self, mut before: impl FnMut(BorrowedLiteralRow<'a>) -> bool) -> usize {
        let (mut start, mut end) = (0, self.len());
        while start < end {
            let mid = start + (end - start) / 2;
            if before(self.get(mid).expect("issued literal fact ordinal")) {
                start = mid + 1;
            } else {
                end = mid;
            }
        }
        start
    }

    pub fn range(self, range: Range<usize>) -> Option<Self> {
        if range.start > range.end || range.end > self.len() { return None; }
        Some(Self { storage:self.storage,first:self.first+range.start,last:self.first+range.end,loan:self.loan,owner:self.owner })
    }
}

#[cfg(debug_assertions)]
#[derive(Default,Debug,Clone,Copy)]
struct BodyProjectionCensus{pages:usize,rows:usize,released_payload_bytes:usize,released_row_bytes:usize,retained_row_bytes:usize}
// The actual producer and append boundary both require a one-byte token.
const COLON_COMPACT_MAX: usize = (u32::MAX >> 1) as usize;

#[derive(Clone, Copy)]
pub struct OriginalColonRows<'a>(ColonSlice<'a>);

#[derive(Clone, Copy)]
enum ColonSlice<'a> {
    Compact(&'a [u32]),
    Wide(&'a [(Span, bool)]),
}

fn decode_colon(value: u32) -> (Span, bool) {
    let start = (value >> 1) as usize;
    (Span::new(start, start + 1), value & 1 != 0)
}

impl<'a> OriginalColonRows<'a> {
    pub fn len(self) -> usize {
        match self.0 {
            ColonSlice::Compact(rows) => rows.len(),
            ColonSlice::Wide(rows) => rows.len(),
        }
    }

    pub fn is_empty(self) -> bool { self.len() == 0 }

    pub fn get(self, at: usize) -> Option<(Span, bool)> {
        match self.0 {
            ColonSlice::Compact(rows) => rows.get(at).copied().map(decode_colon),
            ColonSlice::Wide(rows) => rows.get(at).copied(),
        }
    }

    pub fn iter(self) -> impl ExactSizeIterator<Item = (Span, bool)> + DoubleEndedIterator + 'a {
        (0..self.len()).map(move |at| self.get(at).expect("issued colon ordinal"))
    }

    pub fn partition_point(self, mut predicate: impl FnMut(&(Span, bool)) -> bool) -> usize {
        match self.0 {
            ColonSlice::Compact(rows) => rows.partition_point(|&row| predicate(&decode_colon(row))),
            ColonSlice::Wide(rows) => rows.partition_point(predicate),
        }
    }

    fn range(self, range: std::ops::Range<usize>) -> Self {
        Self(match self.0 {
            ColonSlice::Compact(rows) => ColonSlice::Compact(&rows[range]),
            ColonSlice::Wide(rows) => ColonSlice::Wide(&rows[range]),
        })
    }
}

enum ColonStorage {
    Compact(Vec<u32>),
    Wide(Vec<(Span, bool)>),
}

fn new_colon_rows<T>(
    len: usize,
    capacity: usize,
    a: &crate::SettingAdmission<'_>,
) -> io::Result<(Vec<T>, crate::SettingRootLease)> {
    let capacity = if len == capacity {
        capacity.checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?.max(4)
    } else {
        capacity
    };
    let layout = std::alloc::Layout::array::<T>(capacity)
        .map_err(|e| io::Error::new(io::ErrorKind::OutOfMemory, e))?;
    let credit = a.reserve(layout.size()).map_err(|e| a.take_operational_error().unwrap_or(e))?;
    // EXACT admitted Global layout. The allocation is unique and initialized
    // as an empty Vec, with the matching element capacity for deallocation.
    let raw = std::ptr::NonNull::new(unsafe { std::alloc::alloc(layout) })
        .ok_or(io::ErrorKind::OutOfMemory)?;
    let rows = unsafe { Vec::from_raw_parts(raw.as_ptr().cast::<T>(), 0, capacity) };
    Ok((rows, credit))
}

impl ColonStorage {
    fn rows(&self) -> OriginalColonRows<'_> {
        OriginalColonRows(match self {
            Self::Compact(rows) => ColonSlice::Compact(rows),
            Self::Wide(rows) => ColonSlice::Wide(rows),
        })
    }

    fn push(
        &mut self, span: Span, close: bool,
        credit: &mut crate::SettingRootLease, a: &crate::SettingAdmission<'_>,
    ) -> io::Result<()> {
        fn push<T>(rows: &mut Vec<T>, row: T, credit: &mut crate::SettingRootLease, a: &crate::SettingAdmission<'_>) -> io::Result<()> {
            if rows.len() == rows.capacity() {
                let (mut next, next_credit) = new_colon_rows(rows.len(), rows.capacity(), a)?;
                next.append(rows);
                drop(std::mem::replace(rows, next));
                drop(std::mem::replace(credit, next_credit));
            }
            rows.push(row);
            Ok(())
        }

        match self {
            Self::Compact(rows) if span.start <= COLON_COMPACT_MAX => {
                push(rows, ((span.start as u32) << 1) | u32::from(close), credit, a)
            }
            Self::Compact(rows) => {
                // Promote only for a genuine larger coordinate. Both buffers
                // remain funded until the compact buffer has been destroyed.
                let (mut next, next_credit) = new_colon_rows(rows.len(), rows.capacity(), a)?;
                next.extend(rows.iter().copied().map(decode_colon));
                next.push((span, close));
                drop(std::mem::replace(self, Self::Wide(next)));
                drop(std::mem::replace(credit, next_credit));
                Ok(())
            }
            Self::Wide(rows) => push(rows, (span, close), credit, a),
        }
    }

    fn visit_storage(&self, visit: &mut impl FnMut(usize, usize, usize)) {
        fn visit_rows<T>(rows: &Vec<T>, visit: &mut impl FnMut(usize, usize, usize)) {
            if rows.capacity() != 0 {
                let bytes = rows.capacity() * std::mem::size_of::<T>();
                visit(rows.as_ptr() as usize, bytes, bytes);
            }
        }
        match self {
            Self::Compact(rows) => visit_rows(rows, visit),
            Self::Wide(rows) => visit_rows(rows, visit),
        }
    }
}

struct Payload{
 #[cfg(debug_assertions)]body_projection:BodyProjectionCensus,
 projection:Option<crate::OriginalLiteralProjectionOwner>,next_body_row:usize,
 rows:LiteralPages,colons:ColonStorage,
 // Both append paths order against this shared frontier. Zero means empty
 // because all issued fact intervals are nonempty.
 last_fact_end:usize,extent:Option<usize>,
 colon_credit:crate::SettingRootLease,fixed_credit:crate::SettingRootLease,
}
pub struct OriginalPrimaryLiteralFacts(Option<Arc<Payload>>);
impl Clone for OriginalPrimaryLiteralFacts{fn clone(&self)->Self{Self(Some(self.0.as_ref().expect("live primary facts").clone()))}}
impl Drop for OriginalPrimaryLiteralFacts{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(payload)=Arc::into_inner(owner){drop(payload)}}}}
/// DATA projection only. Actual source-view/backing authorization belongs to
/// the sealed preprocessing/header installer, not these numeric bounds.
pub struct OriginalLiteralFactsView<'a>{rows:OriginalLiteralRows<'a>,colons:OriginalColonRows<'a>,origin:usize,owner:&'a Payload}
impl<'a>OriginalLiteralFactsView<'a>{
 pub fn with_source_data(mut self,source:&'a str)->io::Result<Self>{
  let extent=self.owner.extent.ok_or(io::ErrorKind::NotConnected)?;
  if self.origin.checked_add(source.len()).is_none_or(|end|end>extent){return Err(io::ErrorKind::InvalidInput.into())}
  self.rows.loan=Some(ProjectionLoan{source,origin:self.origin});Ok(self)
 }
pub fn raw_colons(&self)->(OriginalColonRows<'a>,usize){(self.colons,self.origin)}pub fn admitted_by(&self,a:&crate::SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.owner.colon_credit)&&a.matches_lease_domain(&self.owner.rows.directory_credit)&&a.matches_lease_domain(&self.owner.fixed_credit)}pub fn raw_parts(&self)->(OriginalLiteralRows<'a>,usize){(self.rows,self.origin)}pub fn len(&self)->usize{self.rows.len()}pub fn is_empty(&self)->bool{self.rows.is_empty()}}
impl OriginalPrimaryLiteralFacts{
 pub fn projection_owner(&self)->Option<&crate::OriginalLiteralProjectionOwner>{self.payload().projection.as_ref()}
 pub(super) fn enable_projection(&mut self,projection:crate::OriginalLiteralProjectionOwner)->io::Result<()>{
  let owner=Arc::get_mut(self.0.as_mut().ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidInput)?;
  if owner.rows.len!=0||owner.projection.is_some(){return Err(io::ErrorKind::InvalidInput.into())}
  owner.projection=Some(projection);Ok(())
 }
 pub(super) fn project_body_line(&mut self,line:Span,in_body:bool,source:&str,a:&crate::SettingAdmission<'_>)->io::Result<()>{
  if self.payload().projection.is_none(){return Ok(())}
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  let owner=Arc::get_mut(self.0.as_mut().ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidInput)?;
  if owner.extent.is_some()||!a.matches_lease_domain(&owner.fixed_credit){return Err(io::ErrorKind::InvalidInput.into())}
  while owner.next_body_row<owner.rows.len{
   let ordinal=owner.next_body_row;let at=ordinal%LITERAL_PAGE_LEN;let page_index=ordinal/LITERAL_PAGE_LEN;
   let page=&mut owner.rows.chunks[page_index/DIRECTORY_CHUNK_LEN].pages[page_index%DIRECTORY_CHUNK_LEN];
   let(span,data)=page.get_data(at,page_index*LITERAL_PAGE_LEN,None,owner.projection.as_ref()).ok_or(io::ErrorKind::InvalidData)?;
   if span.end>line.end{break}
   if in_body&&span.start>=line.start&&data.raw()?==source.get(span.range()).ok_or(io::ErrorKind::InvalidInput)?{
    page.body[at/64]|=1u64<<(at%64);
   }
   owner.next_body_row+=1;
   if at+1==LITERAL_PAGE_LEN{
    let settlement = page.settle_body_projection(source,page_index*LITERAL_PAGE_LEN,owner.projection.as_ref().unwrap(),a)?;
    let settlement = match settlement {
        Some(settled) => Some(settled),
        None => page.settle_packed_body_projection(source, a)?,
    };
    if let Some((_rows,_payload,_old,_new)) = settlement {
     #[cfg(debug_assertions)]{let c=&mut owner.body_projection;c.pages+=1;c.rows+=_rows;c.released_payload_bytes+=_payload;c.released_row_bytes+=_old;c.retained_row_bytes+=_new;}
    }
   }
  }
  Ok(())
 }
 fn payload(&self)->&Payload{self.0.as_deref().expect("live primary facts")}
 pub(super) fn new(a:&crate::SettingAdmission<'_>)->io::Result<Self>{let fixed_credit=a.reserve(std::mem::size_of::<Payload>()+2*std::mem::size_of::<usize>()).map_err(|e|a.take_operational_error().unwrap_or(e))?;let rows_credit=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;let colon_credit=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Self(Some(Arc::new(Payload{#[cfg(debug_assertions)]body_projection:BodyProjectionCensus::default(),projection:None,next_body_row:0,rows:LiteralPages{chunks:Vec::new(),len:0,directory_credit:rows_credit},colons:ColonStorage::Compact(Vec::new()),last_fact_end:0,extent:None,colon_credit,fixed_credit}))))}
 pub(super) fn append_actual(&mut self,span:Span,data:crate::OriginalLiteralData,a:&crate::SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let owner=Arc::get_mut(self.0.as_mut().ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidInput)?;
  if owner.extent.is_some()||!a.matches_lease_domain(&owner.rows.directory_credit)||!a.matches_lease_domain(&owner.fixed_credit)||span.start>=span.end||owner.last_fact_end>span.start{return Err(io::ErrorKind::InvalidInput.into())}
  owner.rows.push((span,data),a)?;
  owner.last_fact_end=span.end;
  Ok(())
 }
 pub(super) fn append_actual_colon(&mut self,span:Span,close:bool,a:&crate::SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !self.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let owner=Arc::get_mut(self.0.as_mut().ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidInput)?;
  if owner.extent.is_some()||span.end.checked_sub(span.start)!=Some(1)||owner.last_fact_end>span.start{return Err(io::ErrorKind::InvalidInput.into())}
  owner.colons.push(span,close,&mut owner.colon_credit,a)?;
  owner.last_fact_end=span.end;
  Ok(())
 }

 pub(super) fn seal_actual_frontier(&mut self,extent:usize,a:&crate::SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !self.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let owner=Arc::get_mut(self.0.as_mut().ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidInput)?;if owner.extent.is_some()||owner.last_fact_end>extent{return Err(io::ErrorKind::InvalidInput.into())}owner.extent=Some(extent);Ok(())
 }
 pub fn is_admitted_by(&self,a:&crate::SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.payload().rows.directory_credit)&&a.matches_lease_domain(&self.payload().colon_credit)&&a.matches_lease_domain(&self.payload().fixed_credit)}
 pub fn consumed_extent(&self)->Option<usize>{self.payload().extent}
 pub fn rows(&self)->OriginalLiteralRows<'_>{let mut rows=self.payload().rows.window();rows.owner=self.payload().projection.as_ref();rows}
 pub fn colon_rows(&self)->OriginalColonRows<'_>{self.payload().colons.rows()}
 /// Bounds are DATA, not source authorization. Source installer must first
 /// match the SAME real source backing/view, then borrow this no-copy window.
 pub fn checked_data_window(&self,window:Span)->io::Result<OriginalLiteralFactsView<'_>>{
  let owner=self.payload();let extent=owner.extent.ok_or(io::ErrorKind::NotConnected)?;if window.start>window.end||window.end>extent{return Err(io::ErrorKind::InvalidInput.into())}
  let mut rows=owner.rows.window();rows.owner=owner.projection.as_ref();let first=rows.partition_point(|(span,_)|span.end<=window.start);let last=rows.partition_point(|(span,_)|span.start<window.end);
  if first<last&&(rows.get(first).unwrap().0.start<window.start||rows.get(last-1).unwrap().0.end>window.end){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual source view cuts an issued literal occurrence"))}
  let colons=owner.colons.rows();
  let cf=colons.partition_point(|(span,_)|span.end<=window.start);let cl=colons.partition_point(|(span,_)|span.start<window.end);
  if cf<cl&&(colons.get(cf).unwrap().0.start<window.start||colons.get(cl-1).unwrap().0.end>window.end){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual source view cuts an issued colon occurrence"))}
  Ok(OriginalLiteralFactsView{rows:rows.range(first..last).ok_or(io::ErrorKind::InvalidData)?,colons:colons.range(cf..cl),origin:window.start,owner})
 }
 #[cfg(debug_assertions)]
 pub(crate) fn trace_retention(&self)->impl std::fmt::Debug{
  #[derive(Default)]
  struct Census{batch_payload_pages:usize,batch_payload_reserved:usize,exclusive_payload_rows:usize,exclusive_payload_reserved:usize,shared_payload_references:usize,shared_payload_reserved_per_reference_upper:usize}
  #[derive(Default,Debug)]
  struct NumericCensus{
   delivered_rows:usize,
   exclusive_singleton_rows:usize,
   exclusive_singleton_raw_capacity:usize,
   exclusive_singleton_reserved:usize,
   all_numeric_batch_pages:usize,
   all_numeric_batch_raw_capacity:usize,
   all_numeric_batch_reserved:usize,
   mixed_batch_pages:usize,
   mixed_batch_numeric_raw_capacity:usize,
   mixed_batch_reserved:usize,
  }
  let owner=self.payload();let mut census=Census::default();let mut numeric=NumericCensus::default();
  let mut last_payload_page = None;
  for page in owner.rows.chunks.iter().flat_map(|chunk| &chunk.pages) {
   // Physical Arc counts alone no longer describe the logical shared rows.
   let mut occurrences = [0u16; LITERAL_PAGE_LEN];
   if let LiteralPageData::Compact(compact) = &page.data {
    for &code in &compact.codes {
     if code >> 8 < PROJECTED_COMPACT_ORDINAL { occurrences[(code & 0xff) as usize] += 1; }
    }
   }
   for index in 0..page.spans.len() {
   let data=page.get_data(index,0,None,owner.projection.as_ref()).expect("issued literal row").1;
   if data.is_projected(){continue}
   let numeric_raw = data.trace_numeric_raw();
   numeric.delivered_rows += usize::from(numeric_raw.is_some());
   if let Some(current) = data.page_storage_identity() {
    if last_payload_page == Some(current) { continue; }
    last_payload_page = Some(current);
    census.batch_payload_pages += 1;
    let reserved = data.trace_payload().1;
    census.batch_payload_reserved += reserved;
    let (numeric_rows, total_rows, numeric_raw) = data.trace_batch_numeric_raw();
    if numeric_rows == total_rows {
     numeric.all_numeric_batch_pages += 1;
     numeric.all_numeric_batch_raw_capacity += numeric_raw;
     numeric.all_numeric_batch_reserved += reserved;
    } else if numeric_rows != 0 {
     numeric.mixed_batch_pages += 1;
     numeric.mixed_batch_numeric_raw_capacity += numeric_raw;
     numeric.mixed_batch_reserved += reserved;
    }
    continue;
   }
   let (exclusive,bytes)=data.trace_payload();
   let repeated = if let LiteralPageData::Compact(compact) = &page.data {
    let code = compact.codes[index];
    code >> 8 != WIDE_LITERAL_ORDINAL && occurrences[(code & 0xff) as usize] > 1
   } else { false };
   if exclusive && !repeated {
    census.exclusive_payload_rows=census.exclusive_payload_rows.saturating_add(1);
    census.exclusive_payload_reserved=census.exclusive_payload_reserved.saturating_add(bytes);
    if let Some(raw) = numeric_raw {
     numeric.exclusive_singleton_rows += 1;
     numeric.exclusive_singleton_raw_capacity += raw;
     numeric.exclusive_singleton_reserved += bytes;
    }
   } else {
    census.shared_payload_references=census.shared_payload_references.saturating_add(1);
    census.shared_payload_reserved_per_reference_upper=census.shared_payload_reserved_per_reference_upper.saturating_add(bytes);
   }
  }
  }
  // Use a named Debug builder so this snapshot has no owned text or alloc.
  struct Snapshot{rows:usize,colons:usize,fixed:usize,row_capacity:usize,colon_capacity:usize,census:Census,numeric:NumericCensus,body_projection:BodyProjectionCensus}
  impl std::fmt::Debug for Snapshot{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{
   f.debug_struct("PrimaryLiteralCensus").field("rows",&self.rows).field("colons",&self.colons)
    .field("fixed_reserved",&self.fixed).field("row_capacity",&self.row_capacity).field("colon_capacity",&self.colon_capacity)
    .field("batch_payload_pages",&self.census.batch_payload_pages)
    .field("batch_payload_reserved",&self.census.batch_payload_reserved)
    .field("exclusive_payload_rows",&self.census.exclusive_payload_rows).field("exclusive_payload_reserved",&self.census.exclusive_payload_reserved)
    .field("shared_payload_references",&self.census.shared_payload_references).field("shared_payload_reserved_per_reference_upper",&self.census.shared_payload_reserved_per_reference_upper)
    .field("numeric",&self.numeric).field("body_projection",&self.body_projection).finish()
  }}
  Snapshot{rows:owner.rows.len,colons:owner.colons.rows().len(),fixed:owner.fixed_credit.bytes(),row_capacity:owner.rows.reservation_bytes(),colon_capacity:owner.colon_credit.bytes(),census,numeric,body_projection:owner.body_projection}
 }
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  let owner=self.0.as_ref().expect("live primary facts");if let Some(projection)=&owner.projection{projection.visit_storage(&mut visit)}let fixed=std::mem::size_of::<Payload>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(owner)as usize,fixed,fixed);owner.rows.visit_storage(&mut visit);owner.colons.visit_storage(&mut visit);owner.colon_credit.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));owner.fixed_credit.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));
 }
}
#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc, atomic::{Ordering}};
 #[cfg(debug_assertions)]
 #[test]
 fn failed_primary_literal_census_never_counts_shared_payload_as_exclusive(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
  let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();
  let data=crate::OriginalLiteralData::from_value_using("7".to_owned(),crate::OriginalTokenValue::Int(7),&a).unwrap();
  let (exclusive,bytes)=data.as_view().trace_payload();assert!(exclusive);
  facts.append_actual(Span::new(0,1),data.clone(),&a).unwrap();
  facts.append_actual_colon(Span::new(1,2),false,&a).unwrap();
  facts.append_actual(Span::new(2,3),data,&a).unwrap();
  let before=used.load(Ordering::Acquire);
  let census=format!("{:?}",facts.trace_retention());
  assert!(census.contains("rows: 2, colons: 1"));
  assert!(census.contains("exclusive_payload_rows: 0, exclusive_payload_reserved: 0"));
  assert!(census.contains(&format!("shared_payload_references: 2, shared_payload_reserved_per_reference_upper: {}",2*bytes)));
  assert_eq!(used.load(Ordering::Acquire),before);
  drop(facts);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[cfg(debug_assertions)]
 #[test]
 fn numeric_census_classifies_real_owner_even_if_only_numeric_prefix_was_delivered(){
  use crate::{OriginalLiteralData,OriginalTokenValue};
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
  let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();
  let make=|value|Some(OriginalLiteralData::from_value_using("123".to_owned(),value,&a).unwrap());
  let single=make(OriginalTokenValue::Int(0)).unwrap();
  let single_raw=single.as_view().raw_storage().unwrap().capacity();
  facts.append_actual(Span::new(0,3),single,&a).unwrap();

  let mut all=[make(OriginalTokenValue::Int(1)),make(OriginalTokenValue::Int(2)),
               make(OriginalTokenValue::Int(3)),make(OriginalTokenValue::Float(-0.0))];
  OriginalLiteralData::pack_delivery_batch_using(&mut all,&a).unwrap();
  let all_raw:usize=all.iter().flatten().map(|d|d.as_view().raw_storage().unwrap().capacity()).sum();
  for (i,slot) in all.iter_mut().enumerate(){
   facts.append_actual(Span::new(3+i*3,6+i*3),slot.take().unwrap(),&a).unwrap();
  }

  let mut mixed=[make(OriginalTokenValue::Int(4)),make(OriginalTokenValue::Int(5)),
                 make(OriginalTokenValue::Int(6)),make(OriginalTokenValue::String("x"))];
  OriginalLiteralData::pack_delivery_batch_using(&mut mixed,&a).unwrap();
  let mixed_raw:usize=mixed[..3].iter().flatten().map(|d|d.as_view().raw_storage().unwrap().capacity()).sum();
  facts.append_actual(Span::new(15,18),mixed[0].take().unwrap(),&a).unwrap();
  let before=used.load(Ordering::Acquire);
  let census=format!("{:?}",facts.trace_retention());
  assert!(census.contains("batch_payload_pages: 2"),"{census}");
  assert!(census.contains("delivered_rows: 6, exclusive_singleton_rows: 1"),"{census}");
  assert!(census.contains(&format!("exclusive_singleton_raw_capacity: {single_raw},")),"{census}");
  assert!(census.contains(&format!("all_numeric_batch_pages: 1, all_numeric_batch_raw_capacity: {all_raw},")),"{census}");
  assert!(census.contains(&format!("mixed_batch_pages: 1, mixed_batch_numeric_raw_capacity: {mixed_raw},")),"{census}");
  assert_eq!(used.load(Ordering::Acquire),before);
  drop((mixed,facts));
  assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_same_roster_window_never_copies_or_cuts_literals_and_last_alias_keeps_real_credit(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();let data=crate::OriginalLiteralData::from_value_using("123".to_owned(),crate::OriginalTokenValue::Int(123),&a).unwrap();facts.append_actual(Span::new(5,8),data,&a).unwrap();assert!(facts.checked_data_window(Span::new(0,10)).is_err());facts.seal_actual_frontier(12,&a).unwrap();let view=facts.checked_data_window(Span::new(4,10)).unwrap();let(rows,origin)=view.raw_parts();assert_eq!(origin,4);assert!(rows.get(0).unwrap().1.same_owner(facts.rows().get(0).unwrap().1));assert_eq!(rows.get(0).unwrap().0,Span::new(5,8));assert!(facts.checked_data_window(Span::new(6,10)).is_err());assert!(facts.checked_data_window(Span::new(0,7)).is_err());assert!(facts.checked_data_window(Span::new(0,13)).is_err());let alias=facts.clone();drop(facts);assert!(used.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());assert_eq!(alias.rows().len(),1);drop(alias);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod full_slice_parser_tests{
 use super::*;use std::sync::{Arc, atomic::{Ordering}};
 fn scalar_facts(raw:&str,value:crate::OriginalTokenValue<&str>,origin:usize,a:&crate::SettingAdmission<'_>)->OriginalPrimaryLiteralFacts{let mut facts=OriginalPrimaryLiteralFacts::new(a).unwrap();let data=crate::OriginalLiteralData::from_value_using(raw.into(),value,a).unwrap();facts.append_actual(Span::new(origin,origin+raw.len()),data,a).unwrap();facts.seal_actual_frontier(origin+raw.len(),a).unwrap();facts}
 #[test]fn actual_full_slice_setting_parser_lends_exact_typed_value_across_checked_tu_window_without_reparse(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let raw="1.23457";let exact=f32::from_bits(0x3f9e0651);let facts=scalar_facts(raw,crate::OriginalTokenValue::Float(exact),113,&a);let lex=crate::lex_spans(raw);
  let root=crate::prepare_setting_expression_with_original_literal_facts(raw,&lex.tokens,Span::new(0,raw.len()),&a,Some(facts.checked_data_window(Span::new(113,113+raw.len())).unwrap())).unwrap();
  let crate::ExprKind::Literal(literal)=&root.kind else{panic!("literal")};assert!(matches!(literal.original_value(),Some(crate::OriginalTokenValue::Float(value))if value.to_bits()==exact.to_bits()));assert!(literal.original_data().unwrap().same_owner(facts.rows().get(0).unwrap().1));assert_eq!(literal.original_origin(),Some(0));drop(root);assert!(counter.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());drop(facts);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_full_slice_static_string_uses_one_lexical_value_without_bracket_child_parse_or_runtime_grant(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let raw="\"[missing.field]\"";let facts=scalar_facts(raw,crate::OriginalTokenValue::String("[missing.field]"),0,&a);let lex=crate::lex_spans(raw);
  let root=crate::prepare_setting_expression_with_original_literal_facts(raw,&lex.tokens,Span::new(0,raw.len()),&a,Some(facts.checked_data_window(Span::new(0,raw.len())).unwrap())).unwrap();let crate::ExprKind::Literal(literal)=&root.kind else{panic!("literal")};assert!(matches!(literal.original_value(),Some(crate::OriginalTokenValue::String("[missing.field]"))));assert!(literal.syntax_parts().unwrap().is_none());drop(root);drop(facts);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_full_slice_missing_fact_and_first_io_do_not_publish_raw_spelling_fallback_or_partial_root(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.seal_actual_frontier(1,&a).unwrap();let lex=crate::lex_spans("1");let result=crate::prepare_setting_expression_with_original_literal_facts("1",&lex.tokens,Span::new(0,1),&a,Some(facts.checked_data_window(Span::new(0,1)).unwrap()));assert!(matches!(result,Err(crate::SettingSyntaxFailure::Operational(ref e))if e.kind()==io::ErrorKind::Unsupported));let actual=a.take_operational_error().unwrap();assert_eq!(actual.kind(),io::ErrorKind::Unsupported);drop(facts);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let fault=||Err(io::Error::from_raw_os_error(1450));let failed=crate::SettingAdmission::new(&counter,1<<24,&fault);let result=crate::prepare_setting_expression_with_original_literal_facts("1",&lex.tokens,Span::new(0,1),&failed,None);assert!(matches!(result,Err(crate::SettingSyntaxFailure::Operational(ref e))if e.kind()==io::Error::from_raw_os_error(1450).kind()));assert_eq!(failed.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 struct BodySource<'a>{source:&'a str,tokens:&'a[crate::SpanToken],facts:&'a OriginalPrimaryLiteralFacts,a:&'a crate::SettingAdmission<'a>}
 impl crate::SettingSyntaxProvider for BodySource<'_>{
  fn setting(&self,_:&crate::Item)->Result<crate::SettingStatement,crate::Diagnostic>{panic!("no initial settings in fixture")}
  fn original_expression(&self,source:&str,offset:usize)->io::Result<Option<crate::ParsedExpr>>{
   if self.source.get(offset..offset+source.len())!=Some(source){return Err(io::ErrorKind::InvalidData.into())}let end=offset+source.len();let first=self.tokens.partition_point(|token|token.span.end<=offset);let last=self.tokens.partition_point(|token|token.span.start<end);
   Ok(Some(crate::parse_expression_original_token_view(self.source,&self.tokens[first..last],offset,self.a,Some(self.facts.checked_data_window(Span::new(0,self.source.len()))?))))
  }
 }
 #[test]fn actual_same_body_statement_parser_lends_one_primary_numeric_fact_to_its_original_root_and_coordinates(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let source="/proc/p()\n    return 1.23457\n";let start=source.find("1.23457").unwrap();let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();let data=crate::OriginalLiteralData::from_value_using("1.23457".into(),crate::OriginalTokenValue::Float(f32::from_bits(0x3f9e0651)),&a).unwrap();facts.append_actual(Span::new(start,start+7),data,&a).unwrap();facts.seal_actual_frontier(source.len(),&a).unwrap();let tokens=crate::lex_spans(source);let ast=crate::parse(source);let provider=BodySource{source,tokens:&tokens.tokens,facts:&facts,a:&a};let parsed=crate::parse_body_items_with_context_and_settings(&ast.items[0].children,source,&|_|None,&provider,&a);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);
  let crate::StatementKind::Return(Some(root))=&parsed.statements[0].kind else{panic!("return")};assert_eq!(root.span,Span::new(start,start+7));let crate::ExprKind::Literal(literal)=&root.kind else{panic!("literal")};assert!(matches!(literal.original_value(),Some(crate::OriginalTokenValue::Float(value))if value.to_bits()==0x3f9e0651));assert!(literal.original_data().unwrap().same_owner(facts.rows().get(0).unwrap().1));drop(parsed);drop(facts);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod archived_template_source_tests{
 use super::*;use std::sync::{Arc, atomic::{Ordering}};
 fn input(prefix:usize,a:&SettingAdmission<'_>)->(String,Vec<SpanToken>,OriginalPrimaryLiteralFacts){
  let raw="\"a[1]b\"";let source=format!("{}{raw}"," ".repeat(prefix));let mut facts=OriginalPrimaryLiteralFacts::new(a).unwrap();
  for(start,end,value)in [(0,3,OriginalTokenValue::InterpBegin("a")),(3,4,OriginalTokenValue::Int(1)),(4,7,OriginalTokenValue::InterpEnd("b"))]{let mode=if start==3{OriginalStringMode::Unknown}else{OriginalStringMode::Normal};let data=OriginalLiteralData::from_value_with_mode_using(raw[start..end].into(),value,mode,a).unwrap();facts.append_actual(Span::new(prefix+start,prefix+end),data,a).unwrap();}
  facts.seal_actual_frontier(source.len(),a).unwrap();let tokens=vec![SpanToken{kind:TokenKind::Interpolation,span:Span::new(prefix,prefix+3)},SpanToken{kind:TokenKind::Number,span:Span::new(prefix+3,prefix+4)},SpanToken{kind:TokenKind::Interpolation,span:Span::new(prefix+4,prefix+7)}];(source,tokens,facts)
 }
 #[test]fn archived_template_borrows_exact_source_and_same_issued_parts_across_shifted_views(){
  for prefix in [0,7]{let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let(source,tokens,facts)=input(prefix,&a);let before=crate::literal::literal_child_parses_for_test();let parsed=crate::parse_expression_original_token_view(&source,&tokens,prefix,&a,Some(facts.checked_data_window(Span::new(0,source.len())).unwrap()));assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);assert!(a.take_operational_error().is_none());let root=parsed.expr.as_ref().expect("actual typed template");assert_eq!(root.span,Span::new(0,7));let ExprKind::Literal(value)=&root.kind else{panic!("template")};let parts=value.syntax_parts().unwrap().unwrap();assert_eq!(parts.expressions.len(),1);assert_eq!(parts.expressions[0].span,Span::new(3,4));assert!(parts.fragments[0].original.as_ref().unwrap().same_owner(facts.rows().get(0).unwrap().1));assert!(parts.fragments[1].original.as_ref().unwrap().same_owner(facts.rows().get(2).unwrap().1));assert_eq!(crate::literal::literal_child_parses_for_test(),before);drop(parsed);drop(facts);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 }
 #[test]fn archived_template_rejects_missing_facts_and_changed_source_without_guessing_a_template(){
  for missing in [false,true]{let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let(mut source,tokens,facts)=input(0,&a);if !missing{source.replace_range(1..2,"z");}let view=(!missing).then(||facts.checked_data_window(Span::new(0,source.len())).unwrap());let parsed=crate::parse_expression_original_token_view(&source,&tokens,0,&a,view);assert!(parsed.expr.is_none());let failure=a.take_operational_error().expect("explicit unavailable/mismatched data");assert_eq!(failure.kind(),if missing{io::ErrorKind::Unsupported}else{io::ErrorKind::InvalidData});drop(parsed);drop(facts);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 }
}

#[cfg(test)]mod colon_ledger_controls{
 use super::*;use std::sync::atomic::{Ordering};
 #[test]fn whole_original_colon_uses_same_fact_not_authored_spacing_and_keeps_scalar_rows_separate(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let source="value : key";let tokens=crate::lex_spans(source).tokens;
  for(close,allowed)in[(true,true),(false,false)]{let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.append_actual_colon(Span::new(6,7),close,&a).unwrap();facts.seal_actual_frontier(source.len(),&a).unwrap();assert!(facts.rows().is_empty());assert!(facts.colon_rows().iter().eq([(Span::new(6,7),close)]));let parsed=crate::parse_expression_original_token_view(source,&tokens,0,&a,Some(facts.checked_data_window(Span::new(0,source.len())).unwrap()));assert_eq!(parsed.diagnostics.is_empty(),allowed);if allowed{assert!(matches!(parsed.expr.as_ref().unwrap().kind,crate::ExprKind::Member{via_colon:true,..}));}drop(parsed);drop(facts);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
  assert!(crate::parse_expression(source).diagnostics.is_empty(),"ordinary compiler path unchanged");
 }
 #[test]fn whole_colon_reuses_exact_fact_window_and_offset_under_shifted_body_input(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let source="prefix value:key";let start=7;let tokens=crate::lex_spans(source).tokens.into_iter().filter(|t|t.span.start>=start).collect::<Vec<_>>();let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.append_actual_colon(Span::new(12,13),true,&a).unwrap();facts.seal_actual_frontier(source.len(),&a).unwrap();let view=facts.checked_data_window(Span::new(0,source.len())).unwrap();let parsed=crate::parse_expression_original_token_view(source,&tokens,start,&a,Some(view));assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);assert_eq!(parsed.expr.as_ref().unwrap().span,Span::new(0,9));assert!(matches!(parsed.expr.as_ref().unwrap().kind,crate::ExprKind::Member{via_colon:true,..}));drop(parsed);let charged=used.load(Ordering::Acquire);let alias=facts.clone();drop(facts);assert_eq!(used.load(Ordering::Acquire),charged);assert_eq!(alias.colon_rows().len(),1);drop(alias);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn whole_colon_missing_and_foreign_facts_are_operational_refusals_not_ordinary_heuristic_fallback(){let one=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let two=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&one,8<<20,&||Ok(()));let source="value:key";let tokens=crate::lex_spans(source).tokens;let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.seal_actual_frontier(source.len(),&a).unwrap();let parsed=crate::parse_expression_original_token_view(source,&tokens,0,&a,Some(facts.checked_data_window(Span::new(0,source.len())).unwrap()));assert!(parsed.expr.is_none());assert_eq!(a.take_operational_error().unwrap().kind(),io::ErrorKind::Unsupported);drop((parsed,facts));assert_eq!(one.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let fresh=crate::SettingAdmission::new(&one,8<<20,&||Ok(()));let foreign=crate::SettingAdmission::new(&two,8<<20,&||Ok(()));let mut facts=OriginalPrimaryLiteralFacts::new(&fresh).unwrap();facts.append_actual_colon(Span::new(5,6),true,&fresh).unwrap();facts.seal_actual_frontier(source.len(),&fresh).unwrap();let parsed=crate::parse_expression_original_token_view(source,&tokens,0,&foreign,Some(facts.checked_data_window(Span::new(0,source.len())).unwrap()));assert!(parsed.expr.is_none());assert_eq!(foreign.take_operational_error().unwrap().kind(),io::ErrorKind::InvalidInput);drop((parsed,facts));assert_eq!(one.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());assert_eq!(two.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn compact_colons_keep_exact_high_coordinate_and_fail_without_publishing() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let a = crate::SettingAdmission::new(&used, 1<<20, &|| Ok(()));
     let mut facts = OriginalPrimaryLiteralFacts::new(&a).unwrap();
     let lower = Span::new(1, 2);
     let edge = Span::new(COLON_COMPACT_MAX, COLON_COMPACT_MAX + 1);
     let wide = Span::new(edge.end, edge.end + 1);
     facts.append_actual_colon(lower, false, &a).unwrap();
     facts.append_actual_colon(edge, true, &a).unwrap();
     assert_eq!(facts.payload().colon_credit.bytes(), 4 * std::mem::size_of::<u32>());
     let before = used.load(Ordering::Acquire);
     let needed = 4 * std::mem::size_of::<(Span, bool)>();
     let tight = crate::SettingAdmission::new(&used, before + needed - 1, &|| Ok(()));
     assert_eq!(facts.append_actual_colon(wide, false, &tight).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
     assert_eq!(used.load(Ordering::Acquire), before);
     assert!(facts.colon_rows().iter().eq([(lower, false), (edge, true)]));
     assert_eq!(facts.payload().last_fact_end, edge.end);
     assert_eq!(facts.append_actual_colon(Span::new(wide.start, wide.end+1), true, &a).unwrap_err().kind(), io::ErrorKind::InvalidInput);
     facts.append_actual_colon(wide, false, &a).unwrap();
     assert_eq!(used.load(Ordering::Acquire), before - 4 * std::mem::size_of::<u32>() + needed);
     facts.seal_actual_frontier(wide.end, &a).unwrap();
     let (rows, origin) = facts.checked_data_window(Span::new(edge.start, wide.end)).unwrap().raw_colons();
     assert_eq!(origin, edge.start);
     assert_eq!(rows.iter().next_back(), Some((wide, false)));
     assert_eq!(rows.partition_point(|(span,_)|span.start < wide.start), 1);
     assert!(rows.iter().eq([(edge, true), (wide, false)]));
     let alias = facts.clone();
     let retained = used.load(Ordering::Acquire);
     drop(facts);
     assert_eq!(used.load(Ordering::Acquire), retained);
     drop(alias);
     assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn colon_ledger_quota_first_io_and_overlap_refuse_without_leaking_credit(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let good=||Ok(());let a=crate::SettingAdmission::new(&used,8<<20,&good);let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.append_actual_colon(Span::new(2,3),true,&a).unwrap();assert_eq!(facts.append_actual_colon(Span::new(2,3),false,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);let stopped=||Err(io::Error::from_raw_os_error(1450));let fail=crate::SettingAdmission::new(&used,8<<20,&stopped);assert_eq!(facts.append_actual_colon(Span::new(4,5),false,&fail).unwrap_err().raw_os_error(),Some(1450));drop(facts);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());let tiny=crate::SettingAdmission::new(&used,crate::SettingChargeCounter::root_allocation_bytes() + (1),&good);assert_eq!(OriginalPrimaryLiteralFacts::new(&tiny).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
}

#[cfg(test)]
mod literal_page_controls {
    use super::*;
    use std::sync::atomic::{Ordering};

    #[test]
    fn compact_literal_page_keeps_exact_data_on_denial_first_error_and_detach() {
        use std::cell::Cell;
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let mut page = LiteralPage::new(0, &a).unwrap();
        let mut issued = std::array::from_fn::<_, 4, _>(|_| Some(
            crate::OriginalLiteralData::from_value_using(
                "7".into(), crate::OriginalTokenValue::Int(7), &a,
            ).unwrap()
        ));
        crate::OriginalLiteralData::pack_delivery_batch_using(&mut issued, &a).unwrap();
        let [first, second, third, last] = issued.map(Option::unwrap);
        assert!(!first.same_owner(&second));
        let raw = first.raw().as_ptr();
        let different = crate::OriginalLiteralData::from_value_using(
            "7".into(), crate::OriginalTokenValue::Int(7), &a,
        ).unwrap();
        let cohort = [&first, &second, &different, &third, &last];
        for i in 0..LITERAL_PAGE_LEN {
            let value = cohort[i % cohort.len()].clone();
            page.push((Span::new(i * 2, i * 2 + 1), value), &a).unwrap();
        }
        let old = used.load(Ordering::Acquire);
        let exact = LITERAL_PAGE_LEN * mem::size_of::<u32>() + 2 * mem::size_of::<OriginalLiteralOwner>();
        let work = mem::size_of::<LiteralPagePlan>();
        let short = crate::SettingAdmission::new(&used, old + work + exact - 1, &|| Ok(()));
        page.data.settle_full_using(&short).unwrap();
        assert!(matches!(page.data, LiteralPageData::Dense(_)));
        assert_eq!(used.load(Ordering::Acquire), old);
        let polls = Cell::new(0);
        let poll = || {
            polls.set(polls.get() + 1);
            if polls.get() == 3 { Err(io::Error::from_raw_os_error(1450)) } else { Ok(()) }
        };
        let stopped = crate::SettingAdmission::new(&used, old + work + exact, &poll);
        assert_eq!(page.data.settle_full_using(&stopped).unwrap_err().raw_os_error(), Some(1450));
        assert!(matches!(page.data, LiteralPageData::Dense(_)));
        assert_eq!(used.load(Ordering::Acquire), old);
        let exact_limit = crate::SettingAdmission::new(&used, old + work + exact, &|| Ok(()));
        page.data.settle_full_using(&exact_limit).unwrap();
        let LiteralPageData::Compact(data) = &page.data else { panic!("exact admitted bank") };
        assert_eq!(data.credit.bytes(), exact);
        assert_eq!(used.load(Ordering::Acquire),
            old - LITERAL_PAGE_LEN * mem::size_of::<crate::OriginalLiteralData>() + exact);
        for i in 0..LITERAL_PAGE_LEN {
            let (span, view) = page.get(i).unwrap();
            assert_eq!(span, Span::new(i * 2, i * 2 + 1));
            assert!(view.same_owner(cohort[i % cohort.len()]));
        }
        assert_eq!(page.get(0).unwrap().1.raw().unwrap().as_ptr(), raw);
        let keep = page.get(0).unwrap().1.detach_using(&a).unwrap();
        drop((page, first, second, third, last, different));
        assert!(used.load(Ordering::Acquire) > crate::SettingChargeCounter::root_allocation_bytes());
        assert_eq!(keep.raw().as_ptr(), raw);
        assert!(matches!(keep.value(), crate::OriginalTokenValue::Int(7)));
        drop(keep);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn compact_literal_page_retains_wide_actual_issuer_ordinals() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let mut pool = crate::OriginalLiteralPool::new(&a).unwrap();
        pool.advance_empty_pool_for_test(WIDE_LITERAL_ORDINAL as usize - 1);
        let raw = String::from("77");
        let credit = a.reserve(raw.capacity()).unwrap();
        let wide = pool.issue_using(raw, credit, crate::OriginalTokenValue::Int(77),
            crate::OriginalStringMode::Unknown, &a).unwrap();
        assert_eq!(wide.as_view().ordinal(), WIDE_LITERAL_ORDINAL as usize);
        let common = crate::OriginalLiteralData::from_value_using(
            "7".into(), crate::OriginalTokenValue::Int(7), &a,
        ).unwrap();
        let mut page = LiteralPage::new(0, &a).unwrap();
        for i in 0..LITERAL_PAGE_LEN {
            let data = if i == 255 { &wide } else { &common };
            page.push((Span::new(i * 3, i * 3 + data.raw().len()), data.clone()), &a).unwrap();
        }
        page.data.settle_full_using(&a).unwrap();
        let LiteralPageData::Compact(data) = &page.data else { panic!("admitted compact page") };
        assert_eq!(data.owners.len(), 1);
        assert_eq!(data.wide.len(), 1);
        let (span, view) = page.get(255).unwrap();
        assert_eq!(span, Span::new(765, 767));
        assert!(view.same_owner(&wide));
        assert_eq!(view.raw().unwrap().as_ptr(), wide.raw().as_ptr());
        assert!(matches!(view.value().unwrap(), crate::OriginalTokenValue::Int(77)));
        drop((page, pool, common, wide));
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn mixed_fact_frontier_rejects_both_overlap_directions_and_checks_sealing() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut facts = OriginalPrimaryLiteralFacts::new(&a).unwrap();
        let data = crate::OriginalLiteralData::from_value_using(
            "7".into(), crate::OriginalTokenValue::Int(7), &a,
        ).unwrap();
        let literal = Span::new(5, 6);
        let colon = Span::new(6, 7);
        let next = Span::new(7, 8);
        facts.append_actual(literal, data.clone(), &a).unwrap();
        assert_eq!(facts.append_actual_colon(literal, false, &a).unwrap_err().kind(),
            io::ErrorKind::InvalidInput);
        facts.append_actual_colon(colon, true, &a).unwrap();
        assert_eq!(facts.append_actual(colon, data.clone(), &a).unwrap_err().kind(),
            io::ErrorKind::InvalidInput);
        facts.append_actual(next, data.clone(), &a).unwrap();
        assert_eq!(facts.seal_actual_frontier(next.start, &a).unwrap_err().kind(),
            io::ErrorKind::InvalidInput);
        facts.seal_actual_frontier(next.end, &a).unwrap();
        assert!(facts.colon_rows().iter().eq([(colon, true)]));
        let rows = facts.rows();
        assert_eq!(rows.len(), 2);
        assert_eq!(rows.get(0).unwrap().0, literal);
        assert_eq!(rows.get(1).unwrap().0, next);
        assert!(rows.get(1).unwrap().1.same_owner(&data));
        drop((facts, data));
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn literal_fact_directory_adds_one_chunk_without_moving_existing_pages() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let healthy = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let mut facts = OriginalPrimaryLiteralFacts::new(&healthy).unwrap();
        let data = crate::OriginalLiteralData::from_value_using(
            "12".into(), crate::OriginalTokenValue::Int(12), &healthy).unwrap();
        let first_boundary = DIRECTORY_CHUNK_LEN * LITERAL_PAGE_LEN;
        for row in 0..first_boundary {
            facts.append_actual(Span::new(row * 3, row * 3 + 2), data.clone(), &healthy).unwrap();
        }
        let first_page = facts.payload().rows.chunks[0].pages.as_ptr();
        let retained = used.load(Ordering::Acquire);
        let incremental = LITERAL_PAGE_LEN * LITERAL_ROW_BYTES
            + DIRECTORY_CHUNK_LEN * mem::size_of::<LiteralPage>();
        let next = Span::new(first_boundary * 3, first_boundary * 3 + 2);
        let short = crate::SettingAdmission::new(&used, retained + incremental - 1, &|| Ok(()));
        assert_eq!(facts.append_actual(next, data.clone(), &short).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(facts.rows().len(), first_boundary);
        assert_eq!(used.load(Ordering::Acquire), retained);
        let exact = crate::SettingAdmission::new(&used, retained + incremental, &|| Ok(()));
        facts.append_actual(next, data.clone(), &exact).unwrap();
        assert_eq!(used.load(Ordering::Acquire), retained + incremental);
        assert_eq!(facts.payload().rows.chunks[0].pages.as_ptr(), first_page);
        let (span, value) = facts.rows().get(first_boundary).unwrap();
        assert_eq!(span, next);
        assert!(value.same_owner(&data));
        drop((facts, data));
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn literal_fact_pages_retain_exact_rows_and_refuse_growth_without_flattening() {
        let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let healthy=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
        let mut facts=OriginalPrimaryLiteralFacts::new(&healthy).unwrap();
        let data=crate::OriginalLiteralData::from_value_using("12".into(),crate::OriginalTokenValue::Int(12),&healthy).unwrap();
        for row in 0..LITERAL_PAGE_LEN {
            facts.append_actual(Span::new(row*3,row*3+2),data.clone(),&healthy).unwrap();
        }
        let first=facts.rows().get(0).unwrap().1.raw().unwrap().as_ptr();
        let retained=used.load(Ordering::Acquire);
        let page_bytes=LITERAL_PAGE_LEN*LITERAL_ROW_BYTES;
        #[cfg(target_pointer_width = "64")]
        assert_eq!(mem::size_of::<LiteralRow>() - LITERAL_ROW_BYTES, 12);
        let next=Span::new(LITERAL_PAGE_LEN*3,LITERAL_PAGE_LEN*3+2);
        let tight=crate::SettingAdmission::new(&used,retained+page_bytes-1,&||Ok(()));
        assert_eq!(facts.append_actual(next,data.clone(),&tight).unwrap_err().kind(),io::ErrorKind::OutOfMemory);
        assert_eq!(facts.rows().len(),LITERAL_PAGE_LEN);
        assert_eq!(used.load(Ordering::Acquire),retained);
        let fault=crate::SettingAdmission::new(&used,retained+page_bytes,&||Err(io::Error::from_raw_os_error(1450)));
        assert_eq!(facts.append_actual(next,data.clone(),&fault).unwrap_err().raw_os_error(),Some(1450));
        let exact=crate::SettingAdmission::new(&used,retained+page_bytes,&||Ok(()));
        facts.append_actual(next,data.clone(),&exact).unwrap();
        assert_eq!(facts.rows().get(0).unwrap().1.raw().unwrap().as_ptr(),first);
        assert_eq!(used.load(Ordering::Acquire),retained+page_bytes);
        facts.seal_actual_frontier(next.end,&exact).unwrap();

        let previous=Span::new(next.start-3,next.start-1);
        let (window,origin)=facts.checked_data_window(Span::new(previous.start,next.end)).unwrap().raw_parts();
        assert_eq!(origin,previous.start);
        assert_eq!(window.iter().map(|row|row.0).collect::<Vec<_>>(),[previous,next]);
        assert_eq!(window.partition_point(|row|row.0.start<next.start),1);
        assert!(window.get(1).unwrap().1.same_owner(&data));
        assert!(window.range(1..2).unwrap().get(0).unwrap().1.same_owner(&data));
        assert!(window.range(1..3).is_none());
        assert!(facts.checked_data_window(Span::new(next.start+1,next.end)).is_err());

        let alias=facts.clone();
        drop(facts);
        assert_eq!(used.load(Ordering::Acquire),retained+page_bytes);
        drop((alias,data));
        assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
    }
    #[cfg(target_pointer_width = "64")]
    #[test]
    fn literal_fact_pages_preserve_wide_spans_and_refuse_unfunded_fallback() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let healthy = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut facts = OriginalPrimaryLiteralFacts::new(&healthy).unwrap();
        let data = crate::OriginalLiteralData::from_value_using(
            "7".into(), crate::OriginalTokenValue::Int(7), &healthy,
        ).unwrap();
        let edge = u32::MAX as usize;
        let narrow = Span::new(edge - 1, edge + 1);
        let crossing = Span::new(narrow.end, narrow.end + MAX_WIDTH + 1);
        let distant = narrow.start + MAX_START_DELTA + 1;
        let wide = Span::new(distant, distant + 1);
        facts.append_actual(narrow, data.clone(), &healthy).unwrap();
        let narrow_data = facts.rows().get(0).unwrap().1.raw().unwrap().as_ptr();
        let before = used.load(Ordering::Acquire);
        let denied = crate::SettingAdmission::new(&used, before + 2 * mem::size_of::<Span>() - 1, &|| Ok(()));
        assert_eq!(facts.append_actual(crossing, data.clone(), &denied).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(used.load(Ordering::Acquire), before);
        assert_eq!(facts.rows().len(), 1);

        facts.append_actual(crossing, data.clone(), &healthy).unwrap();
        facts.append_actual(wide, data.clone(), &healthy).unwrap();
        assert_eq!(used.load(Ordering::Acquire), before + 2 * mem::size_of::<Span>());
        assert_eq!(facts.rows().get(0).unwrap().1.raw().unwrap().as_ptr(), narrow_data);
        facts.seal_actual_frontier(wide.end, &healthy).unwrap();
        let (all, _) = facts.checked_data_window(Span::new(narrow.start, wide.end)).unwrap().raw_parts();
        assert!(all.iter().all(|(_, retained)| retained.same_owner(&data)));
        assert_eq!(all.iter().map(|(span, _)| span).collect::<Vec<_>>(), [narrow, crossing, wide]);
        assert_eq!(all.partition_point(|(span, _)| span.start < wide.start), 2);
        let page = &facts.payload().rows.chunks[0].pages[0];
        assert_eq!(page.spans[0] & WIDE_BIT, 0, "absolute source coordinates remain full width");
        assert_ne!(page.spans[1] & WIDE_BIT, 0, "wide length keeps exact geometry");
        assert_ne!(page.spans[2] & WIDE_BIT, 0, "wide delta keeps exact geometry");
        let mut visited_wide = false;
        let mut visited_spans = false;
        let mut visited_data = false;
        facts.visit_storage(|ptr, len, capacity| {
            if ptr == page.spans.as_ptr() as usize {
                visited_spans = true;
                assert_eq!(len, 3 * mem::size_of::<u32>());
                assert_eq!(capacity, LITERAL_PAGE_LEN * mem::size_of::<u32>());
            }
            let LiteralPageData::Dense(data) = &page.data else { panic!("partial page is dense") };
            if ptr == data.rows.as_ptr() as usize {
                visited_data = true;
                assert_eq!(len, 3 * mem::size_of::<crate::OriginalLiteralData>());
                assert_eq!(capacity, LITERAL_PAGE_LEN * mem::size_of::<crate::OriginalLiteralData>());
            }
            if ptr == facts.payload().rows.chunks[0].pages[0].wide.as_ptr() as usize {
                visited_wide = true;
                assert_eq!(len, 2 * mem::size_of::<Span>());
                assert_eq!(capacity, len);
            }
        });
        assert!(visited_wide && visited_spans && visited_data);
        drop((facts, data));
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

 #[test]
 fn body_page_projection_is_atomic_paid_and_visible_without_source_until_bound(){
  assert_eq!(mem::size_of::<crate::original_literal_projection::ProjectedLiteral>(),8);
  struct Output{credit:crate::SettingRootLease}
  impl crate::OriginalLiteralOutputOwner for Output{
   fn as_any(&self)->&dyn std::any::Any{self}
   fn release(self:Arc<Self>){if let Some(value)=Arc::into_inner(self){drop(value)}}
   fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize,usize)){let n=mem::size_of::<Self>()+2*mem::size_of::<usize>();visit(self as *const _ as usize,n,n);self.credit.visit_counter_storage(|p,n|visit(p,n,n))}
  }
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let output=crate::OriginalLiteralProjectionOwner::from_output_data(Arc::new(Output{credit:a.reserve(mem::size_of::<Output>()+2*mem::size_of::<usize>()).unwrap()}));
  let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.enable_projection(output).unwrap();
  let mut source=String::new();
  for i in 0..256{
   let raw=format!("\"{}-{i}\"","z".repeat(1100));let start=source.len();source.push_str(&raw);source.push('\n');
   let data=crate::OriginalLiteralData::from_value_with_mode_using(raw.clone(),crate::OriginalTokenValue::String(&raw[1..raw.len()-1]),crate::OriginalStringMode::Normal,&a).unwrap();
   facts.append_actual(Span::new(start,start+raw.len()),data,&a).unwrap();
  }
  let before=used.load(Ordering::Acquire);let line=Span::new(0,source.len());
  let denied=crate::SettingAdmission::new(&used,before,&||Ok(()));
  facts.project_body_line(line,true,&source,&denied).unwrap();
  assert!(facts.rows().iter().all(|(_,data)|!data.is_projected()),"optional staging denial leaves full rows live");
  // The caller retries a new settled page, not a source pull/reparse. Reset
  // only the internal scan cursor for this targeted storage control.
  Arc::get_mut(facts.0.as_mut().unwrap()).unwrap().next_body_row=0;
  facts.project_body_line(line,true,&source,&a).unwrap();
  assert!(used.load(Ordering::Acquire)+200_000<before,"actual unique owner credits are physically reclaimed before EOF");
  facts.seal_actual_frontier(source.len(),&a).unwrap();
  let rows=facts.rows();assert_eq!(rows.len(),256);let(span,data)=rows.get(13).unwrap();assert!(data.is_projected());
  assert_eq!(data.raw().err().unwrap().kind(),io::ErrorKind::NotConnected);
  assert_eq!(data.value().err().unwrap().kind(),io::ErrorKind::NotConnected);
  assert_eq!(data.detach_using(&a).err().unwrap().kind(),io::ErrorKind::NotConnected);
  let bound=facts.checked_data_window(line).unwrap().with_source_data(&source).unwrap();
  let same=bound.raw_parts().0.get(13).unwrap().1;assert!(data.same_owner(same));
  assert_eq!(same.raw().unwrap(),&source[span.range()]);assert_eq!(same.raw().unwrap().as_ptr(),source[span.range()].as_ptr());
  let full_bytes=used.load(Ordering::Acquire);let detached=same.detach_using(&a).unwrap();
  assert!(detached.as_view().same_owner(same));assert!(used.load(Ordering::Acquire)>full_bytes);
  drop(bound);drop(facts);assert!(detached.raw().ends_with("-13\""));drop(detached);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[cfg(debug_assertions)]
 #[test]
 fn compact_body_bank_withdrawal_pays_descriptors_and_keeps_mixed_survivor() {
    struct Output;
    impl crate::OriginalLiteralOutputOwner for Output {
        fn as_any(&self) -> &dyn std::any::Any { self }
        fn release(self: Arc<Self>) { drop(Arc::into_inner(self)); }
        fn visit_storage(&self, _: &mut dyn FnMut(usize, usize, usize)) {}
    }

    for whole_group in [false, true] {
        let fixed = crate::SettingChargeCounter::root_allocation_bytes();
        let used = crate::SettingChargeCounter::try_new(fixed).unwrap();
        let a = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let output = crate::OriginalLiteralProjectionOwner::from_output_data(Arc::new(Output));
        let mut page = LiteralPage::new(0, &a).unwrap();
        let mut source = String::new();
        let mut issued: Vec<_> = (0..4).map(|index| {
            let raw = format!("\"{}-{index}\"", "body".repeat(24));
            let start = source.len();
            source.push_str(&raw);
            source.push('\n');
            let value = if !whole_group && index == 0 {
                crate::OriginalTokenValue::String("different cooked")
            } else {
                crate::OriginalTokenValue::String(&raw[1..raw.len()-1])
            };
            let data = crate::OriginalLiteralData::from_value_with_mode_using(
                raw.clone(), value, crate::OriginalStringMode::Normal, &a,
            ).unwrap();
            (Span::new(start, start + raw.len()), Some(data))
        }).collect();
        let mut slots: Vec<_> = issued.iter_mut().map(|(_, data)| data.take()).collect();
        crate::OriginalLiteralData::pack_delivery_batch_using(&mut slots, &a).unwrap();
        let packed_key = slots[0].as_ref().unwrap().as_view().page_storage_identity().unwrap();
        let survivor_pointer = slots[0].as_ref().unwrap().raw().as_ptr();
        let total_owner_bytes = slots[0].as_ref().unwrap().as_view().trace_payload().1;
        let raw_bytes: usize = slots[1..].iter().map(|data| data.as_ref().unwrap().raw_storage().capacity()).sum();
        for ((span, _), data) in issued.into_iter().zip(slots) {
            page.push((span, data.unwrap()), &a).unwrap();
        }
        let filler = crate::OriginalLiteralData::from_value_using(
            "0".to_owned(), crate::OriginalTokenValue::Int(0), &a,
        ).unwrap();
        for _ in 4..LITERAL_PAGE_LEN {
            let start = source.len();
            source.push_str("0\n");
            page.push((Span::new(start, start+1), filler.clone()), &a).unwrap();
        }
        page.body[0] = 0b1111;
        page.data.settle_full_using(&a).unwrap();

        let escaped = page.get(0).unwrap().1.detach_using(&a).unwrap();
        let before = used.load(Ordering::Acquire);
        assert!(page.settle_packed_body_projection(&source, &a).unwrap().is_none());
        assert_eq!(used.load(Ordering::Acquire), before);
        assert_eq!(escaped.raw().as_ptr(), survivor_pointer);
        drop(escaped);

        let denied = crate::SettingAdmission::new(&used, before, &|| Ok(()));
        assert!(page.settle_packed_body_projection(&source, &denied).unwrap().is_none());
        assert_eq!(used.load(Ordering::Acquire), before);
        assert_eq!(page.get(0).unwrap().1.raw().unwrap().as_ptr(), survivor_pointer);

        let second_pointer = page.get(1).unwrap().1.raw().unwrap().as_ptr();
        let fault = || Err(io::Error::from_raw_os_error(1450));
        let failing = crate::SettingAdmission::new(&used, 8 << 20, &fault);
        let LiteralPageData::Compact(compact) = &mut page.data else { panic!("compact bank") };
        let bank = (compact.codes[1] & 255) as usize;
        let ordinal = compact.codes[1] >> 8;
        let incomplete = compact.owners[bank].withdraw_packed_using(1 << ordinal, true, &a).unwrap_err();
        assert_eq!(incomplete.kind(), io::ErrorKind::InvalidData);
        let error = compact.owners[bank].withdraw_packed_using(1 << ordinal, false, &failing).unwrap_err();
        assert_eq!(error.raw_os_error(), Some(1450));
        assert_eq!(used.load(Ordering::Acquire), before);
        assert_eq!(page.get(1).unwrap().1.raw().unwrap().as_ptr(), second_pointer);

        let (count, released, old, new) = page.settle_packed_body_projection(&source, &a).unwrap().unwrap();
        assert_eq!(count, if whole_group { 4 } else { 3 });
        assert_eq!(released, if whole_group { total_owner_bytes } else { raw_bytes });
        assert_eq!(used.load(Ordering::Acquire), before + new - old - released);
        let loan = ProjectionLoan { source: &source, origin: 0 };
        for index in usize::from(!whole_group)..4 {
            let (_, unbound) = page.get_data(index, 0, None, Some(&output)).unwrap();
            assert!(unbound.is_projected());
            assert_eq!(unbound.raw().unwrap_err().kind(), io::ErrorKind::NotConnected);
            let (span, bound) = page.get_data(index, 0, Some(loan), Some(&output)).unwrap();
            assert_eq!(bound.raw().unwrap().as_ptr(), source[span.range()].as_ptr());
        }
        if !whole_group {
            let (_, survivor) = page.get(0).unwrap();
            assert_eq!(survivor.page_storage_identity(), Some(packed_key));
            assert_eq!(survivor.raw().unwrap().as_ptr(), survivor_pointer);
            assert!(matches!(survivor.value().unwrap(), crate::OriginalTokenValue::String("different cooked")));
            survivor.visit_storage(|_, _, _| {});
        }
        drop((page, filler, output));
        assert_eq!(used.load(Ordering::Acquire), fixed);
    }
 }
}
