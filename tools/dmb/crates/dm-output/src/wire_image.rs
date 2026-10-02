//! Physical images with fallible addressed list objects. No logical Dmb is
//! exposed until all actual lists have been explicitly materialized.
use byond_dmb::dmb::{Dmb,ListWords,ChunkedDmb,DmbWireCache,WireListSource,ReferenceValidatedImage,Proc,Variable,WireRecordSource};
use serde::{Serialize,Deserialize};
use sha2::{Digest,Sha256};
use std::{collections::HashMap,io,ops::Range,path::{Path,PathBuf},sync::{Arc,Mutex}};
const WINDOW:usize=1024;
const ROW_WINDOW:usize=4096;
const BUDGET:usize=8*1024*1024;
fn invalid(message:&'static str)->io::Error {io::Error::new(io::ErrorKind::InvalidData,message)}
#[derive(Clone,Serialize,Deserialize)]
pub struct VerifiedCodeHandle {digest:String,words:usize,width:usize}
impl VerifiedCodeHandle {
    pub fn digest(&self)->&str {&self.digest}
    pub fn word_count(&self)->usize {self.words}
    pub fn object_width(&self)->usize {self.width}
    fn valid(&self)->bool {self.digest.len()==64&&self.digest.bytes().all(|c|c.is_ascii_hexdigit())
        &&self.words<=u16::MAX as usize&&matches!(self.width,2|4)}
}
#[derive(Clone)]
pub enum ListObject {Resident(ListWords),Addressed(VerifiedCodeHandle)}
#[derive(Default)]
struct ReadWindow {rows:HashMap<String,Arc<[u8]>>,bytes:usize}
#[derive(Default)]
struct PendingWrites {rows:Vec<dm_store::Change>,bytes:usize}
#[derive(Default,Clone,Copy)]
pub struct CodeIoStats {pub windows:usize,pub bytes:usize,pub read_seconds:f64}
pub struct CodeObjectStore {root:PathBuf,io_stats:Mutex<CodeIoStats>,store:dm_store::Store,window:Mutex<ReadWindow>,pending:Mutex<PendingWrites>,lookahead:Mutex<Vec<VerifiedCodeHandle>>}
impl CodeObjectStore {
    pub fn open(root:&Path)->io::Result<Arc<Self>> {Ok(Arc::new(Self {
        root:root.to_owned(),io_stats:Mutex::new(CodeIoStats::default()),store:dm_store::Store::open(root.join("wire-list-objects.redb"))?,window:Mutex::new(ReadWindow::default()),pending:Mutex::new(PendingWrites::default()),lookahead:Mutex::new(Vec::new())}))}
    pub fn cache_root(&self)->&Path {&self.root}
    pub fn io_stats(&self)->CodeIoStats {*self.io_stats.lock().unwrap_or_else(|error|error.into_inner())}
    fn namespace()->&'static str {"wire-list-object-v1"}
    pub fn resident_bytes(&self)->usize {self.window.lock().unwrap_or_else(|e|e.into_inner()).bytes
        +self.pending.lock().unwrap_or_else(|e|e.into_inner()).bytes
        +self.lookahead.lock().unwrap_or_else(|e|e.into_inner()).len()*128}
    pub fn clear(&self) { *self.window.lock().unwrap_or_else(|e|e.into_inner())=ReadWindow::default(); }
    pub fn set_lookahead(&self,handles:Vec<VerifiedCodeHandle>)->io::Result<()> {
        if handles.len()>WINDOW||handles.iter().any(|h|!h.valid()) {return Err(invalid("invalid wire code lookahead"));}
        *self.lookahead.lock().unwrap_or_else(|e|e.into_inner())=handles;Ok(())
    }
    pub fn persist_batch(&self,rows:&[(&[u32],usize)])->io::Result<Vec<VerifiedCodeHandle>> {
        if rows.len()>WINDOW {return Err(invalid("wire list write window exceeds bound"));}
        let mut changes=Vec::new();let mut handles=Vec::new();let mut total=0usize;
        for &(words,width) in rows {
            let bytes=encode(words,width)?;total+=bytes.len();
            if total>BUDGET {return Err(invalid("wire list write byte window exceeds bound"));}
            let digest=format!("{:x}",Sha256::digest(&bytes));
            changes.push((dm_store::Key::new(Self::namespace(),&digest),bytes));
            handles.push(VerifiedCodeHandle {digest,words:words.len(),width});
        }
        self.store.put_many(changes,None)?;Ok(handles)
    }
    pub fn persist_words(&self,words:&[u32],width:usize)->io::Result<VerifiedCodeHandle> {
        self.persist_batch(&[(words,width)])?.pop().ok_or_else(||invalid("empty wire list write"))
    }
    /// Derived objects share bounded transactions, instead of committing once
    /// for every freshly compiled procedure. Locators may safely miss after an
    /// interrupted cache flush; final output publication still verifies bytes.
    pub fn stage_words(&self,words:&[u32],width:usize)->io::Result<VerifiedCodeHandle> {
        self.stage_encoded(encode(words,width)?,width)
    }
    /// Stage a projected raw object after checked schema relocation. Shape,
    /// width and digest are proved here before admitting its addressed handle.
    pub fn stage_encoded(&self,bytes:Vec<u8>,width:usize)->io::Result<VerifiedCodeHandle> {
        let count=bytes.get(..2).ok_or_else(||invalid("wire list length missing"))?;
        let words=u16::from_le_bytes(count.try_into().unwrap()) as usize;
        let digest=format!("{:x}",Sha256::digest(&bytes));
        let handle=VerifiedCodeHandle {digest:digest.clone(),words,width};
        validate_bytes(&handle,&bytes)?;
        let mut pending=self.pending.lock().unwrap_or_else(|e|e.into_inner());
        if pending.bytes.saturating_add(bytes.len())>BUDGET||pending.rows.len()>=8192 {
            self.store.commit(&[],&pending.rows,None)?;*pending=PendingWrites::default();
        }
        pending.bytes+=bytes.len();pending.rows.push(dm_store::Change::Put(dm_store::Key::new(Self::namespace(),digest),bytes));Ok(handle)
    }
    pub fn flush(&self)->io::Result<()> {
        let mut pending=self.pending.lock().unwrap_or_else(|e|e.into_inner());
        if !pending.rows.is_empty() {self.store.commit(&[],&pending.rows,None)?;*pending=PendingWrites::default();}Ok(())
    }
    /// One bounded ownership session, before serial composition consumes rows.
    pub fn prefetch(&self,handles:&[VerifiedCodeHandle])->io::Result<()> {
        let next=self.read_owned(handles)?;
        *self.window.lock().unwrap_or_else(|e|e.into_inner())=next;Ok(())
    }
    /// Owned exact read observation; independent of the synchronous replay cache.
    fn read_owned(&self,handles:&[VerifiedCodeHandle])->io::Result<ReadWindow> {
        if handles.len()>WINDOW||handles.iter().any(|h|!h.valid()) {return Err(invalid("invalid wire list read window"));}
        let keys:Vec<_>=handles.iter().map(|h|dm_store::Key::new(Self::namespace(),&h.digest)).collect();
        let started=std::time::Instant::now();
        let batch=self.store.read_many_bounded(&keys,2+u16::MAX as usize*4,BUDGET,None)?;
        {let mut stats=self.io_stats.lock().unwrap_or_else(|error|error.into_inner());stats.windows+=1;
            stats.bytes+=batch.values.iter().filter_map(|value|value.as_ref()).map(Vec::len).sum::<usize>();stats.read_seconds+=started.elapsed().as_secs_f64();}
        let mut next=ReadWindow::default();
        for ((handle,bytes),witness) in handles.iter().zip(batch.values).zip(batch.witnesses) {
            let bytes=bytes.ok_or_else(||invalid("missing wire list object"))?;
            if witness.value_digest.as_deref()!=Some(handle.digest.as_str()) {return Err(invalid("wire list digest mismatch"));}
            validate_bytes(handle,&bytes)?;
            if !next.rows.contains_key(&handle.digest) {next.bytes+=bytes.len()+handle.digest.len()+128;next.rows.insert(handle.digest.clone(),bytes.into());}
        }
        if next.bytes>BUDGET+WINDOW*256 {return Err(invalid("wire list resident window exceeds bound"));}
        Ok(next)
    }
    pub fn restore(&self,handle:&VerifiedCodeHandle)->io::Result<Arc<[u8]>> {
        if !handle.valid() {return Err(invalid("invalid wire list handle"));}
        if let Some(bytes)=self.window.lock().unwrap_or_else(|e|e.into_inner()).rows.get(&handle.digest).cloned() {
            validate_bytes(handle,&bytes)?;return Ok(bytes);
        }
        let nearby={let handles=self.lookahead.lock().unwrap_or_else(|e|e.into_inner());
            if let Some(start)=handles.iter().position(|h|h.digest==handle.digest) {
                let mut end=start;let mut bytes=0;while end<handles.len() {
                    let charge=2+handles[end].words*handles[end].width;
                    if end>start&&bytes+charge>BUDGET {break;}bytes+=charge;end+=1;
                }handles[start..end].to_vec()
            } else {vec![handle.clone()]}};
        self.prefetch(&nearby)?;
        self.window.lock().unwrap_or_else(|e|e.into_inner()).rows.get(&handle.digest).cloned().ok_or_else(||invalid("missing prefetched wire list"))
    }
}
fn encode(words:&[u32],width:usize)->io::Result<Vec<u8>> {
    if words.len()>u16::MAX as usize||!matches!(width,2|4) {return Err(invalid("wire list shape exceeds bound"));}
    let mut bytes=Vec::with_capacity(2+words.len()*width);bytes.extend_from_slice(&(words.len() as u16).to_le_bytes());
    for &word in words {if width==2 {bytes.extend_from_slice(&u16::try_from(word).map_err(|_|invalid("narrow list operand overflow"))?.to_le_bytes());}
        else {bytes.extend_from_slice(&word.to_le_bytes());}}
    Ok(bytes)
}
fn validate_bytes(handle:&VerifiedCodeHandle,bytes:&[u8])->io::Result<()> {
    if !handle.valid()||bytes.len()!=2+handle.words*handle.width||bytes.get(..2)!=Some((handle.words as u16).to_le_bytes().as_slice()) {
        return Err(invalid("wire list object shape mismatch"));
    } Ok(())
}
#[derive(Clone)]
pub struct ListSourceSegment {rows:Arc<[ListObject]>,store:Option<Arc<CodeObjectStore>>}
impl ListSourceSegment {
 pub fn len(&self)->usize {self.rows.len()}
 pub fn resident_bytes(&self)->usize {self.rows.len()*std::mem::size_of::<ListObject>()+self.rows.iter().map(|row|match row {ListObject::Resident(words)=>words.capacity()*4,ListObject::Addressed(handle)=>handle.digest.capacity()}).sum::<usize>()}
}
pub struct ListObjectTable {rows:Vec<ListObject>,store:Option<Arc<CodeObjectStore>>}
impl ListObjectTable {
    pub fn new(store:Option<Arc<CodeObjectStore>>)->Self {Self {rows:Vec::new(),store}}
    pub fn len(&self)->usize {self.rows.len()}
    pub fn append_resident(&mut self,words:impl Into<ListWords>)->usize {let id=self.len();self.rows.push(ListObject::Resident(words.into()));id}
    pub fn append_verified(&mut self,handle:VerifiedCodeHandle)->io::Result<usize> {
        if !handle.valid()||self.store.is_none() {return Err(invalid("wire list handle lacks store"));}
        let id=self.len();self.rows.push(ListObject::Addressed(handle));Ok(id)
    }
    pub fn source_segments(&mut self,start:usize,end:usize)->io::Result<Vec<ListSourceSegment>> {
        if start>end||end>self.len() {return Err(invalid("list source range out of bounds"));}
        for row in &mut self.rows[start..end] {if let ListObject::Resident(words)=row {if let ListWords::Owned(_)=words {let old=std::mem::take(words);if let ListWords::Owned(owned)=old {*words=ListWords::Shared(owned.into());}}}}
        Ok(self.rows[start..end].chunks(256).map(|rows|ListSourceSegment {rows:rows.to_vec().into(),store:self.store.clone()}).collect())
    }
    pub fn prepare_append_source_segments(&self,segments:&[ListSourceSegment])->io::Result<Range<usize>> {
        let mut store=self.store.clone();let start=self.len();let count=segments.iter().try_fold(0usize,|count,segment|count.checked_add(segment.len())).ok_or_else(||invalid("list source count overflow"))?;
        let end=start.checked_add(count).ok_or_else(||invalid("list source count overflow"))?;u32::try_from(end).map_err(io::Error::other)?;
        for segment in segments {if segment.rows.iter().any(|row|matches!(row,ListObject::Addressed(_))) {
            let candidate=segment.store.as_ref().ok_or_else(||invalid("addressed list segment lacks store"))?;
            if store.as_ref().is_some_and(|old|!Arc::ptr_eq(old,candidate)) {return Err(invalid("foreign addressed list segment"));}store=Some(candidate.clone());
            if segment.rows.iter().any(|row|matches!(row,ListObject::Addressed(handle) if !handle.valid())) {return Err(invalid("invalid addressed list segment"));}
        }}
        Ok(start..end)
    }
    pub fn append_source_segments(&mut self,segments:Vec<ListSourceSegment>)->io::Result<Range<usize>> {
        let range=self.prepare_append_source_segments(&segments)?;
        if self.store.is_none() {self.store=segments.iter().find_map(|segment|segment.store.clone());}
        for segment in segments {self.rows.extend(segment.rows.iter().cloned());}Ok(range)
    }
    pub fn prepare_range(&self,range:Range<usize>)->io::Result<()> {
        if range.end>self.len()||range.start>range.end||range.len()>ROW_WINDOW {return Err(invalid("wire list preparation range exceeds bound"));}
        let handles:Vec<_>=self.rows[range].iter().filter_map(|row|match row {ListObject::Addressed(h)=>Some(h.clone()),_=>None}).collect();
        if handles.is_empty() {return Ok(());}
        if handles.len()>WINDOW {return Err(invalid("wire code handle count exceeds bound"));}
        let store=self.store.as_ref().ok_or_else(||invalid("wire list store missing"))?;
        if handles.iter().map(|h|2+h.words*h.width).sum::<usize>()>BUDGET {return Err(invalid("wire list preparation byte bound exceeded"));}
        store.prefetch(&handles)
    }
    pub fn read_words(&self,index:usize)->io::Result<ListWords> {
        match self.rows.get(index).ok_or_else(||invalid("wire list index out of bounds"))? {
            ListObject::Resident(words)=>Ok(words.clone()),ListObject::Addressed(h)=>{
                let bytes=self.store.as_ref().ok_or_else(||invalid("wire list store missing"))?.restore(h)?;
                Ok(bytes[2..].chunks_exact(h.width).map(|b|if h.width==2 {u16::from_le_bytes(b.try_into().unwrap()) as u32}
                    else {u32::from_le_bytes(b.try_into().unwrap())}).collect::<Vec<_>>().into())}
        }
    }
    pub fn materialize_mut(&mut self,index:usize)->io::Result<&mut ListWords> {
        if matches!(self.rows.get(index),Some(ListObject::Addressed(_))) {
            let words=self.read_words(index)?;self.rows[index]=ListObject::Resident(words);
        }
        match self.rows.get_mut(index) {Some(ListObject::Resident(words))=>Ok(words),_=>Err(invalid("wire list index out of bounds"))}
    }
}
impl WireListSource for ListObjectTable {
    fn len(&self)->usize {self.len()}
    fn resident_words(&self,index:usize)->Option<&ListWords> {match self.rows.get(index)? {ListObject::Resident(words)=>Some(words),_=>None}}
    fn word_count(&self,index:usize)->io::Result<usize> {match self.rows.get(index).ok_or_else(||invalid("wire list index out of bounds"))? {
        ListObject::Resident(words)=>Ok(words.len()),ListObject::Addressed(h)=>Ok(h.words)}}
    fn read_wire(&self,index:usize,width:usize)->io::Result<Arc<[u8]>> {
        match self.rows.get(index).ok_or_else(||invalid("wire list index out of bounds"))? {
            ListObject::Resident(words)=>Ok(encode(words,width)?.into()),ListObject::Addressed(h)=>{
                if h.width!=width {return Err(invalid("wire list width witness mismatch"));}
                self.store.as_ref().ok_or_else(||invalid("wire list store missing"))?.restore(h)}
        }
    }
    fn prepare_window(&self,start:usize,max_rows:usize)->io::Result<usize> {
        let end=self.window_end(start,max_rows)?;self.prepare_range(start..end)?;Ok(end)
    }
}
impl ListObjectTable {
    fn window_end(&self,start:usize,max_rows:usize)->io::Result<usize> {
        if start>self.len()||max_rows==0 {return Err(invalid("invalid wire source window"));}
        let mut end=start;let mut bytes=0;let mut handles=0;
        while end<self.len()&&end-start<max_rows.min(ROW_WINDOW) {
            let (charge,addressed)=match &self.rows[end] {ListObject::Resident(_)=>(0,0),ListObject::Addressed(h)=>(2+h.words*h.width,1)};
            if end>start&&(bytes+charge>BUDGET||handles+addressed>WINDOW) {break;}
            bytes+=charge;handles+=addressed;end+=1;
        }
        Ok(end)
    }
}
/// A rendezvous owns at most current + producer code windows. Disconnect
/// drops the pending read and terminates the scoped producer on every error.
struct PipelinedLists<'a> {
    lists:&'a ListObjectTable,
    receiver:Mutex<std::sync::mpsc::Receiver<io::Result<(usize,usize,ReadWindow)>>>,
    current:Mutex<(usize,usize,ReadWindow)>,
}
impl WireListSource for PipelinedLists<'_> {
    fn len(&self)->usize {self.lists.len()}
    fn word_count(&self,index:usize)->io::Result<usize> {self.lists.word_count(index)}
    fn resident_words(&self,index:usize)->Option<&ListWords> {self.lists.resident_words(index)}
    fn read_wire(&self,index:usize,width:usize)->io::Result<Arc<[u8]>> {
        match self.lists.rows.get(index).ok_or_else(||invalid("pipelined list index out of range"))? {
            ListObject::Resident(words)=>Ok(encode(words,width)?.into()),
            ListObject::Addressed(handle)=>{
                if handle.width!=width {return Err(invalid("pipelined list width mismatch"));}
                let current=self.current.lock().map_err(|_|invalid("pipelined source lock poisoned"))?;
                if index<current.0||index>=current.1 {return Err(invalid("pipelined list outside current window"));}
                let bytes=current.2.rows.get(handle.digest()).cloned().ok_or_else(||invalid("pipelined code object missing"))?;
                validate_bytes(handle,&bytes)?;Ok(bytes)
            }
        }
    }
    fn prepare_window(&self,start:usize,max_rows:usize)->io::Result<usize> {
        let expected=self.lists.window_end(start,max_rows)?;
        // The preceding window is fully consumed before accepting the next.
        // Release it first so the producer cannot race into a third live page.
        *self.current.lock().map_err(|_|invalid("pipelined source lock poisoned"))?=(0,0,ReadWindow::default());
        let next=self.receiver.lock().map_err(|_|invalid("pipelined receiver lock poisoned"))?.recv()
            .map_err(|_|io::Error::new(io::ErrorKind::BrokenPipe,"code source producer disconnected"))??;
        if next.0!=start||next.1!=expected {return Err(invalid("pipelined source order mismatch"));}
        *self.current.lock().map_err(|_|invalid("pipelined source lock poisoned"))?=next;Ok(expected)
    }
}
#[derive(Serialize,Deserialize)]
pub struct PhysicalSnapshot {version:u32,metadata:Dmb,lists:Vec<SnapshotList>,procs:Vec<crate::typed_table::PageSliceRef>,variables:Vec<crate::typed_table::PageSliceRef>}
#[derive(Serialize,Deserialize)]
enum SnapshotList {Resident(ListWords),Addressed(VerifiedCodeHandle)}
#[derive(Clone,Copy,Serialize,Deserialize,PartialEq,Eq)]
pub struct PhysicalRangeCursor {pub header_flags:u32,pub procs:usize,pub variables:usize,pub lists:usize,pub strings:usize,pub references:usize,pub instances:usize}
#[derive(Serialize,Deserialize)]
pub struct PhysicalRange {start:PhysicalRangeCursor,end:PhysicalRangeCursor,procs:Vec<crate::typed_table::PageSliceRef>,variables:Vec<crate::typed_table::PageSliceRef>,lists:Vec<SnapshotList>,strings:Vec<byond_dmb::dmb::DmString>,references:Vec<u32>,instances:Vec<byond_dmb::dmb::Instance>}
impl PhysicalRange {pub fn end(&self)->PhysicalRangeCursor {self.end} pub fn strings(&self)->&[byond_dmb::dmb::DmString] {&self.strings} pub fn start(&self)->PhysicalRangeCursor {self.start}}
pub struct WireImage {metadata:Dmb,lists:ListObjectTable,procs:crate::typed_table::TypedTable<Proc>,variables:crate::typed_table::TypedTable<Variable>}
/// Exact live suffix of an immutable declaration prefix. The guard checks
/// every other physical input; matching dense lengths alone is insufficient.
#[derive(Serialize)]
pub struct BindingAppendDelta<'a> {
    resources:&'a [byond_dmb::dmb::ResourceRef],
    strings:&'a [byond_dmb::dmb::DmString],
    base_strings:usize,base_variables:usize,base_procedures:usize,
    variables:Vec<Variable>,procedures:Vec<Proc>,
}
/// Mutable physical assembly. Actual list objects occupy every table slot;
/// code handles never masquerade as empty logical lists.
pub struct WireImageBuilder {pub(crate) metadata:Dmb,pub(crate) lists:ListObjectTable,pub(crate) procs:crate::typed_table::TypedTable<Proc>,pub(crate) variables:crate::typed_table::TypedTable<Variable>}
impl WireImageBuilder {
    pub fn from_native(mut image:Dmb,store:Option<Arc<CodeObjectStore>>)->Self {
        // Canonical assembly uses one fixed physical operand width, independent
        // of edit history and later table growth. Native import stays exact.
        image.header.flags|=0x4000_0000;
        let lists=std::mem::take(&mut image.lists);
        let procs=crate::typed_table::TypedTable::from_rows(std::mem::take(&mut image.procs)).with_backing(store.as_ref().and_then(|store|crate::typed_pages::TypedPages::open(&store.root,"wire-proc-v1",1024*1024,|_|0).ok()).map(|pages|Arc::new(Mutex::new(pages))));
        let variables=crate::typed_table::TypedTable::from_rows(std::mem::take(&mut image.variables)).with_backing(store.as_ref().and_then(|store|crate::typed_pages::TypedPages::open(&store.root,"wire-variable-v1",1024*1024,|_|0).ok()).map(|pages|Arc::new(Mutex::new(pages))));
        Self {metadata:image,procs,variables,lists:ListObjectTable {rows:lists.into_iter().map(ListObject::Resident).collect(),store}}
    }
    pub fn range_cursor(&self)->PhysicalRangeCursor {PhysicalRangeCursor {header_flags:self.metadata.header.flags,procs:self.procs.len(),variables:self.variables.len(),lists:self.lists.len(),strings:self.metadata.strings.len(),references:self.metadata.proc_references.len(),instances:self.metadata.instances.len()}}
    pub fn export_range(&mut self,start:PhysicalRangeCursor)->io::Result<PhysicalRange> {
        let end=self.range_cursor();
        if end.header_flags&!0x4000_0000!=start.header_flags&!0x4000_0000 {return Err(invalid("physical range changes unsupported header flags"));}
        if start.procs>end.procs||start.variables>end.variables||start.lists>end.lists||start.strings>end.strings||start.references>end.references||start.instances>end.instances {return Err(invalid("invalid physical range cursor"));}
        let procs=self.procs.export_portable_slices(start.procs,end.procs)?;let variables=self.variables.export_portable_slices(start.variables,end.variables)?;
        let mut lists=Vec::with_capacity(end.lists-start.lists);
        let width=if self.metadata.header.flags&0x4000_0000!=0 {4}else {2};
        for row in &self.lists.rows[start.lists..] {lists.push(match row {ListObject::Addressed(handle)=>SnapshotList::Addressed(handle.clone()),ListObject::Resident(words)=>match &self.lists.store {Some(store)=>SnapshotList::Addressed(store.stage_words(words,width)?),None=>SnapshotList::Resident(words.clone())}});}
        if let Some(store)=&self.lists.store {store.flush()?;}
        Ok(PhysicalRange {start,end,procs,variables,lists,strings:self.metadata.strings[start.strings..].to_vec(),references:self.metadata.proc_references[start.references..].to_vec(),instances:self.metadata.instances[start.instances..].to_vec()})
    }
    pub fn append_range(&mut self,range:&PhysicalRange)->io::Result<()> {
        if self.range_cursor()!=range.start {return Err(invalid("physical range allocation mismatch"));}
        if range.end.header_flags&!0x4000_0000!=range.start.header_flags&!0x4000_0000 {return Err(invalid("unsupported physical range header flags"));}
        let proc_count=range.procs.iter().try_fold(0usize,|n,p|n.checked_add(p.end.checked_sub(p.start)?)).ok_or_else(||invalid("invalid proc page range"))?;
        let variable_count=range.variables.iter().try_fold(0usize,|n,p|n.checked_add(p.end.checked_sub(p.start)?)).ok_or_else(||invalid("invalid variable page range"))?;
        for (start,added,end) in [(range.start.procs,proc_count,range.end.procs),(range.start.variables,variable_count,range.end.variables),(range.start.lists,range.lists.len(),range.end.lists),(range.start.strings,range.strings.len(),range.end.strings),(range.start.references,range.references.len(),range.end.references),(range.start.instances,range.instances.len(),range.end.instances)] {if start.checked_add(added)!=Some(end) {return Err(invalid("physical range shape mismatch"));}}
        let promotes=[self.metadata.classes.len(),self.metadata.mobs.len(),self.metadata.map_objects.len(),self.metadata.resources.len(),range.end.procs,range.end.variables,range.end.lists,range.end.strings,range.end.references,range.end.instances].into_iter().any(|count|count>u16::MAX as usize);
        let expected_flags=range.start.header_flags|if promotes {0x4000_0000}else {0};
        if range.end.header_flags!=expected_flags {return Err(invalid("physical range header promotion mismatch"));}
        let store=self.lists.store.clone().ok_or_else(||invalid("physical range requires addressed store"))?;
        // Construct and validate all source slices before mutating the target.
        let proc_store=self.procs.backing_store().ok_or_else(||invalid("physical range proc backing missing"))?;
        let variable_store=self.variables.backing_store().ok_or_else(||invalid("physical range variable backing missing"))?;
        let mut procs=crate::typed_table::TypedTable::default().with_backing(Some(proc_store.clone()));procs.append_page_slices(proc_store,range.procs.clone())?;
        let mut variables=crate::typed_table::TypedTable::default().with_backing(Some(variable_store.clone()));variables.append_page_slices(variable_store,range.variables.clone())?;
        let mut lists=ListObjectTable::new(Some(store));for row in &range.lists {match row {SnapshotList::Resident(words)=>{lists.append_resident(words.clone());},SnapshotList::Addressed(handle)=>{lists.append_verified(handle.clone())?;}}}
        let proc_segments=procs.segments()?;let variable_segments=variables.segments()?;let list_segments=lists.source_segments(0,lists.len())?;
        // Preparation may change tail representation but never logical rows.
        // All backing IO and bounds checks finish before any target append.
        self.procs.prepare_append_segments(&proc_segments)?;self.variables.prepare_append_segments(&variable_segments)?;self.lists.prepare_append_source_segments(&list_segments)?;
        for (current,added) in [(self.metadata.strings.len(),range.strings.len()),(self.metadata.proc_references.len(),range.references.len()),(self.metadata.instances.len(),range.instances.len())] {u32::try_from(current.checked_add(added).ok_or_else(||invalid("physical range count overflow"))?).map_err(io::Error::other)?;}
        self.procs.append_segments(proc_segments)?;self.variables.append_segments(variable_segments)?;self.lists.append_source_segments(list_segments)?;
        self.metadata.strings.extend_from_slice(&range.strings);self.metadata.proc_references.extend_from_slice(&range.references);self.metadata.instances.extend_from_slice(&range.instances);
        crate::assembly::AssemblyImage::promote_object_ids(self);
        Ok(())
    }
    pub fn encode_prefix_to_sink(&self,sink:Box<dyn FnMut(&[u8])->io::Result<()>>)->io::Result<()> {
        self.metadata.encode_physical_to_sink(&self.lists,self,&mut DmbWireCache::default(),sink).map(|_|())
    }
    pub fn resident_bytes(&self)->usize {
        let metadata=&self.metadata;
        std::mem::size_of::<Self>()+self.typed_resident_bytes()+self.lists.rows.capacity()*std::mem::size_of::<ListObject>()
        +self.lists.rows.iter().map(|row|match row {ListObject::Resident(words)=>words.capacity()*4,ListObject::Addressed(handle)=>handle.digest.capacity()}).sum::<usize>()
        +metadata.grid.capacity()*std::mem::size_of::<byond_dmb::dmb::GridRun>()+metadata.classes.capacity()*std::mem::size_of::<byond_dmb::dmb::Class>()
        +metadata.mobs.capacity()*std::mem::size_of::<byond_dmb::dmb::MobType>()+metadata.strings.capacity()*std::mem::size_of::<byond_dmb::dmb::DmString>()+metadata.strings.iter().map(|row|row.data.capacity()).sum::<usize>()
        +metadata.proc_references.capacity()*4+metadata.instances.capacity()*std::mem::size_of::<byond_dmb::dmb::Instance>()+metadata.map_objects.capacity()*std::mem::size_of::<byond_dmb::dmb::MapObject>()+metadata.resources.capacity()*std::mem::size_of::<byond_dmb::dmb::ResourceRef>()
        +metadata.header.version_line.capacity()+metadata.header.compatibility_line.capacity()+metadata.header.executor_line.as_ref().map_or(0,Vec::capacity)
    }
    pub fn freeze_resident_lists(&mut self) {for row in &mut self.lists.rows {if let ListObject::Resident(words)=row {if matches!(words,ListWords::Owned(_)) {let old=std::mem::take(words);if let ListWords::Owned(old)=old {*words=ListWords::Shared(old.into());}}}}}
    pub fn snapshot(&self)->io::Result<Self> {
        let rows=self.lists.rows.iter().map(|row|match row {ListObject::Addressed(handle)=>ListObject::Addressed(handle.clone()),ListObject::Resident(words)=>ListObject::Resident(match words {ListWords::Shared(words)=>ListWords::Shared(words.clone()),ListWords::Owned(words)=>ListWords::Shared(words.clone().into())})}).collect();
        Ok(Self {metadata:self.metadata.clone(),lists:ListObjectTable {rows,store:self.lists.store.clone()},procs:self.procs.shared_snapshot()?,variables:self.variables.shared_snapshot()?})
    }
    pub fn export_snapshot(&mut self)->io::Result<PhysicalSnapshot> {
        self.freeze_resident_lists();self.procs.address_resident_segments()?;self.variables.address_resident_segments()?;
        let procs=self.procs.export_page_slices(0,self.procs.len())?;let variables=self.variables.export_page_slices(0,self.variables.len())?;
        let mut lists=Vec::with_capacity(self.lists.rows.len());
        let width=if self.metadata.header.flags&0x4000_0000!=0 {4}else {2};
        for row in &self.lists.rows {
            lists.push(match row {
                ListObject::Resident(words)=>match &self.lists.store {
                    Some(store)=>SnapshotList::Addressed(store.stage_words(words,width)?),
                    None=>SnapshotList::Resident(words.clone()),
                },
                ListObject::Addressed(handle)=>SnapshotList::Addressed(handle.clone()),
            });
        }
        if let Some(store)=&self.lists.store {store.flush()?;}
        Ok(PhysicalSnapshot {version:1,metadata:self.metadata.clone(),lists,procs,variables})
    }
    pub fn restore_snapshot(snapshot:PhysicalSnapshot,store:Arc<CodeObjectStore>)->io::Result<Self> {
        if snapshot.version!=1||!snapshot.metadata.procs.is_empty()||!snapshot.metadata.variables.is_empty()||!snapshot.metadata.lists.is_empty() {return Err(invalid("invalid physical snapshot metadata"));}
        let proc_store=Arc::new(Mutex::new(crate::typed_pages::TypedPages::open(&store.root,"wire-proc-v1",1024*1024,|_|0)?));
        let variable_store=Arc::new(Mutex::new(crate::typed_pages::TypedPages::open(&store.root,"wire-variable-v1",1024*1024,|_|0)?));
        let mut procs=crate::typed_table::TypedTable::default().with_backing(Some(proc_store.clone()));procs.append_page_slices(proc_store,snapshot.procs)?;
        let mut variables=crate::typed_table::TypedTable::default().with_backing(Some(variable_store.clone()));variables.append_page_slices(variable_store,snapshot.variables)?;
        let mut lists=ListObjectTable::new(Some(store));for row in snapshot.lists {match row {SnapshotList::Resident(words)=>{lists.append_resident(words);},SnapshotList::Addressed(handle)=>{lists.append_verified(handle)?;}}}
        Ok(Self {metadata:snapshot.metadata,lists,procs,variables})
    }
    pub fn append_verified_code(&mut self,handle:VerifiedCodeHandle)->io::Result<u32> {
        if self.lists.len()==0xffff {self.lists.append_resident(Vec::new());}
        let id=u32::try_from(self.lists.append_verified(handle)?).map_err(io::Error::other)?;
        crate::assembly::AssemblyImage::promote_object_ids(self);Ok(id)
    }
    pub fn relink_code(&self,handle:&VerifiedCodeHandle,plan:&crate::wire_relocation::RelocationPlan)->io::Result<VerifiedCodeHandle> {
        if !plan.changed() {return Ok(handle.clone());}
        let store=self.lists.store.as_ref().ok_or_else(||invalid("wire code store missing"))?;
        let bytes=store.restore(handle)?;store.stage_encoded(plan.apply(handle,&bytes)?,handle.object_width())
    }
    pub fn finish(self,cache:&mut byond_dmb::dmb::ReferenceValidationCache)->io::Result<WireImage> {
        if let Some(store)=&self.lists.store {store.flush()?;}
        self.procs.flush_backing()?;self.variables.flush_backing()?;
        self.metadata.validate_physical_sources(&self.lists,&self,cache)?;
        Ok(WireImage {metadata:self.metadata,lists:self.lists,procs:self.procs,variables:self.variables})
    }
    pub fn materialize(&self)->io::Result<Dmb> {
        let mut native=self.metadata.clone();let mut lists=Vec::with_capacity(self.lists.len());let mut until=0;
        for id in 0..self.lists.len() {if id>=until {until=self.lists.prepare_window(id,WINDOW)?;}lists.push(self.lists.read_words(id)?);}
        native.lists=lists.into();native.procs=self.procs.materialize()?;native.variables=self.variables.materialize()?;Ok(native)
    }
}
impl WireImage {
    pub fn from_native(image:Dmb)->io::Result<Self> {Self::from_native_with_validator(image,|image|image.reference_validated(&mut Default::default()))}
    pub fn from_native_with_validator<F>(mut image:Dmb,validate:F)->io::Result<Self>
        where F:for<'a> FnOnce(&'a Dmb)->io::Result<ReferenceValidatedImage<'a>> {
        {let proof=validate(&image)?;if !std::ptr::eq(proof.image(),&image) {return Err(invalid("wire image proof belongs to another image"));}}
        let lists=std::mem::take(&mut image.lists);
        let procs=crate::typed_table::TypedTable::from_rows(std::mem::take(&mut image.procs));
        let variables=crate::typed_table::TypedTable::from_rows(std::mem::take(&mut image.variables));
        Ok(Self {metadata:image,procs,variables,lists:ListObjectTable {rows:lists.into_iter().map(ListObject::Resident).collect(),store:None}})
    }
    pub fn lists(&self)->&ListObjectTable {&self.lists}
    pub fn resources(&self)->&[byond_dmb::dmb::ResourceRef] {&self.metadata.resources}
    /// Replace already certified native list ownership with addressed exact
    /// wire objects. No reference authorization changes during this move.
    pub fn archive_lists(&mut self,store:Arc<CodeObjectStore>)->io::Result<()> {
        if self.lists.rows.iter().any(|row|matches!(row,ListObject::Addressed(_)))
            &&self.lists.store.as_ref().is_none_or(|old|!Arc::ptr_eq(old,&store)) {
            return Err(invalid("wire list objects belong to another store"));
        }
        self.lists.store=Some(Arc::clone(&store));
        let width=if self.metadata.header.flags&0x4000_0000!=0 {4}else{2};
        let mut start=0;
        while start<self.lists.len() {
            let mut end=start;let mut bytes=0usize;
            while end<self.lists.len()&&end-start<WINDOW {
                let charge=match &self.lists.rows[end] {ListObject::Resident(words)=>2+words.len()*width,ListObject::Addressed(_)=>0};
                if end>start&&bytes+charge>BUDGET {break;}bytes+=charge;end+=1;
            }
            let indices:Vec<_>=(start..end).filter(|&id|matches!(&self.lists.rows[id],ListObject::Resident(_))).collect();
            let input:Vec<_>=indices.iter().filter_map(|&id|match &self.lists.rows[id] {ListObject::Resident(words)=>Some((words.as_slice(),width)),_=>None}).collect();
            let handles=store.persist_batch(&input)?;
            for (id,handle) in indices.into_iter().zip(handles) {self.lists.rows[id]=ListObject::Addressed(handle);}
            start=end;
        }
        self.lists.store=Some(store);Ok(())
    }
    pub fn materialize(&self)->io::Result<Dmb> {
        let mut native=self.metadata.clone();let mut words=Vec::with_capacity(self.lists.len());
        let mut prepared_until=0;
        for index in 0..self.lists.len() {
            if index>=prepared_until {prepared_until=self.lists.prepare_window(index,WINDOW)?;}
            words.push(self.lists.read_words(index)?);
        }
        native.lists=words.into();native.procs=self.procs.materialize()?;native.variables=self.variables.materialize()?;Ok(native)
    }
    pub fn serialize_stored(&self,root:&std::path::Path,cache:&mut DmbWireCache)->io::Result<crate::chunks::StoredDmb> {
        let before=self.lists.store.as_ref().map(|store|store.io_stats()).unwrap_or_default();
        let builder=std::sync::Arc::new(std::sync::Mutex::new(crate::chunks::PageBuilder::new(root)));
        let sink=std::sync::Arc::clone(&builder);
        let encode_sink=Box::new(move |bytes:&[u8]|sink.lock().map_err(|_|invalid("page sink lock poisoned"))?.append(bytes));
        let (len,spans)=std::thread::scope(|scope| {
            let (sender,receiver)=std::sync::mpsc::sync_channel(0);
            let producer=scope.spawn(move || {
                let mut start=0;
                while start<self.lists.len() {
                    let end=self.lists.window_end(start,ROW_WINDOW)?;
                    let handles:Vec<_>=self.lists.rows[start..end].iter().filter_map(|row|match row {ListObject::Addressed(handle)=>Some(handle.clone()),_=>None}).collect();
                    let window=if handles.is_empty() {Ok(ReadWindow::default())}else {self.lists.store.as_ref().ok_or_else(||invalid("pipelined code store missing"))?.read_owned(&handles)};
                    let failed=window.is_err();
                    if sender.send(window.map(|window|(start,end,window))).is_err()||failed {return Ok(());}
                    start=end;
                }Ok::<(),io::Error>(())
            });
            let source=PipelinedLists {lists:&self.lists,receiver:Mutex::new(receiver),current:Mutex::new((0,0,ReadWindow::default()))};
            let encoded=self.metadata.encode_physical_to_sink(&source,self,cache,encode_sink);
            drop(source); // unblock a send before joining on encoder failure
            let joined=producer.join().map_err(|_|invalid("code source producer panicked"))?;
            let encoded=encoded?;joined?;Ok::<_,io::Error>(encoded)
        })?;
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            let after=self.lists.store.as_ref().map(|store|store.io_stats()).unwrap_or_default();
            eprintln!("DM_BUILD_TRACE physical code source: windows={} bytes={} read_seconds={:.3}",after.windows-before.windows,after.bytes-before.bytes,after.read_seconds-before.read_seconds);
        }
        std::sync::Arc::try_unwrap(builder).map_err(|_|invalid("page sink still retained"))?
            .into_inner().map_err(|_|invalid("page sink lock poisoned"))?.finish(len,spans)
    }
}
impl WireImageBuilder {
    pub fn append_only_context_delta_from<'a>(&'a self,prefix:&Self)->io::Result<Option<BindingAppendDelta<'a>>> {
        let a=&self.metadata;let b=&prefix.metadata;
        if a.header!=b.header||a.dimensions!=b.dimensions||a.grid!=b.grid||a.classes!=b.classes||a.mobs!=b.mobs
            ||a.variable_footer!=b.variable_footer||a.proc_references!=b.proc_references||a.instances!=b.instances
            ||a.map_objects!=b.map_objects||a.world!=b.world||a.strings.len()<b.strings.len()
            ||a.strings[..b.strings.len()]!=b.strings||self.lists.rows.len()!=prefix.lists.rows.len()
            ||!self.procs.same_prefix_as(&prefix.procs)||!self.variables.same_prefix_as(&prefix.variables) {return Ok(None);}
        for (a,b) in self.lists.rows.iter().zip(&prefix.lists.rows) {
            let same=match (a,b) {
                (ListObject::Resident(a),ListObject::Resident(b))=>a==b,
                (ListObject::Addressed(a),ListObject::Addressed(b))=>a.digest==b.digest&&a.width==b.width&&a.words==b.words,
                _=>false,
            };
            if !same {return Ok(None);}
        }
        let base_variables=prefix.variables.len();let base_procedures=prefix.procs.len();
        if self.variables.len()-base_variables>1024||self.procs.len()-base_procedures>1024 {return Ok(None);}
        Ok(Some(BindingAppendDelta {resources:&a.resources,strings:&a.strings[b.strings.len()..],base_strings:b.strings.len(),
            base_variables,base_procedures,variables:self.variables.range(base_variables,self.variables.len())?,
            procedures:self.procs.range(base_procedures,self.procs.len())?}))
    }
}
impl WireImage {
    pub fn serialize_chunks(&self,cache:&mut DmbWireCache)->io::Result<ChunkedDmb> {
        self.metadata.encode_physical_chunks(&self.lists,self,cache)
    }
}

impl WireRecordSource for WireImageBuilder {
 fn proc_count(&self)->usize {self.procs.len()} fn proc_row(&self,index:usize)->io::Result<Proc> {self.procs.get(index)}
 fn variable_count(&self)->usize {self.variables.len()} fn variable_row(&self,index:usize)->io::Result<Variable> {self.variables.get(index)}
 fn proc_rows(&self,start:usize,end:usize)->io::Result<Vec<Proc>> {self.procs.range(start,end)}
 fn variable_rows(&self,start:usize,end:usize)->io::Result<Vec<Variable>> {self.variables.range(start,end)}
}
impl WireRecordSource for WireImage {
 fn proc_count(&self)->usize {self.procs.len()} fn proc_row(&self,index:usize)->io::Result<Proc> {self.procs.get(index)}
 fn variable_count(&self)->usize {self.variables.len()} fn variable_row(&self,index:usize)->io::Result<Variable> {self.variables.get(index)}
 fn proc_rows(&self,start:usize,end:usize)->io::Result<Vec<Proc>> {self.procs.range(start,end)}
 fn variable_rows(&self,start:usize,end:usize)->io::Result<Vec<Variable>> {self.variables.range(start,end)}
}
impl WireImageBuilder {
 pub fn procedure_segments(&mut self)->io::Result<Vec<crate::typed_table::TableSegment<Proc>>> {self.procs.segments()}
 pub fn variable_segments(&mut self)->io::Result<Vec<crate::typed_table::TableSegment<Variable>>> {self.variables.segments()}
 pub fn append_proc_segments(&mut self,segments:Vec<crate::typed_table::TableSegment<Proc>>)->io::Result<Range<usize>> {let range=self.procs.append_segments(segments)?;crate::assembly::AssemblyImage::promote_object_ids(self);Ok(range)}
 pub fn append_variable_segments(&mut self,segments:Vec<crate::typed_table::TableSegment<Variable>>)->io::Result<Range<usize>> {let range=self.variables.append_segments(segments)?;crate::assembly::AssemblyImage::promote_object_ids(self);Ok(range)}
 pub fn append_proc_pages(&mut self,store:Arc<Mutex<crate::typed_pages::TypedPages<Proc>>>,pages:Vec<crate::typed_pages::PageHandle>)->io::Result<Range<usize>> {let range=self.procs.append_pages(store,pages)?;crate::assembly::AssemblyImage::promote_object_ids(self);Ok(range)}
 pub fn append_variable_pages(&mut self,store:Arc<Mutex<crate::typed_pages::TypedPages<Variable>>>,pages:Vec<crate::typed_pages::PageHandle>)->io::Result<Range<usize>> {let range=self.variables.append_pages(store,pages)?;crate::assembly::AssemblyImage::promote_object_ids(self);Ok(range)}
 pub fn capture_proc_table(&mut self)->io::Result<crate::typed_table::TypedTable<Proc>> {self.procs.snapshot()}
 pub fn capture_variable_table(&mut self)->io::Result<crate::typed_table::TypedTable<Variable>> {self.variables.snapshot()}
 pub fn proc_segments_range(&self,start:usize,end:usize)->io::Result<Vec<crate::typed_table::TableSegment<Proc>>> {self.procs.slice_segments(start,end)}
 pub fn variable_segments_range(&self,start:usize,end:usize)->io::Result<Vec<crate::typed_table::TableSegment<Variable>>> {self.variables.slice_segments(start,end)}
 pub fn list_segments_range(&mut self,start:usize,end:usize)->io::Result<Vec<ListSourceSegment>> {self.lists.source_segments(start,end)}
 pub fn append_list_segments(&mut self,segments:Vec<ListSourceSegment>)->io::Result<Range<usize>> {let range=self.lists.append_source_segments(segments)?;crate::assembly::AssemblyImage::promote_object_ids(self);Ok(range)}
 pub fn typed_resident_bytes(&self)->usize {self.procs.resident_bytes()+self.variables.resident_bytes()}
}
