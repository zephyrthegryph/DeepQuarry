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
pub struct PackedRecords {store:Store,pages:String,buckets:String}
#[derive(Clone,Serialize,Deserialize)]
struct Locator {page:String,slot:u32}
#[derive(Serialize,Deserialize)]
struct Bucket {version:u8,rows:BTreeMap<String,Locator>}
fn bucket(key:&str)->u8 {Sha256::digest(key.as_bytes())[0]}
fn sha_name(value:&str)->bool {value.len()==64&&value.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b))}
impl PackedRecords {
    pub fn new(store:Store,namespace:impl Into<String>)->io::Result<Self> {
        let namespace=namespace.into();Key::new(&namespace,"probe").encode()?;
        Ok(Self {store,pages:format!("{namespace}-packed-pages-v1"),buckets:format!("{namespace}-packed-buckets-v1")})
    }
    fn bucket_key(&self,id:u8)->Key {Key::new(&self.buckets,format!("{id:02x}"))}
    fn read_buckets(&self,ids:&[u8],cancel:Option<&AtomicBool>)->io::Result<(BTreeMap<u8,Bucket>,Vec<ReadWitness>)> {
        let keys:Vec<_>=ids.iter().map(|id|self.bucket_key(*id)).collect();
        let batch=self.store.read_many_bounded(&keys,BUCKET_BYTES,INDEX_BYTES,cancel)?;
        let mut result=BTreeMap::new();
        for (id,bytes) in ids.iter().zip(batch.values) {
            let row=match bytes {Some(bytes)=>serde_json::from_slice::<Bucket>(&bytes).map_err(error)?,None=>Bucket {version:1,rows:BTreeMap::new()}};
            if row.version!=1 || row.rows.len()>64000 || row.rows.iter().any(|(key,loc)|key.len()>KEY_BYTES||bucket(key)!=*id||!sha_name(&loc.page)||loc.slot as usize>=PAGE_ROWS) {
                return Err(invalid_data("invalid packed locator bucket"));
            }
            result.insert(*id,row);
        }
        Ok((result,batch.witnesses))
    }
    /// At most64000 records and32MiB encoded page bytes per call. Each page
    /// has at most1024 rows/8MiB; each locator bucket at most8MiB. Only touched
    /// buckets are merged, with four exact-witness conflict retries. Concurrent
    /// writers preserve unrelated names; same-name last committed value wins.
    pub fn write_many(&self,records:&[(String,Vec<u8>)],cancel:Option<&AtomicBool>)->io::Result<Commit> {
        if records.len()>64000 {return Err(invalid_data("packed record count exceeds64000"));}
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
            if key.len()>KEY_BYTES || size>PAGE_BYTES-12 {return Err(invalid_data("packed record exceeds page limits"));}
            if rows.len()==PAGE_ROWS || page.len()+size>PAGE_BYTES {seal(&mut page,&mut rows,&self.pages,&mut changes,&mut locators);}
            bytes=bytes.checked_add(size).ok_or_else(||invalid_data("packed batch overflow"))?;
            if bytes>BATCH_BYTES {return Err(invalid_data("packed batch exceeds32MiB"));}
            page.extend_from_slice(&(key.len() as u32).to_le_bytes());page.extend_from_slice(&(value.len() as u64).to_le_bytes());page.extend_from_slice(key.as_bytes());page.extend_from_slice(value);rows.push(key.to_owned());
        }
        seal(&mut page,&mut rows,&self.pages,&mut changes,&mut locators);
        if locators.is_empty(){return Ok(Commit::Applied);}
        let ids:Vec<_>=locators.keys().map(|key|bucket(key)).collect::<std::collections::BTreeSet<_>>().into_iter().collect();let page_count=changes.len();
        for _ in 0..4 {
            changes.truncate(page_count);
            let (mut buckets,witnesses)=self.read_buckets(&ids,cancel)?;
            for (key,locator) in &locators {buckets.get_mut(&bucket(key)).unwrap().rows.insert(key.clone(),locator.clone());}
            for (id,rows) in buckets {let bytes=serde_json::to_vec(&rows).map_err(error)?;if bytes.len()>BUCKET_BYTES{return Err(invalid_data("packed locator bucket exceeds8MiB"));}changes.push(Change::Put(self.bucket_key(id),bytes));}
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
        if keys.len()>64000 || keys.iter().any(|key|key.len()>KEY_BYTES) {return Err(invalid_data("packed read key limits exceeded"));}
        let ids:Vec<_>=keys.iter().map(|key|bucket(key)).collect::<std::collections::BTreeSet<_>>().into_iter().collect();
        let (buckets,_)=self.read_buckets(&ids,cancel)?;
        let max_batch_bytes=max_batch_bytes.min(INDEX_BYTES);
        if !prefix {
            // Group by immutable identity so source-order requests cannot
            // repeatedly hydrate the same SHA-sorted publication page.
            let mut requests=BTreeMap::<String,Vec<(usize,u32)>>::new();
            for (index,key) in keys.iter().enumerate() {
                if let Some(locator)=buckets[&bucket(key)].rows.get(key) {
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
                        if len>max_payload_bytes||total.checked_add(len).is_none_or(|sum|sum>max_batch_bytes){return Err(invalid_data("packed payload hydration budget exceeded"));}
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
            let Some(locator)=buckets[&bucket(key)].rows.get(key) else {result.push(None);continue;};
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
                if prefix {break;}return Err(invalid_data("packed payload hydration budget exceeded"));
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
