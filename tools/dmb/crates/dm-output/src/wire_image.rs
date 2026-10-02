//! Physical images with fallible addressed list objects. No logical Dmb is
//! exposed until all actual lists have been explicitly materialized.
use byond_dmb::dmb::{Dmb,ListWords,ChunkedDmb,DmbWireCache,WireListSource,ReferenceValidatedImage};
use serde::{Serialize,Deserialize};
use sha2::{Digest,Sha256};
use std::{collections::HashMap,io,ops::Range,path::Path,sync::{Arc,Mutex}};
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
pub enum ListObject {Resident(ListWords),Addressed(VerifiedCodeHandle)}
#[derive(Default)]
struct ReadWindow {rows:HashMap<String,Arc<[u8]>>,bytes:usize}
#[derive(Default)]
struct PendingWrites {rows:Vec<dm_store::Change>,bytes:usize}
#[derive(Default,Clone,Copy)]
pub struct CodeIoStats {pub windows:usize,pub bytes:usize,pub read_seconds:f64}
pub struct CodeObjectStore {io_stats:Mutex<CodeIoStats>,store:dm_store::Store,window:Mutex<ReadWindow>,pending:Mutex<PendingWrites>,lookahead:Mutex<Vec<VerifiedCodeHandle>>}
impl CodeObjectStore {
    pub fn open(root:&Path)->io::Result<Arc<Self>> {Ok(Arc::new(Self {
        io_stats:Mutex::new(CodeIoStats::default()),store:dm_store::Store::open(root.join("wire-list-objects.redb"))?,window:Mutex::new(ReadWindow::default()),pending:Mutex::new(PendingWrites::default()),lookahead:Mutex::new(Vec::new())}))}
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
        *self.window.lock().unwrap_or_else(|e|e.into_inner())=next;Ok(())
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
pub struct ListObjectTable {rows:Vec<ListObject>,store:Option<Arc<CodeObjectStore>>}
impl ListObjectTable {
    pub fn new(store:Option<Arc<CodeObjectStore>>)->Self {Self {rows:Vec::new(),store}}
    pub fn len(&self)->usize {self.rows.len()}
    pub fn append_resident(&mut self,words:impl Into<ListWords>)->usize {let id=self.len();self.rows.push(ListObject::Resident(words.into()));id}
    pub fn append_verified(&mut self,handle:VerifiedCodeHandle)->io::Result<usize> {
        if !handle.valid()||self.store.is_none() {return Err(invalid("wire list handle lacks store"));}
        let id=self.len();self.rows.push(ListObject::Addressed(handle));Ok(id)
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
        let mut end=start;let mut bytes=0;let mut handles=0;
        while end<self.len()&&end-start<max_rows.min(ROW_WINDOW) {
            let (charge,addressed)=match &self.rows[end] {ListObject::Resident(_)=>(0,0),ListObject::Addressed(h)=>(2+h.words*h.width,1)};
            if end>start&&(bytes+charge>BUDGET||handles+addressed>WINDOW) {break;}
            bytes+=charge;handles+=addressed;end+=1;
        }
        self.prepare_range(start..end)?;Ok(end)
    }
}
pub struct WireImage {metadata:Dmb,lists:ListObjectTable}
/// Mutable physical assembly. Actual list objects occupy every table slot;
/// code handles never masquerade as empty logical lists.
pub struct WireImageBuilder {pub(crate) metadata:Dmb,pub(crate) lists:ListObjectTable}
impl WireImageBuilder {
    pub fn from_native(mut image:Dmb,store:Option<Arc<CodeObjectStore>>)->Self {
        // Canonical assembly uses one fixed physical operand width, independent
        // of edit history and later table growth. Native import stays exact.
        image.header.flags|=0x4000_0000;
        let lists=std::mem::take(&mut image.lists);
        Self {metadata:image,lists:ListObjectTable {rows:lists.into_iter().map(ListObject::Resident).collect(),store}}
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
        self.metadata.validate_metadata_with_lists(&self.lists,cache)?;
        Ok(WireImage {metadata:self.metadata,lists:self.lists})
    }
    pub fn materialize(&self)->io::Result<Dmb> {
        let mut native=self.metadata.clone();let mut lists=Vec::with_capacity(self.lists.len());let mut until=0;
        for id in 0..self.lists.len() {if id>=until {until=self.lists.prepare_window(id,WINDOW)?;}lists.push(self.lists.read_words(id)?);}
        native.lists=lists.into();Ok(native)
    }
}
impl WireImage {
    pub fn from_native(image:Dmb)->io::Result<Self> {Self::from_native_with_validator(image,|image|image.reference_validated(&mut Default::default()))}
    pub fn from_native_with_validator<F>(mut image:Dmb,validate:F)->io::Result<Self>
        where F:for<'a> FnOnce(&'a Dmb)->io::Result<ReferenceValidatedImage<'a>> {
        {let proof=validate(&image)?;if !std::ptr::eq(proof.image(),&image) {return Err(invalid("wire image proof belongs to another image"));}}
        let lists=std::mem::take(&mut image.lists);
        Ok(Self {metadata:image,lists:ListObjectTable {rows:lists.into_iter().map(ListObject::Resident).collect(),store:None}})
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
        native.lists=words.into();Ok(native)
    }
    pub fn serialize_stored(&self,root:&std::path::Path,cache:&mut DmbWireCache)->io::Result<crate::chunks::StoredDmb> {
        let before=self.lists.store.as_ref().map(|store|store.io_stats()).unwrap_or_default();
        let builder=std::sync::Arc::new(std::sync::Mutex::new(crate::chunks::PageBuilder::new(root)));
        let sink=std::sync::Arc::clone(&builder);
        let (len,spans)=self.metadata.encode_metadata_to_sink(&self.lists,cache,Box::new(move |bytes| {
            sink.lock().map_err(|_|invalid("page sink lock poisoned"))?.append(bytes)
        }))?;
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            let after=self.lists.store.as_ref().map(|store|store.io_stats()).unwrap_or_default();
            eprintln!("DM_BUILD_TRACE physical code source: windows={} bytes={} read_seconds={:.3}",after.windows-before.windows,after.bytes-before.bytes,after.read_seconds-before.read_seconds);
        }
        std::sync::Arc::try_unwrap(builder).map_err(|_|invalid("page sink still retained"))?
            .into_inner().map_err(|_|invalid("page sink lock poisoned"))?.finish(len,spans)
    }
    pub fn serialize_chunks(&self,cache:&mut DmbWireCache)->io::Result<ChunkedDmb> {
        self.metadata.encode_metadata_with_lists(&self.lists,cache)
    }
}
