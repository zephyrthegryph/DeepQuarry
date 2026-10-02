//! Bounded addressed typed table pages shared by linker and analysis consumers.
//! Manifests hold page handles rather than eagerly decoded namespace snapshots.
use serde::{Serialize, Deserialize, de::DeserializeOwned};
use sha2::{Digest,Sha256};
use std::{collections::{BTreeMap,BTreeSet},io,path::Path,sync::Arc};
const MAX_ROWS: usize=256;
const MAX_ENCODED: usize=1024*1024;
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PageHandle {pub digest:String,pub rows:usize,pub encoded_bytes:usize,pub resident_bytes:usize}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TableManifest {pub version:u32,pub schema:String,pub pages:Vec<PageHandle>,pub rows:usize}
pub struct IndexedTable {manifest:TableManifest,starts:Vec<usize>}
impl IndexedTable {pub fn manifest(&self)->&TableManifest {&self.manifest}}
pub struct RowView<T> {page:Arc<[T]>,index:usize}
impl<T> std::ops::Deref for RowView<T> {type Target=T;fn deref(&self)->&T {&self.page[self.index]}}
struct Cached<T> {page:Arc<[T]>,charge:usize,encoded_bytes:usize,tick:u64}
pub struct TypedPages<T> {
    store:dm_store::Store,schema:String,budget:usize,bytes:usize,clock:u64,
    cache:BTreeMap<String,Cached<T>>,lru:BTreeSet<(u64,String)>,
    row_charge:fn(&T)->usize,pending:BTreeMap<String,Vec<u8>>,pending_bytes:usize,
}
fn invalid(message:&'static str)->io::Error {io::Error::new(io::ErrorKind::InvalidData,message)}
fn valid_digest(digest:&str)->bool {digest.len()==64 && digest.bytes().all(|byte|byte.is_ascii_hexdigit())}
impl<T:Serialize+DeserializeOwned> TypedPages<T> {
    pub fn open(root:&Path,schema:&str,budget:usize,row_charge:fn(&T)->usize)->io::Result<Self> {
        if schema.is_empty() || schema.len()>256 {return Err(invalid("invalid typed page schema"));}
        Ok(Self {store:dm_store::Store::open(root.join("typed-output-pages.redb"))?,schema:schema.to_owned(),
            budget,bytes:0,clock:0,cache:BTreeMap::new(),lru:BTreeSet::new(),row_charge,pending:BTreeMap::new(),pending_bytes:0})
    }
    fn namespace(&self)->String {format!("typed-page-v1-{}",format!("{:x}",Sha256::digest(self.schema.as_bytes())))}
    pub fn resident_bytes(&self)->usize {self.bytes+self.pending_bytes+self.pending.len()*128}
    pub fn clear_decoded(&mut self) {self.cache.clear();self.lru.clear();self.bytes=0;}
    fn encode_page(&self,rows:&[T])->io::Result<(PageHandle,Vec<u8>)> {
        if rows.is_empty() || rows.len()>MAX_ROWS {return Err(invalid("typed page row bound exceeded"));}
        let bytes=rmp_serde::to_vec(rows).map_err(io::Error::other)?;
        if bytes.len()>MAX_ENCODED {return Err(invalid("typed page byte bound exceeded"));}
        let resident_bytes=rows.iter().try_fold(rows.len()*std::mem::size_of::<T>(),|sum,row|
            sum.checked_add((self.row_charge)(row))).ok_or_else(||invalid("typed page size overflow"))?;
        if resident_bytes.saturating_add(256)>self.budget {return Err(invalid("typed page exceeds resident budget"));}
        let digest=format!("{:x}",Sha256::digest(&bytes));
        Ok((PageHandle {digest,rows:rows.len(),encoded_bytes:bytes.len(),resident_bytes},bytes))
    }
    /// One bounded transaction per caller-selected page window, never one
    /// transaction per row. Encoding and hashing occur before DB ownership.
    pub fn stage_page(&mut self,rows:&[T])->io::Result<PageHandle> {
        let (handle,bytes)=self.encode_page(rows)?;
        if !self.pending.contains_key(&handle.digest) {
            if self.pending_bytes.saturating_add(bytes.len())>8*1024*1024||self.pending.len()>=1024 {self.flush()?;}
            self.pending_bytes+=bytes.len();self.pending.insert(handle.digest.clone(),bytes);
        }Ok(handle)
    }
    pub fn flush(&mut self)->io::Result<()> {
        if self.pending.is_empty() {return Ok(());}
        let namespace=self.namespace();let rows=self.pending.iter().map(|(digest,bytes)|(dm_store::Key::new(&namespace,digest),bytes.clone())).collect();
        self.store.put_many(rows,None)?;self.pending.clear();self.pending_bytes=0;Ok(())
    }
    pub fn write_pages(&self,pages:&[&[T]])->io::Result<Vec<PageHandle>> {
        if pages.len()>128 {return Err(invalid("typed write window exceeds page bound"));}
        let mut handles=Vec::with_capacity(pages.len());let mut records=Vec::with_capacity(pages.len());
        let mut bytes=0usize;let namespace=self.namespace();
        for page in pages {
            let (handle,encoded)=self.encode_page(page)?;bytes=bytes.saturating_add(encoded.len());
            if bytes>8*1024*1024 {return Err(invalid("typed write window exceeds byte bound"));}
            records.push((dm_store::Key::new(&namespace,&handle.digest),encoded));handles.push(handle);
        }
        if !records.is_empty() {self.store.put_many(records,None)?;}
        Ok(handles)
    }
    pub fn write_page(&self,rows:&[T])->io::Result<PageHandle> {
        self.write_pages(&[rows])?.pop().ok_or_else(||invalid("empty typed write result"))
    }
    pub fn read_page(&mut self,handle:&PageHandle)->io::Result<Arc<[T]>> {
        if !valid_digest(&handle.digest) || handle.rows==0 || handle.rows>MAX_ROWS
            || handle.encoded_bytes>MAX_ENCODED || handle.resident_bytes>self.budget {
            return Err(invalid("invalid typed page handle"));
        }
        if let Some(entry)=self.cache.get_mut(&handle.digest) {
            if entry.page.len()!=handle.rows || entry.charge!=handle.resident_bytes.saturating_add(256)
                || entry.encoded_bytes!=handle.encoded_bytes {return Err(invalid("cached typed page shape mismatch"));}
            self.lru.remove(&(entry.tick,handle.digest.clone()));self.clock+=1;entry.tick=self.clock;
            self.lru.insert((entry.tick,handle.digest.clone()));return Ok(Arc::clone(&entry.page));
        }
        let key=dm_store::Key::new(self.namespace(),&handle.digest);
        let bytes=if let Some(bytes)=self.pending.get(&handle.digest) {bytes.clone()}else {
            self.store.read_many_bounded(&[key],MAX_ENCODED,MAX_ENCODED,None)?.values.into_iter().next().flatten().ok_or_else(||invalid("missing typed page"))?};
        if bytes.len()!=handle.encoded_bytes || format!("{:x}",Sha256::digest(&bytes))!=handle.digest {
            return Err(invalid("typed page content mismatch"));
        }
        let rows:Vec<T>=rmp_serde::from_slice(&bytes).map_err(io::Error::other)?;
        let charge=rows.iter().try_fold(rows.len()*std::mem::size_of::<T>(),|sum,row|
            sum.checked_add((self.row_charge)(row))).ok_or_else(||invalid("typed page size overflow"))?;
        if rows.len()!=handle.rows || charge!=handle.resident_bytes || charge.saturating_add(256)>self.budget {
            return Err(invalid("typed page shape mismatch"));
        }
        let charge=charge+256;
        let page:Arc<[T]>=rows.into();
        while self.bytes.saturating_add(charge)>self.budget {
            let Some((tick,key))=self.lru.pop_first() else {break;};
            if self.cache.get(&key).is_some_and(|entry|entry.tick==tick) {
                if let Some(old)=self.cache.remove(&key) {self.bytes=self.bytes.saturating_sub(old.charge);}
            }
        }
        self.clock+=1;self.bytes+=charge;self.lru.insert((self.clock,handle.digest.clone()));
        self.cache.insert(handle.digest.clone(),Cached {page:Arc::clone(&page),charge,encoded_bytes:handle.encoded_bytes,tick:self.clock});
        Ok(page)
    }
    pub fn read_row(&mut self,manifest:&TableManifest,index:usize)->io::Result<RowView<T>> {
        if manifest.version!=1 || manifest.schema!=self.schema || index>=manifest.rows {
            return Err(invalid("typed table index mismatch"));
        }
        let mut base=0usize;
        for handle in &manifest.pages {
            let end=base.checked_add(handle.rows).ok_or_else(||invalid("typed table size overflow"))?;
            if index<end {return Ok(RowView {page:self.read_page(handle)?,index:index-base});}
            base=end;
        }
        Err(invalid("incomplete typed table manifest"))
    }
    pub fn index(&self,manifest:TableManifest)->io::Result<IndexedTable> {
        if manifest.version!=1 || manifest.schema!=self.schema {return Err(invalid("typed table schema mismatch"));}
        let mut starts=Vec::with_capacity(manifest.pages.len());let mut rows=0usize;
        for page in &manifest.pages {
            if !valid_digest(&page.digest) || page.rows==0 || page.rows>MAX_ROWS
                || page.encoded_bytes>MAX_ENCODED || page.resident_bytes.saturating_add(256)>self.budget {
                return Err(invalid("invalid typed table page"));
            }
            starts.push(rows);rows=rows.checked_add(page.rows).ok_or_else(||invalid("typed table size overflow"))?;
        }
        if rows!=manifest.rows {return Err(invalid("typed table row count mismatch"));}
        Ok(IndexedTable {manifest,starts})
    }
    pub fn read_indexed(&mut self,table:&IndexedTable,index:usize)->io::Result<RowView<T>> {
        if table.manifest.schema!=self.schema || index>=table.manifest.rows {return Err(invalid("typed table index mismatch"));}
        let page=table.starts.partition_point(|start|*start<=index)-1;
        Ok(RowView {page:self.read_page(&table.manifest.pages[page])?,index:index-table.starts[page]})
    }
    pub fn manifest(&self,pages:Vec<PageHandle>)->io::Result<TableManifest> {
        let rows=pages.iter().try_fold(0usize,|sum,page|sum.checked_add(page.rows))
            .ok_or_else(||invalid("typed table size overflow"))?;
        if pages.iter().any(|page|!valid_digest(&page.digest) || page.rows==0 || page.rows>MAX_ROWS
            || page.encoded_bytes>MAX_ENCODED || page.resident_bytes>self.budget) {
            return Err(invalid("invalid typed table page"));
        }
        Ok(TableManifest {version:1,schema:self.schema.clone(),pages,rows})
    }
}
