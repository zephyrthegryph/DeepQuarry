//! Named query records packed into immutable SHA pages and transactional buckets.
//! This is a byte-record index, independent of typed table/page row codecs.
use super::*;
const MAGIC:&[u8;8]=b"DMPACK01";
const PAGE_BYTES:usize=8*1024*1024;
const PAGE_ROWS:usize=1024;
const BATCH_BYTES:usize=32*1024*1024;
const BUCKET_BYTES:usize=8*1024*1024;
const INDEX_BYTES:usize=64*1024*1024;
const KEY_BYTES:usize=16*1024;
#[derive(Clone,Debug)]
pub struct PackedRecords {store:Store,pages:String,buckets:String,index_cache:std::sync::Arc<std::sync::Mutex<IndexCache>>}
#[derive(Clone,Serialize,Deserialize)]
struct Locator {page:String,slot:u32}
#[derive(Serialize,Deserialize)]
struct Bucket {version:u8,rows:BTreeMap<String,Locator>}
fn bucket(key:&str)->u8 {Sha256::digest(key.as_bytes())[0]}
fn sha_name(value:&str)->bool {value.len()==64&&value.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b))}
impl PackedRecords {
    pub fn new(store:Store,namespace:impl Into<String>)->io::Result<Self> {
        let namespace=namespace.into();Key::new(&namespace,"probe").encode()?;
        Ok(Self {store,pages:format!("{namespace}-packed-pages-v1"),buckets:format!("{namespace}-packed-buckets-v1"),index_cache:Default::default()})
    }
    fn bucket_key(&self,id:u8)->Key {Key::new(&self.buckets,format!("{id:02x}"))}
    fn read_index(&self,ids:&[u8],cancel:Option<&AtomicBool>)->io::Result<(BTreeMap<u8,std::sync::Arc<VerifiedIndex>>,Vec<ReadWitness>)> {
        let keys:Vec<_>=ids.iter().map(|id|self.bucket_key(*id)).collect();
        let batch=self.store.read_many_bounded(&keys,BUCKET_BYTES,INDEX_BYTES,cancel)?;
        let mut result=BTreeMap::new();
        for ((id,bytes),witness) in ids.iter().zip(batch.values).zip(&batch.witnesses) {
            let identity=(*id,witness.value_digest.clone());
            let cached=self.index_cache.lock().unwrap_or_else(|error|error.into_inner()).get(&identity);
            let entry=if let Some(cached)=cached {cached} else {
                let bytes=bytes.unwrap_or_default();
                let view=IndexView::new(&bytes,*id)?;
                let count=match view {IndexView::Binary {count,..}=>Some(count),_=>None};
                let mut entry=VerifiedIndex {bytes,count,permit:0};
                let charge=entry.bytes.capacity()+320;
                if count.is_some()&&charge<=LOCAL_INDEX_CACHE&&reserve_index_bytes(charge) {
                    entry.permit=charge;
                    let entry=std::sync::Arc::new(entry);
                    self.index_cache.lock().unwrap_or_else(|error|error.into_inner()).insert(identity,entry.clone());entry
                } else {std::sync::Arc::new(entry)}
            };
            result.insert(*id,entry);
        }
        Ok((result,batch.witnesses))
    }
    /// Retained immutable index payloads are charged to the shared cache permit;
    /// active readers keep that permit alive after session eviction.
    pub fn retained_index_bytes(&self)->usize {
        self.index_cache.lock().unwrap_or_else(|error|error.into_inner()).bytes
    }
    pub fn clear_index_cache(&self) {
        let mut cache=self.index_cache.lock().unwrap_or_else(|error|error.into_inner());cache.entries.clear();cache.bytes=0;
    }
    fn read_buckets(&self,ids:&[u8],cancel:Option<&AtomicBool>)->io::Result<(BTreeMap<u8,Bucket>,Vec<ReadWitness>)> {
        let (raw,witnesses)=self.read_index(ids,cancel)?;
        let mut buckets=BTreeMap::new();
        for (id,entry) in raw {buckets.insert(id,entry.view(id)?.materialize()?);}
        Ok((buckets,witnesses))
    }
    /// At most64000 records and32MiB encoded page bytes per call. Each page
    /// has at most1024 rows/8MiB; each locator bucket at most8MiB. Only touched
    /// buckets are merged, with four exact-witness conflict retries. Concurrent
    /// writers preserve unrelated names; same-name last committed value wins.
    pub fn write_many(&self,records:&[(String,Vec<u8>)],cancel:Option<&AtomicBool>)->io::Result<Commit> {
        if records.len()>64000 {return Err(io::Error::new(io::ErrorKind::InvalidInput,"packed record count exceeds64000"));}
        let ordered:BTreeMap<_,_>=records.iter().map(|(key,value)|(key.as_str(),value.as_slice())).collect();
        let mut changes=Vec::new();let mut locators=BTreeMap::<String,Locator>::new();
        let mut page=MAGIC.to_vec();page.extend_from_slice(&0u32.to_le_bytes());let mut rows=Vec::<String>::new();let mut bytes=0usize;
        fn seal(page:&mut Vec<u8>,rows:&mut Vec<String>,namespace:&str,changes:&mut Vec<Change>,locators:&mut BTreeMap<String,Locator>) {
            if rows.is_empty(){return;}
            page[8..12].copy_from_slice(&(rows.len() as u32).to_le_bytes());let name=digest(page);
            for (slot,key) in rows.drain(..).enumerate(){locators.insert(key,Locator {page:name.clone(),slot:slot as u32});}
            changes.push(Change::Put(Key::new(namespace,name),std::mem::replace(page,MAGIC.to_vec())));page.extend_from_slice(&0u32.to_le_bytes());
        }
        for (key,value) in ordered {
            let size=12usize.checked_add(key.len()).and_then(|n|n.checked_add(value.len())).ok_or_else(||invalid_data("packed record size overflow"))?;
            if key.len()>KEY_BYTES || size>PAGE_BYTES-12 {return Err(io::Error::new(io::ErrorKind::InvalidInput,"packed record exceeds page limits"));}
            if rows.len()==PAGE_ROWS || page.len()+size>PAGE_BYTES {seal(&mut page,&mut rows,&self.pages,&mut changes,&mut locators);}
            bytes=bytes.checked_add(size).ok_or_else(||invalid_data("packed batch overflow"))?;
            if bytes>BATCH_BYTES {return Err(io::Error::new(io::ErrorKind::InvalidInput,"packed batch exceeds32MiB"));}
            page.extend_from_slice(&(key.len() as u32).to_le_bytes());page.extend_from_slice(&(value.len() as u64).to_le_bytes());page.extend_from_slice(key.as_bytes());page.extend_from_slice(value);rows.push(key.to_owned());
        }
        seal(&mut page,&mut rows,&self.pages,&mut changes,&mut locators);
        if locators.is_empty(){return Ok(Commit::Applied);}
        let ids:Vec<_>=locators.keys().map(|key|bucket(key)).collect::<std::collections::BTreeSet<_>>().into_iter().collect();let page_count=changes.len();
        for _ in 0..4 {
            changes.truncate(page_count);
            let (mut buckets,witnesses)=self.read_buckets(&ids,cancel)?;
            for (key,locator) in &locators {buckets.get_mut(&bucket(key)).unwrap().rows.insert(key.clone(),locator.clone());}
            for (id,rows) in buckets {let bytes=encode_index(id,&rows)?;if bytes.len()>BUCKET_BYTES{return Err(io::Error::new(io::ErrorKind::InvalidInput,"packed locator bucket exceeds8MiB"));}changes.push(Change::Put(self.bucket_key(id),bytes));}
            match self.store.commit(&witnesses,&changes,cancel)? {Commit::Applied=>return Ok(Commit::Applied),Commit::Conflict=>{}}
        }
        Ok(Commit::Conflict)
    }
    /// Missing named locators return None. A located missing/corrupt page is an
    /// error, never proof of absence. Values are hydrated only for requested keys.
    pub fn read_many(&self,keys:&[String],max_payload_bytes:usize,max_batch_bytes:usize,cancel:Option<&AtomicBool>)->io::Result<Vec<Option<Vec<u8>>>> {
        self.read_inner(keys,max_payload_bytes,max_batch_bytes,cancel,false)
    }
    /// Returns an ordered witnessed prefix fitting the payload byte budget.
    /// Omitted trailing keys have not been observed and must not count as misses.
    pub fn read_prefix(&self,keys:&[String],max_payload_bytes:usize,max_batch_bytes:usize,cancel:Option<&AtomicBool>)->io::Result<Vec<Option<Vec<u8>>>> {
        self.read_inner(keys,max_payload_bytes,max_batch_bytes,cancel,true)
    }
    fn read_inner(&self,keys:&[String],max_payload_bytes:usize,max_batch_bytes:usize,cancel:Option<&AtomicBool>,prefix:bool)->io::Result<Vec<Option<Vec<u8>>>> {
        if keys.len()>64000 || keys.iter().any(|key|key.len()>KEY_BYTES) {return Err(io::Error::new(io::ErrorKind::InvalidInput,"packed read key limits exceeded"));}
        let ids:Vec<_>=keys.iter().map(|key|bucket(key)).collect::<std::collections::BTreeSet<_>>().into_iter().collect();
        let (raw,_)=self.read_index(&ids,cancel)?;
        let buckets:BTreeMap<_,_>=raw.iter().map(|(id,entry)|Ok((*id,entry.view(*id)?))).collect::<io::Result<_>>()?;
        let max_batch_bytes=max_batch_bytes.min(INDEX_BYTES);
        if !prefix {
            // Group by immutable identity so source-order requests cannot
            // repeatedly hydrate the same SHA-sorted publication page.
            let mut requests=BTreeMap::<String,Vec<(usize,u32)>>::new();
            for (index,key) in keys.iter().enumerate() {
                if let Some(locator)=buckets[&bucket(key)].lookup(key)? {
                    requests.entry(locator.page.clone()).or_default().push((index,locator.slot));
                }
            }
            let names:Vec<_>=requests.keys().map(|name|Key::new(&self.pages,name)).collect();
            let mut result=vec![None;keys.len()];let mut total=0usize;
            for group in names.chunks(4) {
                let batch=self.store.read_many_bounded(group,PAGE_BYTES,BATCH_BYTES,cancel)?;
                for (name,bytes) in group.iter().zip(batch.values) {
                    let bytes=bytes.ok_or_else(||invalid_data("packed locator page missing"))?;
                    if digest(&bytes)!=name.name{return Err(invalid_data("packed page SHA mismatch"));}
                    let offsets=decode_page(&bytes)?;
                    for &(index,slot) in &requests[&name.name] {
                        let &(key_start,key_end,start,end)=offsets.get(slot as usize).ok_or_else(||invalid_data("packed locator slot out of bounds"))?;
                        if &bytes[key_start..key_end]!=keys[index].as_bytes(){return Err(invalid_data("packed locator key mismatch"));}
                        let len=end-start;
                        if len>max_payload_bytes||total.checked_add(len).is_none_or(|sum|sum>max_batch_bytes){return Err(io::Error::new(io::ErrorKind::InvalidInput,"packed payload hydration budget exceeded"));}
                        total+=len;result[index]=Some(bytes[start..end].to_vec());
                    }
                }
            }
            return Ok(result);
        }
        let mut result=Vec::new();let mut total=0usize;
        // One bounded page window; adjacent locators reuse its verified bytes.
        let mut current:Option<(String,Vec<u8>,Vec<(usize,usize,usize,usize)>)>=None;
        for key in keys {
            let Some(locator)=buckets[&bucket(key)].lookup(key)? else {result.push(None);continue;};
            if current.as_ref().is_none_or(|(name,_,_)|name!=&locator.page) {
                let batch=self.store.read_many_bounded(&[Key::new(&self.pages,&locator.page)],PAGE_BYTES,PAGE_BYTES,cancel)?;
                let bytes=batch.values.into_iter().next().flatten().ok_or_else(||invalid_data("packed locator page missing"))?;
                if digest(&bytes)!=locator.page {return Err(invalid_data("packed page SHA mismatch"));}
                let offsets=decode_page(&bytes)?;current=Some((locator.page.clone(),bytes,offsets));
            }
            let (_,bytes,offsets)=current.as_ref().unwrap();
            let &(key_start,key_end,start,end)=offsets.get(locator.slot as usize).ok_or_else(||invalid_data("packed locator slot out of bounds"))?;
            if &bytes[key_start..key_end]!=key.as_bytes() {return Err(invalid_data("packed locator key mismatch"));}
            let len=end-start;
            if len>max_payload_bytes || total.checked_add(len).is_none_or(|sum|sum>max_batch_bytes) {
                if prefix {break;}return Err(io::Error::new(io::ErrorKind::InvalidInput,"packed payload hydration budget exceeded"));
            }
            total+=len;result.push(Some(bytes[start..end].to_vec()));
        }
        Ok(result)
    }
}
fn decode_page(bytes:&[u8])->io::Result<Vec<(usize,usize,usize,usize)>> {
    if bytes.len()<12||bytes.len()>PAGE_BYTES||&bytes[..8]!=MAGIC{return Err(invalid_data("invalid packed page header"));}
    let count=u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize;if count>PAGE_ROWS{return Err(invalid_data("packed page row count"));}
    let mut at=12usize;let mut result=Vec::with_capacity(count);
    for _ in 0..count {
        let header=bytes.get(at..at.checked_add(12).ok_or_else(||invalid_data("packed row overflow"))?).ok_or_else(||invalid_data("truncated packed row"))?;
        let key_len=u32::from_le_bytes(header[..4].try_into().unwrap()) as usize;
        let value_len=usize::try_from(u64::from_le_bytes(header[4..12].try_into().unwrap())).map_err(error)?;
        let key_start=at+12;let key_end=key_start.checked_add(key_len).ok_or_else(||invalid_data("packed key overflow"))?;
        let end=key_end.checked_add(value_len).ok_or_else(||invalid_data("packed value overflow"))?;
        if key_len>KEY_BYTES||end>bytes.len()||std::str::from_utf8(&bytes[key_start..key_end]).is_err(){return Err(invalid_data("invalid packed row bounds"));}
        result.push((key_start,key_end,key_end,end));at=end;
    }
    if at!=bytes.len(){return Err(invalid_data("packed page trailing bytes"));}Ok(result)
}

const INDEX_MAGIC:&[u8;8]=b"DMINDEX2";
enum IndexView<'a> {Empty,Binary {bytes:&'a [u8],count:usize},Legacy(Bucket)}
impl<'a> IndexView<'a> {
    fn new(bytes:&'a [u8],id:u8)->io::Result<Self> {
        if bytes.is_empty(){return Ok(Self::Empty);}
        if !bytes.starts_with(INDEX_MAGIC) {
            let bucket:Bucket=serde_json::from_slice(bytes).map_err(|error|invalid_data(&error.to_string()))?;
            if bucket.version!=1||bucket.rows.len()>64000||bucket.rows.iter().any(|(key,loc)|key.len()>KEY_BYTES||super::packed_records::bucket(key)!=id||!sha_name(&loc.page)||loc.slot as usize>=PAGE_ROWS){return Err(invalid_data("invalid legacy packed index"));}
            return Ok(Self::Legacy(bucket));
        }
        if bytes.len()<16||bytes.len()>BUCKET_BYTES||bytes[8]!=id||bytes[9..12]!=[0,0,0]{return Err(invalid_data("invalid binary packed index header"));}
        let count=u32::from_le_bytes(bytes[12..16].try_into().unwrap()) as usize;
        let directory_end=16usize.checked_add((count+1).checked_mul(4).ok_or_else(||invalid_data("packed index directory overflow"))?).ok_or_else(||invalid_data("packed index directory overflow"))?;
        if count>64000||directory_end>bytes.len(){return Err(invalid_data("invalid packed index directory"));}
        let view=Self::Binary {bytes,count};
        if view.offset(0)?!=directory_end||view.offset(count)?!=bytes.len(){return Err(invalid_data("packed index directory endpoints"));}
        let mut previous:Option<&str>=None;
        for index in 0..count {
            let (key,_,slot)=view.row(index)?;
            if slot as usize>=PAGE_ROWS||previous.is_some_and(|before|before>=key)||bucket(key)!=id{return Err(invalid_data("packed index ordering/shape"));}
            previous=Some(key);
        }
        Ok(view)
    }
    fn offset(&self,index:usize)->io::Result<usize> {
        let Self::Binary {bytes,count}=self else {return Err(invalid_data("not binary index"));};
        if index>*count{return Err(invalid_data("packed index directory bounds"));}
        let at=16+index*4;Ok(u32::from_le_bytes(bytes[at..at+4].try_into().unwrap()) as usize)
    }
    fn row(&self,index:usize)->io::Result<(&'a str,&'a [u8],u32)> {
        let Self::Binary {bytes,count}=self else {return Err(invalid_data("not binary index"));};
        if index>=*count{return Err(invalid_data("packed index row bounds"));}
        let bytes=*bytes;
        let start=self.offset(index)?;let end=self.offset(index+1)?;
        if start>end||end>bytes.len()||end-start<36||end-start-36>KEY_BYTES{return Err(invalid_data("packed index row shape"));}
        let key_end=end-36;let key=std::str::from_utf8(&bytes[start..key_end]).map_err(|error|invalid_data(&error.to_string()))?;
        Ok((key,&bytes[key_end..key_end+32],u32::from_le_bytes(bytes[end-4..end].try_into().unwrap())))
    }
    fn lookup(&self,key:&str)->io::Result<Option<Locator>> {
        match self {
            Self::Empty=>Ok(None),Self::Legacy(bucket)=>Ok(bucket.rows.get(key).cloned()),
            Self::Binary {count,..}=>{
                let mut low=0;let mut high=*count;
                while low<high {let mid=low+(high-low)/2;let (name,page,slot)=self.row(mid)?;
                    match name.cmp(key) {std::cmp::Ordering::Less=>low=mid+1,std::cmp::Ordering::Greater=>high=mid,std::cmp::Ordering::Equal=>return Ok(Some(Locator {page:hex_digest(page),slot}))}
                }Ok(None)
            }
        }
    }
    fn materialize(&self)->io::Result<Bucket> {
        match self {Self::Empty=>Ok(Bucket {version:1,rows:BTreeMap::new()}),Self::Legacy(bucket)=>Ok(Bucket {version:1,rows:bucket.rows.clone()}),Self::Binary {count,..}=>{
            let mut rows=BTreeMap::new();for index in 0..*count {let (key,page,slot)=self.row(index)?;rows.insert(key.to_owned(),Locator {page:hex_digest(page),slot});}Ok(Bucket {version:1,rows})
        }}
    }
}
fn hex_digest(bytes:&[u8])->String {
    const HEX:&[u8;16]=b"0123456789abcdef";
    let mut text=String::with_capacity(bytes.len()*2);for &byte in bytes{text.push(HEX[(byte>>4) as usize] as char);text.push(HEX[(byte&15) as usize] as char);}text
}
fn encode_index(id:u8,bucket:&Bucket)->io::Result<Vec<u8>> {
    if bucket.rows.len()>64000{return Err(io::Error::new(io::ErrorKind::InvalidInput,"packed locator count exceeds64000"));}
    let count=bucket.rows.len();let mut bytes=INDEX_MAGIC.to_vec();bytes.extend_from_slice(&[id,0,0,0]);bytes.extend_from_slice(&(count as u32).to_le_bytes());bytes.resize(16+(count+1)*4,0);
    for (index,(key,locator)) in bucket.rows.iter().enumerate() {
        if key.len()>KEY_BYTES||super::packed_records::bucket(key)!=id||!sha_name(&locator.page)||locator.slot as usize>=PAGE_ROWS{return Err(invalid_data("invalid packed index publication"));}
        let offset=u32::try_from(bytes.len()).map_err(error)?;bytes[16+index*4..20+index*4].copy_from_slice(&offset.to_le_bytes());bytes.extend_from_slice(key.as_bytes());
        for pair in locator.page.as_bytes().chunks_exact(2) {let digit=|b:u8|if b<=b'9'{b-b'0'}else{b-b'a'+10};bytes.push((digit(pair[0])<<4)|digit(pair[1]));}
        bytes.extend_from_slice(&locator.slot.to_le_bytes());
        if bytes.len()>BUCKET_BYTES{return Err(io::Error::new(io::ErrorKind::InvalidInput,"packed locator bucket exceeds8MiB"));}
    }
    let end=bytes.len() as u32;bytes[16+count*4..20+count*4].copy_from_slice(&end.to_le_bytes());Ok(bytes)
}

const LOCAL_INDEX_CACHE:usize=16*1024*1024;
const GLOBAL_INDEX_CACHE:usize=32*1024*1024;
static INDEX_RETAINED:std::sync::atomic::AtomicUsize=std::sync::atomic::AtomicUsize::new(0);
fn reserve_index_bytes(bytes:usize)->bool {
    INDEX_RETAINED.fetch_update(Ordering::AcqRel,Ordering::Acquire,|held|held.checked_add(bytes).filter(|next|*next<=GLOBAL_INDEX_CACHE)).is_ok()
}
#[derive(Debug)]
struct VerifiedIndex {bytes:Vec<u8>,count:Option<usize>,permit:usize}
impl VerifiedIndex {
    fn view(&self,id:u8)->io::Result<IndexView<'_>> {
        // Only successful full validation constructs a retained binary entry.
        match self.count {Some(count)=>Ok(IndexView::Binary {bytes:&self.bytes,count}),None=>IndexView::new(&self.bytes,id)}
    }
}
impl Drop for VerifiedIndex {fn drop(&mut self){if self.permit!=0 {INDEX_RETAINED.fetch_sub(self.permit,Ordering::AcqRel);}}}
#[derive(Debug,Default)]
struct IndexCache {entries:BTreeMap<(u8,Option<String>),(u64,std::sync::Arc<VerifiedIndex>)>,bytes:usize,clock:u64}
impl IndexCache {
    fn get(&mut self,key:&(u8,Option<String>))->Option<std::sync::Arc<VerifiedIndex>> {
        self.clock=self.clock.wrapping_add(1);let (touched,value)=self.entries.get_mut(key)?;*touched=self.clock;Some(value.clone())
    }
    fn insert(&mut self,key:(u8,Option<String>),value:std::sync::Arc<VerifiedIndex>) {
        self.clock=self.clock.wrapping_add(1);
        if let Some((_,old))=self.entries.insert(key,(self.clock,value.clone())){self.bytes=self.bytes.saturating_sub(old.permit);}
        self.bytes+=value.permit;
        while self.bytes>LOCAL_INDEX_CACHE {
            let Some(key)=self.entries.iter().min_by_key(|(_,entry)|entry.0).map(|(key,_)|key.clone()) else {break;};
            if let Some((_,old))=self.entries.remove(&key){self.bytes=self.bytes.saturating_sub(old.permit);}
        }
    }
}
