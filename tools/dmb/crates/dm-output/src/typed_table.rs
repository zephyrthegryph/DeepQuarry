//! Ordered immutable typed segments with bounded fallible reads and overlays.
use crate::typed_pages::{TypedPages,PageHandle};
use serde::{Serialize,Deserialize,de::DeserializeOwned};
use std::{collections::BTreeMap,io,ops::Range,sync::{Arc,Mutex}};
fn invalid(message:&'static str)->io::Error {io::Error::new(io::ErrorKind::InvalidData,message)}
pub enum TableSegment<T> {
    Resident(Arc<[T]>),
    ResidentRange {rows:Arc<[T]>,start:usize,end:usize},
    Addressed {store:Arc<Mutex<TypedPages<T>>>,page:PageHandle},
    AddressedRange {store:Arc<Mutex<TypedPages<T>>>,page:PageHandle,start:usize,end:usize},
}
impl<T> Clone for TableSegment<T> {fn clone(&self)->Self {match self {
    Self::Resident(rows)=>Self::Resident(Arc::clone(rows)),
    Self::ResidentRange {rows,start,end}=>Self::ResidentRange {rows:rows.clone(),start:*start,end:*end},
    Self::Addressed {store,page}=>Self::Addressed {store:Arc::clone(store),page:page.clone()},
    Self::AddressedRange {store,page,start,end}=>Self::AddressedRange {store:store.clone(),page:page.clone(),start:*start,end:*end},
}}}
#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct PageSliceRef {pub page:PageHandle,pub start:usize,pub end:usize}
impl<T> TableSegment<T> {
 fn len(&self)->usize {match self {Self::Resident(rows)=>rows.len(),Self::Addressed {page,..}=>page.rows,Self::ResidentRange {start,end,..}|Self::AddressedRange {start,end,..}=>end.saturating_sub(*start)}}
 fn valid(&self)->bool {match self {Self::ResidentRange {rows,start,end}=>start<=end&&*end<=rows.len(),Self::AddressedRange {page,start,end,..}=>start<=end&&*end<=page.rows,_=>true}}
 fn slice(&self,start:usize,end:usize)->Self {match self {
  Self::Resident(rows)=>Self::ResidentRange {rows:rows.clone(),start,end},
  Self::ResidentRange {rows,start:base,..}=>Self::ResidentRange {rows:rows.clone(),start:base+start,end:base+end},
  Self::Addressed {store,page}=>Self::AddressedRange {store:store.clone(),page:page.clone(),start,end},
  Self::AddressedRange {store,page,start:base,..}=>Self::AddressedRange {store:store.clone(),page:page.clone(),start:base+start,end:base+end},
 }}
}
pub struct TypedTable<T> {segments:Vec<TableSegment<T>>,starts:Vec<usize>,rows:usize,tail:Vec<T>,overlays:BTreeMap<usize,T>,backing:Option<Arc<Mutex<TypedPages<T>>>>}
impl<T> Default for TypedTable<T> {fn default()->Self {Self {segments:Vec::new(),starts:Vec::new(),rows:0,tail:Vec::new(),overlays:BTreeMap::new(),backing:None}}}
impl<T:Clone+Serialize+DeserializeOwned> TypedTable<T> {
    pub fn from_rows(rows:Vec<T>)->Self {let mut table=Self::default();if !rows.is_empty() {table.starts.push(0);table.rows=rows.len();table.segments.push(TableSegment::Resident(rows.into()));}table}
    pub fn with_backing(mut self,backing:Option<Arc<Mutex<TypedPages<T>>>>)->Self {self.backing=backing;self}
    pub fn flush_backing(&self)->io::Result<()> {
        let mut seen=std::collections::BTreeSet::new();
        for store in self.backing.iter().chain(self.segments.iter().filter_map(|segment|match segment {TableSegment::Addressed {store,..}|TableSegment::AddressedRange {store,..}=>Some(store),_=>None})) {
            if seen.insert(Arc::as_ptr(store) as usize) {store.lock().map_err(|_|invalid("typed store poisoned"))?.flush()?;}
        }Ok(())
    }
    pub fn len(&self)->usize {self.rows+self.tail.len()}
    pub fn is_empty(&self)->bool {self.len()==0}
    pub fn get(&self,index:usize)->io::Result<T> {
        if index>=self.len() {return Err(invalid("typed row index out of range"));}
        if let Some(row)=self.overlays.get(&index) {return Ok(row.clone());}
        if index>=self.rows {return Ok(self.tail[index-self.rows].clone());}
        let segment=self.starts.partition_point(|start|*start<=index)-1;let offset=index-self.starts[segment];
        match &self.segments[segment] {TableSegment::Resident(rows)=>Ok(rows[offset].clone()),
            TableSegment::ResidentRange {rows,start,..}=>Ok(rows[start+offset].clone()),
            TableSegment::AddressedRange {store,page,start,..}=>Ok(store.lock().map_err(|_|invalid("typed store poisoned"))?.read_page(page)?.get(start+offset).ok_or_else(||invalid("typed page row missing"))?.clone()),
            TableSegment::Addressed {store,page}=>{let mut store=store.lock().map_err(|_|invalid("typed page store lock poisoned"))?;
                Ok(store.read_page(page)?.get(offset).ok_or_else(||invalid("typed page row missing"))?.clone())}}
    }
    pub fn range(&self,start:usize,end:usize)->io::Result<Vec<T>> {
        if start>end||end>self.len()||end-start>1024 {return Err(invalid("typed row range exceeds bound"));}
        let mut output=Vec::with_capacity(end-start);
        let mut cursor=start;
        while cursor<end && cursor<self.rows {
            let segment_index=self.starts.partition_point(|base|*base<=cursor)-1;
            let base=self.starts[segment_index];
            let segment=&self.segments[segment_index];
            let stop=end.min(base+segment.len());
            let local=cursor-base..stop-base;
            match segment {
                TableSegment::Resident(rows)=>output.extend_from_slice(&rows[local]),
                TableSegment::ResidentRange {rows,start,..}=>output.extend_from_slice(&rows[start+local.start..start+local.end]),
                TableSegment::Addressed {store,page}=>{
                    let rows=store.lock().map_err(|_|invalid("typed store poisoned"))?.read_page(page)?;
                    output.extend_from_slice(rows.get(local).ok_or_else(||invalid("typed page range missing"))?);
                }
                TableSegment::AddressedRange {store,page,start,..}=>{
                    let rows=store.lock().map_err(|_|invalid("typed store poisoned"))?.read_page(page)?;
                    output.extend_from_slice(rows.get(start+local.start..start+local.end).ok_or_else(||invalid("typed page range missing"))?);
                }
            }
            cursor=stop;
        }
        if cursor<end {output.extend_from_slice(&self.tail[cursor-self.rows..end-self.rows]);}
        for (&index,row) in self.overlays.range(start..end) {output[index-start]=row.clone();}
        Ok(output)
    }
    pub fn append(&mut self,row:T)->io::Result<u32> {let index=u32::try_from(self.len()).map_err(io::Error::other)?;self.tail.push(row);if self.tail.len()>=256 {self.seal_tail()?;}Ok(index)}
    pub fn replace(&mut self,index:usize,row:T)->io::Result<()> {
        if index>=self.len() {return Err(invalid("typed replacement index out of range"));}
        if index>=self.rows {self.tail[index-self.rows]=row;}else {self.overlays.insert(index,row);}Ok(())
    }
    fn seal_tail(&mut self)->io::Result<()> {
        if self.tail.is_empty() {return Ok(());}
        let segment=if let Some(store)=&self.backing {
            let page=store.lock().map_err(|_|invalid("typed store poisoned"))?.stage_page(&self.tail)?;
            TableSegment::Addressed {store:Arc::clone(store),page}
        }else {TableSegment::Resident(self.tail.clone().into())};
        self.starts.push(self.rows);self.rows+=self.tail.len();self.tail.clear();self.segments.push(segment);Ok(())
    }
    pub fn backing_store(&self)->Option<Arc<Mutex<TypedPages<T>>>> {self.backing.clone()}
    pub fn prepare_append_segments(&mut self,segments:&[TableSegment<T>])->io::Result<Range<usize>> {
        if segments.iter().any(|segment|!segment.valid()) {return Err(invalid("invalid typed segment slice"));}
        let added=segments.iter().try_fold(0usize,|sum,segment|sum.checked_add(segment.len())).ok_or_else(||invalid("typed table size overflow"))?;
        let start=self.len();let end=start.checked_add(added).ok_or_else(||invalid("typed table size overflow"))?;
        u32::try_from(end).map_err(io::Error::other)?;self.seal_tail()?;
        Ok(start..end)
    }
    pub fn append_segments(&mut self,segments:Vec<TableSegment<T>>)->io::Result<Range<usize>> {
        let range=self.prepare_append_segments(&segments)?;
        for segment in segments {if segment.len()==0 {continue;}self.starts.push(self.rows);self.rows+=segment.len();self.segments.push(segment);}Ok(range)
    }
    pub fn append_page_slices(&mut self,store:Arc<Mutex<TypedPages<T>>>,pages:Vec<PageSliceRef>)->io::Result<Range<usize>> {
        store.lock().map_err(|_|invalid("typed store poisoned"))?.manifest(pages.iter().map(|slice|slice.page.clone()).collect())?;
        self.append_segments(pages.into_iter().map(|slice|TableSegment::AddressedRange {store:store.clone(),page:slice.page,start:slice.start,end:slice.end}).collect())
    }
    pub fn append_pages(&mut self,store:Arc<Mutex<TypedPages<T>>>,pages:Vec<PageHandle>)->io::Result<Range<usize>> {
        store.lock().map_err(|_|invalid("typed page store lock poisoned"))?.manifest(pages.clone())?;
        self.append_segments(pages.into_iter().map(|page|TableSegment::Addressed {store:Arc::clone(&store),page}).collect())
    }
    /// Snapshot preserves immutable segments; overlays are explicit small rows.
    pub fn segments(&mut self)->io::Result<Vec<TableSegment<T>>> {
        self.seal_tail()?;let mut result=Vec::new();
        for (index,segment) in self.segments.iter().enumerate() {
            let start=self.starts[index];let end=start+segment.len();
            if self.overlays.range(start..end).next().is_none() {result.push(segment.clone());}
            else {for at in (start..end).step_by(256) {result.push(TableSegment::Resident(self.range(at,(at+256).min(end))?.into()));}}
        }Ok(result)
    }
    /// Shares whole immutable pages; only cut edges and pages with actual overlays are rebuilt.
    pub fn slice_segments(&self,start:usize,end:usize)->io::Result<Vec<TableSegment<T>>> {
        if start>end||end>self.len() {return Err(invalid("typed segment range out of bounds"));}
        let mut result=Vec::new();
        let first=self.starts.partition_point(|base|*base<=start).saturating_sub(1);
        for (index,segment) in self.segments.iter().enumerate().skip(first) {
            let base=self.starts[index];if base>=end {break;}let limit=base+segment.len();let lo=start.max(base);let hi=end.min(limit);
            if lo>=hi {continue;}
            if self.overlays.range(lo..hi).next().is_none() {result.push(segment.slice(lo-base,hi-base));continue;}
            for at in (lo..hi).step_by(256) {let rows=self.range(at,(at+256).min(hi))?;
                let piece=if let Some(store)=&self.backing {let page=store.lock().map_err(|_|invalid("typed store poisoned"))?.stage_page(&rows)?;TableSegment::Addressed {store:Arc::clone(store),page}}
                    else {TableSegment::Resident(rows.into())};result.push(piece);
            }
        }
        let lo=start.max(self.rows);if lo<end {for at in (lo..end).step_by(256) {result.push(TableSegment::Resident(self.range(at,(at+256).min(end))?.into()));}}
        Ok(result)
    }
    /// Portable durable page references in the caller-selected schema/store.
    /// Reuses pages already belonging to that store; bounded edge rows are staged.
    pub fn export_page_refs(&self,store:Arc<Mutex<TypedPages<T>>>,start:usize,end:usize)->io::Result<Vec<PageHandle>> {
        let segments=self.slice_segments(start,end)?;let mut pages=Vec::new();
        for segment in segments {match segment {
            TableSegment::Addressed {store:source,page} if Arc::ptr_eq(&source,&store)=>pages.push(page),
            TableSegment::Addressed {store:source,page}=>{let rows=source.lock().map_err(|_|invalid("typed store poisoned"))?.read_page(&page)?;
                pages.push(store.lock().map_err(|_|invalid("typed store poisoned"))?.stage_page(&rows)?);},
            TableSegment::ResidentRange {rows,start,end}=>{for chunk in rows[start..end].chunks(256) {pages.push(store.lock().map_err(|_|invalid("typed store poisoned"))?.stage_page(chunk)?);}},
            TableSegment::AddressedRange {store:source,page,start,end}=>{let rows=source.lock().map_err(|_|invalid("typed store poisoned"))?.read_page(&page)?;pages.push(store.lock().map_err(|_|invalid("typed store poisoned"))?.stage_page(&rows[start..end])?);},
            TableSegment::Resident(rows)=>{for chunk in rows.chunks(256) {pages.push(store.lock().map_err(|_|invalid("typed store poisoned"))?.stage_page(chunk)?);}}
        }}
        store.lock().map_err(|_|invalid("typed store poisoned"))?.flush()?;Ok(pages)
    }
    /// Prove an immutable prefix without decoding addressed pages. A layout
    /// mismatch rejects the acceleration; callers can use their ordinary read
    /// path. Existing overlays are compared exactly, never just by row count.
    pub fn same_prefix_as(&self,prefix:&Self)->bool where T:PartialEq {
        if self.len()<prefix.len()||self.overlays.range(..prefix.len()).ne(prefix.overlays.iter()) {return false;}
        fn same<T:PartialEq>(left:&TableSegment<T>,left_at:usize,right:&TableSegment<T>,right_at:usize,len:usize)->bool {
            fn resident<T>(segment:&TableSegment<T>)->Option<(&Arc<[T]>,usize)> {match segment {
                TableSegment::Resident(rows)=>Some((rows,0)),TableSegment::ResidentRange {rows,start,..}=>Some((rows,*start)),_=>None,
            }}
            fn addressed<T>(segment:&TableSegment<T>)->Option<(&PageHandle,usize)> {match segment {
                TableSegment::Addressed {page,..}=>Some((page,0)),TableSegment::AddressedRange {page,start,..}=>Some((page,*start)),_=>None,
            }}
            if let (Some((a,base_a)),Some((b,base_b)))=(resident(left),resident(right)) {
                let a_at=base_a+left_at;let b_at=base_b+right_at;
                return (Arc::ptr_eq(a,b)&&a_at==b_at)||matches!((a.get(a_at..a_at+len),b.get(b_at..b_at+len)),(Some(a),Some(b)) if a==b);
            }
            if let (Some((a,base_a)),Some((b,base_b)))=(addressed(left),addressed(right)) {
                return a==b&&base_a+left_at==base_b+right_at;
            }
            false
        }
        let mut cursor=0;
        while cursor<prefix.rows {
            if cursor>=self.rows {return false;}
            let a=self.starts.partition_point(|start|*start<=cursor)-1;
            let b=prefix.starts.partition_point(|start|*start<=cursor)-1;
            let left_at=cursor-self.starts[a];let right_at=cursor-prefix.starts[b];
            let len=(self.segments[a].len()-left_at).min(prefix.segments[b].len()-right_at);
            if !same(&self.segments[a],left_at,&prefix.segments[b],right_at,len) {return false;}cursor+=len;
        }
        // A mutable tail is bounded by the table's seal threshold. Snapshot
        // composition can turn it into a resident segment; compare actual rows.
        prefix.tail.len()<=1024&&prefix.tail.iter().enumerate().all(|(offset,row)|self.get(prefix.rows+offset).is_ok_and(|current|current==*row))
    }
    pub fn shared_snapshot(&self)->io::Result<Self> {let segments=self.slice_segments(0,self.len())?;let mut table=Self::default().with_backing(self.backing.clone());table.append_segments(segments)?;Ok(table)}
    pub fn snapshot(&mut self)->io::Result<Self> {let segments=self.segments()?;self.flush_backing()?;let mut result=Self::default().with_backing(self.backing.clone());result.append_segments(segments)?;Ok(result)}
    pub fn address_resident_segments(&mut self)->io::Result<()> {
        let Some(store)=self.backing.clone() else {return Err(io::Error::new(io::ErrorKind::Unsupported,"typed table backing missing"));};
        let segments=self.segments()?;let mut addressed=Vec::new();
        for segment in segments {match segment {
            TableSegment::Resident(rows)=>{for chunk in rows.chunks(256) {let page=store.lock().map_err(|_|invalid("typed store poisoned"))?.stage_page(chunk)?;addressed.push(TableSegment::Addressed {store:store.clone(),page});}},
            TableSegment::ResidentRange {rows,start,end}=>{for chunk in rows[start..end].chunks(256) {let page=store.lock().map_err(|_|invalid("typed store poisoned"))?.stage_page(chunk)?;addressed.push(TableSegment::Addressed {store:store.clone(),page});}},
            other=>addressed.push(other),
        }}
        store.lock().map_err(|_|invalid("typed store poisoned"))?.flush()?;
        self.segments=addressed;self.starts.clear();self.rows=0;self.overlays.clear();for segment in &self.segments {self.starts.push(self.rows);self.rows+=segment.len();}Ok(())
    }
    pub fn export_portable_slices(&self,start:usize,end:usize)->io::Result<Vec<PageSliceRef>> {
        let backing=self.backing.clone().ok_or_else(||invalid("typed export backing missing"))?;
        let mut result=Vec::new();
        for segment in self.slice_segments(start,end)? {match segment {
            TableSegment::Addressed {page,..}=>{let end=page.rows;result.push(PageSliceRef {page,start:0,end});},
            TableSegment::AddressedRange {page,start,end,..}=>result.push(PageSliceRef {page,start,end}),
            TableSegment::Resident(rows)=>{for chunk in rows.chunks(256) {let page=backing.lock().map_err(|_|invalid("typed store poisoned"))?.stage_page(chunk)?;let end=page.rows;result.push(PageSliceRef {page,start:0,end});}},
            TableSegment::ResidentRange {rows,start,end}=>{for chunk in rows[start..end].chunks(256) {let page=backing.lock().map_err(|_|invalid("typed store poisoned"))?.stage_page(chunk)?;let end=page.rows;result.push(PageSliceRef {page,start:0,end});}},
        }}
        backing.lock().map_err(|_|invalid("typed store poisoned"))?.flush()?;Ok(result)
    }
    pub fn export_page_slices(&self,start:usize,end:usize)->io::Result<Vec<PageSliceRef>> {
        let mut result=Vec::new();
        for segment in self.slice_segments(start,end)? {match segment {
            TableSegment::Addressed {store,page}=>{store.lock().map_err(|_|invalid("typed store poisoned"))?.flush()?;let end=page.rows;result.push(PageSliceRef {page,start:0,end});},
            TableSegment::AddressedRange {store,page,start,end}=>{store.lock().map_err(|_|invalid("typed store poisoned"))?.flush()?;result.push(PageSliceRef {page,start,end});},
            _=>return Err(io::Error::new(io::ErrorKind::Unsupported,"resident typed slice requires explicit page export")),
        }}Ok(result)
    }
    pub fn persist_range(&self,store:&TypedPages<T>,start:usize,end:usize)->io::Result<Vec<PageHandle>> {
        let rows=self.range(start,end)?;let groups:Vec<_>=rows.chunks(256).collect();store.write_pages(&groups)
    }
    pub fn materialize(&self)->io::Result<Vec<T>> {let mut rows=Vec::with_capacity(self.len());for start in (0..self.len()).step_by(1024) {rows.extend(self.range(start,(start+1024).min(self.len()))?);}Ok(rows)}
    pub fn resident_bytes(&self)->usize {
        let mut stores=std::collections::BTreeSet::new();let mut residents=std::collections::BTreeSet::new();let mut shared=0;
        for store in self.backing.iter().chain(self.segments.iter().filter_map(|segment|match segment {TableSegment::Addressed {store,..}|TableSegment::AddressedRange {store,..}=>Some(store),_=>None})) {
            if stores.insert(Arc::as_ptr(store) as usize) {shared+=store.lock().unwrap_or_else(|e|e.into_inner()).resident_bytes();}
        }
        for segment in &self.segments {if let TableSegment::Resident(rows)|TableSegment::ResidentRange {rows,..}=segment {if residents.insert(rows.as_ptr() as usize) {shared+=rows.len()*std::mem::size_of::<T>();}}}
        shared+self.tail.capacity()*std::mem::size_of::<T>()+self.segments.capacity()*std::mem::size_of::<TableSegment<T>>()
            +self.starts.capacity()*std::mem::size_of::<usize>()+self.overlays.len()*(std::mem::size_of::<T>()+64)
            +self.segments.iter().map(|segment|match segment {TableSegment::Resident(_)|TableSegment::ResidentRange {..}=>0,TableSegment::Addressed {page,..}|TableSegment::AddressedRange {page,..}=>page.digest.capacity()+96}).sum::<usize>()
    }
}
