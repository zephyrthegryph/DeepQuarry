//! Ordered immutable typed segments with bounded fallible reads and overlays.
use crate::typed_pages::{TypedPages,PageHandle};
use serde::{Serialize,de::DeserializeOwned};
use std::{collections::BTreeMap,io,ops::Range,sync::{Arc,Mutex}};
fn invalid(message:&'static str)->io::Error {io::Error::new(io::ErrorKind::InvalidData,message)}
pub enum TableSegment<T> {
    Resident(Arc<[T]>),
    Addressed {store:Arc<Mutex<TypedPages<T>>>,page:PageHandle},
}
impl<T> Clone for TableSegment<T> {fn clone(&self)->Self {match self {
    Self::Resident(rows)=>Self::Resident(Arc::clone(rows)),
    Self::Addressed {store,page}=>Self::Addressed {store:Arc::clone(store),page:page.clone()},
}}}
impl<T> TableSegment<T> {fn len(&self)->usize {match self {Self::Resident(rows)=>rows.len(),Self::Addressed {page,..}=>page.rows}}}
pub struct TypedTable<T> {segments:Vec<TableSegment<T>>,starts:Vec<usize>,rows:usize,tail:Vec<T>,overlays:BTreeMap<usize,T>,backing:Option<Arc<Mutex<TypedPages<T>>>>}
impl<T> Default for TypedTable<T> {fn default()->Self {Self {segments:Vec::new(),starts:Vec::new(),rows:0,tail:Vec::new(),overlays:BTreeMap::new(),backing:None}}}
impl<T:Clone+Serialize+DeserializeOwned> TypedTable<T> {
    pub fn from_rows(rows:Vec<T>)->Self {let mut table=Self::default();if !rows.is_empty() {table.starts.push(0);table.rows=rows.len();table.segments.push(TableSegment::Resident(rows.into()));}table}
    pub fn with_backing(mut self,backing:Option<Arc<Mutex<TypedPages<T>>>>)->Self {self.backing=backing;self}
    pub fn flush_backing(&self)->io::Result<()> {
        let mut seen=std::collections::BTreeSet::new();
        for store in self.backing.iter().chain(self.segments.iter().filter_map(|segment|match segment {TableSegment::Addressed {store,..}=>Some(store),_=>None})) {
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
            TableSegment::Addressed {store,page}=>{let mut store=store.lock().map_err(|_|invalid("typed page store lock poisoned"))?;
                Ok(store.read_page(page)?.get(offset).ok_or_else(||invalid("typed page row missing"))?.clone())}}
    }
    pub fn range(&self,start:usize,end:usize)->io::Result<Vec<T>> {
        if start>end||end>self.len()||end-start>1024 {return Err(invalid("typed row range exceeds bound"));}
        (start..end).map(|index|self.get(index)).collect()
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
    pub fn append_segments(&mut self,segments:Vec<TableSegment<T>>)->io::Result<Range<usize>> {
        let added=segments.iter().try_fold(0usize,|sum,segment|sum.checked_add(segment.len())).ok_or_else(||invalid("typed table size overflow"))?;
        let start=self.len();let end=start.checked_add(added).ok_or_else(||invalid("typed table size overflow"))?;
        u32::try_from(end).map_err(io::Error::other)?;self.seal_tail()?;
        for segment in segments {if segment.len()==0 {continue;}self.starts.push(self.rows);self.rows+=segment.len();self.segments.push(segment);}Ok(start..end)
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
    pub fn persist_range(&self,store:&TypedPages<T>,start:usize,end:usize)->io::Result<Vec<PageHandle>> {
        let rows=self.range(start,end)?;let groups:Vec<_>=rows.chunks(256).collect();store.write_pages(&groups)
    }
    pub fn materialize(&self)->io::Result<Vec<T>> {let mut rows=Vec::with_capacity(self.len());for start in (0..self.len()).step_by(1024) {rows.extend(self.range(start,(start+1024).min(self.len()))?);}Ok(rows)}
    pub fn resident_bytes(&self)->usize {self.backing.as_ref().map(|store|store.lock().unwrap_or_else(|e|e.into_inner()).resident_bytes()).unwrap_or(0)+self.tail.capacity()*std::mem::size_of::<T>()+self.segments.capacity()*std::mem::size_of::<TableSegment<T>>()
        +self.starts.capacity()*std::mem::size_of::<usize>()+self.overlays.len()*(std::mem::size_of::<T>()+64)
        +self.segments.iter().map(|segment|match segment {TableSegment::Resident(rows)=>rows.len()*std::mem::size_of::<T>(),TableSegment::Addressed {page,..}=>page.digest.capacity()+96}).sum::<usize>()}
}
