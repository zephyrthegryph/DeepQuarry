//! Disk-composable declaration allocation snapshots. Artifacts are primary;
//! decoded skeletons are an optional bounded acceleration layer.
use super::*;
use std::io::{self, Read, Write};
const CHUNK: usize = 4 * 1024 * 1024;
const MAX_COMPONENT: usize = 512 * 1024 * 1024;
const MAX_ITEMS: usize = 2_000_000;
const NAMESPACE: &str = "declaration-snapshot-fragments-v2";
const MANIFESTS: &str = "declaration-snapshot-manifest-v2";
#[derive(Serialize, Deserialize)]
struct Manifest {
    image: Vec<String>, strings: Vec<String>, proc_paths: Vec<String>, class_paths: Vec<String>,
    pending: Vec<Vec<String>>, dynamic: Vec<Vec<String>>, initializer_globals: Vec<String>,
    global_proc_ids: Vec<String>, shared: Vec<String>, invocations: Vec<Vec<String>>,
}
struct Writes { store:Store, pending:Vec<Change>, bytes:usize, written:usize }
impl Writes {
    fn enqueue(&mut self,key:String,encoded:Vec<u8>)->io::Result<()> {
        self.enqueue_key(Key::new(NAMESPACE,key),encoded)
    }
    fn enqueue_key(&mut self,key:Key,encoded:Vec<u8>)->io::Result<()> {
        if self.bytes.saturating_add(encoded.len())>16*1024*1024 {self.flush()?;}
        self.bytes+=encoded.len();self.written+=encoded.len();self.pending.push(Change::Put(key,encoded));Ok(())
    }
    fn flush(&mut self)->io::Result<()> {
        if self.pending.is_empty() {return Ok(());}
        self.store.commit(&[],&self.pending,None)?;self.pending.clear();self.bytes=0;Ok(())
    }
}
struct FragmentWriter<'a> { writes: &'a mut Writes, current: Vec<u8>, keys: Vec<String>, total: usize }
impl FragmentWriter<'_> {
    fn flush_fragment(&mut self) -> io::Result<()> {
        if self.current.is_empty() { return Ok(()); }
        let key = format!("{:x}", Sha256::digest(&self.current));
        let encoded = lz4_flex::compress_prepend_size(&self.current);
        self.writes.enqueue(key.clone(),encoded)?;
        self.keys.push(key); self.current.clear(); Ok(())
    }
}
impl Write for FragmentWriter<'_> {
    fn write(&mut self, mut bytes: &[u8]) -> io::Result<usize> {
        let count = bytes.len();
        self.total = self.total.checked_add(count).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"snapshot size overflow"))?;
        if self.total > MAX_COMPONENT { return Err(io::Error::new(io::ErrorKind::InvalidData,"snapshot component limit")); }
        while !bytes.is_empty() {
            let size = bytes.len().min(CHUNK-self.current.len());
            self.current.extend_from_slice(&bytes[..size]); bytes=&bytes[size..];
            if self.current.len()==CHUNK {self.flush_fragment()?;}
        }
        Ok(count)
    }
    fn flush(&mut self)->io::Result<()> {self.flush_fragment()}
}
fn put<T:Serialize + ?Sized>(writes:&mut Writes,value:&T)->Option<Vec<String>> {
    let mut writer=FragmentWriter {writes,current:Vec::with_capacity(CHUNK),keys:Vec::new(),total:0};
    rmp_serde::encode::write_named(&mut writer,value).ok()?; writer.flush_fragment().ok()?; Some(writer.keys)
}
fn put_rows<T:Serialize>(writes:&mut Writes,rows:&[T])->Option<Vec<Vec<String>>> {
    rows.chunks(1024).map(|rows|put(writes,rows)).collect()
}
/// A row-group identity uses already-derived semantic invocation identities
/// plus the current physical static slots and metadata. Stable groups compose
/// their disk fragments directly without serializing their decoded plans again.
fn put_invocations(writes:&mut Writes,rows:&[InvocationPlan])->Option<Vec<Vec<String>>> {
    const GROUPS:&str="declaration-invocation-groups-v2";
    let groups:Vec<_>=rows.chunks(1024).collect();
    let keys:Vec<_>=groups.iter().map(|rows| {
        let mut hash=Sha256::new();hash.update(env!("DM_EMISSION_FINGERPRINT"));
        for row in *rows {
            hash.update((row.path.len() as u64).to_le_bytes());hash.update(row.path.as_bytes());hash.update(row.frame_digest.as_bytes());
            hash.update(serde_json::to_vec(&row.metadata).unwrap_or_default());
            let ordered:BTreeMap<_,_>=row.static_ids.iter().collect();
            for (name,id) in ordered {hash.update((name.len() as u64).to_le_bytes());hash.update(name.as_bytes());hash.update(id.to_le_bytes());}
        }
        Key::new(GROUPS,format!("{:x}",hash.finalize()))
    }).collect();
    let mut known=BTreeMap::new();
    for batch in keys.chunks(128) {
        if let Ok(read)=writes.store.read_many_bounded(batch,256*1024,8*1024*1024,None) {
            for (key,bytes) in batch.iter().zip(read.values) {
                if let Some(bytes)=bytes {
                    if let Ok(fragments)=serde_json::from_slice::<Vec<String>>(&bytes) {
                        if !fragments.is_empty()&&fragments.len()<=MAX_COMPONENT/CHUNK+1 {known.insert(key.name.clone(),fragments);}
                    }
                }
            }
        }
    }
    let mut result=Vec::with_capacity(groups.len());let mut reused=0;
    for (rows,key) in groups.into_iter().zip(keys) {
        if let Some(fragments)=known.remove(&key.name) {result.push(fragments);reused+=1;continue;}
        let fragments=put(writes,rows)?;
        writes.enqueue_key(key,serde_json::to_vec(&fragments).ok()?).ok()?;
        result.push(fragments);
    }
    if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE declaration invocation groups: {reused} reused, {} encoded",result.len()-reused);}
    Some(result)
}
struct FragmentReader<'a> { store:&'a Store, keys:&'a [String], next:usize, bytes:Vec<u8>, position:usize, total:usize }
impl Read for FragmentReader<'_> {
    fn read(&mut self, output:&mut [u8])->io::Result<usize> {
        if output.is_empty() {return Ok(0);}
        if self.position==self.bytes.len() {
            let Some(key)=self.keys.get(self.next) else {return Ok(0)};
            let record=self.store.read_many_bounded(&[Key::new(NAMESPACE,key)],CHUNK+64*1024,CHUNK+64*1024,None)?;
            let bytes=record.values.first().and_then(Option::as_deref).ok_or_else(||io::Error::new(io::ErrorKind::NotFound,"snapshot fragment missing"))?;
            if bytes.len()<4 {return Err(io::Error::new(io::ErrorKind::InvalidData,"snapshot fragment header"));}
            let size=u32::from_le_bytes(bytes[..4].try_into().unwrap()) as usize;
            if size==0||size>CHUNK {return Err(io::Error::new(io::ErrorKind::InvalidData,"snapshot fragment size"));}
            self.total=self.total.saturating_add(size);
            if self.total>MAX_COMPONENT {return Err(io::Error::new(io::ErrorKind::InvalidData,"snapshot component size"));}
            self.bytes=lz4_flex::decompress_size_prepended(bytes).map_err(|error|io::Error::new(io::ErrorKind::InvalidData,error.to_string()))?;
            if format!("{:x}",Sha256::digest(&self.bytes))!=*key {return Err(io::Error::new(io::ErrorKind::InvalidData,"snapshot fragment identity"));}
            self.position=0;self.next+=1;
        }
        let size=output.len().min(self.bytes.len()-self.position);
        output[..size].copy_from_slice(&self.bytes[self.position..self.position+size]);self.position+=size;Ok(size)
    }
}
fn get<T:serde::de::DeserializeOwned>(store:&Store,keys:&[String])->Option<T> {
    if keys.is_empty()||keys.len()>MAX_COMPONENT/CHUNK+1 {return None;}
    let reader=FragmentReader {store,keys,next:0,bytes:Vec::new(),position:0,total:0};
    rmp_serde::from_read(std::io::BufReader::with_capacity(64*1024,reader)).ok()
}
fn get_rows<T:serde::de::DeserializeOwned>(store:&Store,groups:&[Vec<String>])->Option<Vec<T>> {
    if groups.len()>MAX_ITEMS/1024+1 {return None;}
    let mut result=Vec::new();
    for keys in groups {
        let mut rows:Vec<T>=get(store,keys)?;
        if rows.len()>1024||result.len().saturating_add(rows.len())>MAX_ITEMS {return None;}
        result.append(&mut rows);
    }
    Some(result)
}
pub(super) fn store(root:&Path,key:&str,value:&FrozenSkeleton)->Option<()> {
    let started=std::time::Instant::now();
    let store=Store::open(root.join("skeleton.redb")).ok()?;
    let mut writes=Writes {store,pending:Vec::new(),bytes:0,written:0};
    let metadata=&value.metadata;
    let manifest=Manifest {
        image:put(&mut writes,&value.image)?, strings:put(&mut writes,&metadata.strings)?,
        proc_paths:put(&mut writes,&metadata.proc_paths)?, class_paths:put(&mut writes,&metadata.class_paths)?,
        pending:put_rows(&mut writes,&metadata.pending)?, dynamic:put_rows(&mut writes,&metadata.dynamic)?,
        initializer_globals:put(&mut writes,&metadata.initializer_globals)?,global_proc_ids:put(&mut writes,&metadata.global_proc_ids)?,
        shared:put(&mut writes,&metadata.shared)?,invocations:put_invocations(&mut writes,&metadata.invocations)?,
    };
    let bytes=serde_json::to_vec(&manifest).ok()?;
    writes.flush().ok()?;
    writes.store.commit(&[],&[Change::Put(Key::new(MANIFESTS,key),bytes)],None).ok()?;
    if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE declaration snapshot persisted {} bytes in {:.3}s",writes.written,started.elapsed().as_secs_f64());}
    Some(())
}
pub(super) fn load(root:&Path,key:&str)->Option<FrozenSkeleton> {
    let started=std::time::Instant::now();
    let store=Store::open(root.join("skeleton.redb")).ok()?;
    let record=store.read_many_bounded(&[Key::new(MANIFESTS,key)],2*1024*1024,2*1024*1024,None).ok()?;
    let manifest:Manifest=serde_json::from_slice(record.values.first()?.as_deref()?).ok()?;
    let image=get(&store,&manifest.image)?;
    let metadata=SkeletonMetadata {
        strings:get(&store,&manifest.strings)?,proc_paths:get(&store,&manifest.proc_paths)?,class_paths:get(&store,&manifest.class_paths)?,
        pending:get_rows(&store,&manifest.pending)?,dynamic:get_rows(&store,&manifest.dynamic)?,
        initializer_globals:get(&store,&manifest.initializer_globals)?,global_proc_ids:get(&store,&manifest.global_proc_ids)?,
        shared:get(&store,&manifest.shared)?,invocations:get_rows(&store,&manifest.invocations)?,
    };
    if std::env::var_os("DM_BUILD_TRACE").is_some() {
        let fragments=manifest.image.len()+manifest.strings.len()+manifest.proc_paths.len()+manifest.class_paths.len()+manifest.pending.iter().map(Vec::len).sum::<usize>()+manifest.dynamic.iter().map(Vec::len).sum::<usize>()+manifest.initializer_globals.len()+manifest.global_proc_ids.len()+manifest.shared.len()+manifest.invocations.iter().map(Vec::len).sum::<usize>();
        eprintln!("DM_BUILD_TRACE declaration snapshot restored {fragments} binary fragments in {:.3}s",started.elapsed().as_secs_f64());
    }
    Some(FrozenSkeleton::new(image,metadata))
}
