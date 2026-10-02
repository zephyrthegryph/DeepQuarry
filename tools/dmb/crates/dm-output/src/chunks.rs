//! Immutable physical object pages and deterministic ordered composition.
//! Page identities are independent of their position; the ordered manifest
//! carries output offsets and list spans. Readers verify every addressed page.
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);
#[derive(Clone, Serialize, Deserialize)]
pub struct PageRef { pub digest: String, pub len: usize }
#[derive(Clone, Serialize, Deserialize)]
pub struct ObjectManifest {
    pub version: u32,
    pub pages: Vec<PageRef>,
    pub len: usize,
    pub digest: String,
    pub list_spans: Vec<std::ops::Range<usize>>,
}
/// Created only from a validated physical writer; manifest metadata alone is
/// never an authorization to publish bytes or skip page content verification.
pub struct StoredDmb { root: PathBuf, manifest: ObjectManifest, manifest_digest: String }
impl StoredDmb {
    pub fn len(&self) -> usize { self.manifest.len }
    pub fn digest(&self) -> &str { &self.manifest.digest }
    pub fn manifest(&self) -> &ObjectManifest { &self.manifest }
    pub fn manifest_digest(&self) -> &str { &self.manifest_digest }
    pub fn write_to(&self, output: &mut impl Write) -> io::Result<()> {
        let mut whole = Sha256::new();
        let mut total = 0usize;
        let mut buffer = [0u8; 64*1024];
        for page in &self.manifest.pages {
            let mut input = File::open(page_path(&self.root, &page.digest))?;
            let mut hash = Sha256::new(); let mut len = 0usize;
            loop {
                let count = input.read(&mut buffer)?;
                if count == 0 { break; }
                len = len.checked_add(count).ok_or_else(|| invalid("page size overflow"))?;
                if len > page.len { return Err(invalid("object page length mismatch")); }
                hash.update(&buffer[..count]); whole.update(&buffer[..count]);
                output.write_all(&buffer[..count])?;
            }
            if len != page.len || format!("{:x}", hash.finalize()) != page.digest {
                return Err(invalid("object page digest mismatch"));
            }
            total = total.checked_add(len).ok_or_else(|| invalid("object size overflow"))?;
        }
        if total != self.len() || format!("{:x}",whole.finalize()) != self.digest() {
            return Err(invalid("object composition digest mismatch"));
        }
        Ok(())
    }
}
fn invalid(message: &'static str) -> io::Error { io::Error::new(io::ErrorKind::InvalidData,message) }
fn page_path(root: &Path, digest: &str) -> PathBuf { root.join(&digest[..2]).join(digest) }
fn matches(path: &Path, bytes: &[u8]) -> bool {
    let Ok(mut input) = File::open(path) else { return false; };
    let mut buffer = [0u8;64*1024]; let mut offset = 0;
    loop {
        let Ok(count) = input.read(&mut buffer) else { return false; };
        if count == 0 { return offset == bytes.len(); }
        let Some(expected) = bytes.get(offset..offset+count) else { return false; };
        if expected != &buffer[..count] { return false; }
        offset += count;
    }
}
pub fn persist(root: &Path, image: &byond_dmb::dmb::ChunkedDmb) -> io::Result<StoredDmb> {
    let root = root.join("dmb-object-pages-v1");
    let mut whole = Sha256::new(); let mut pages = Vec::with_capacity(image.pages.len());
    let mut total = 0usize;
    for bytes in image.pages.iter().flat_map(|page|page.chunks(256*1024)) {
        whole.update(bytes);
        total = total.checked_add(bytes.len()).ok_or_else(||invalid("object size overflow"))?;
        let digest = format!("{:x}",Sha256::digest(bytes));
        let path = page_path(&root,&digest);
        if !matches(&path,bytes) {
            fs::create_dir_all(path.parent().unwrap())?;
            let temp = path.with_extension(format!("pending-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::Relaxed)));
            let result = (|| {
                let mut output = OpenOptions::new().create_new(true).write(true).open(&temp)?;
                // Rebuildable cache: close before atomic rename, but durability
                // belongs to the composed CAS file and published generation.
                // A lost/torn cache page is rejected by its SHA on every read.
                output.write_all(bytes)?; drop(output);
                if path.exists() && !matches(&path,bytes) { fs::remove_file(&path)?; }
                match fs::rename(&temp,&path) {
                    Ok(()) => Ok(()),
                    Err(_) if matches(&path,bytes) => Ok(()),
                    Err(error) => Err(error),
                }
            })();
            let _ = fs::remove_file(&temp); result?;
        }
        pages.push(PageRef {digest,len:bytes.len()});
    }
    if total != image.len || image.list_spans.iter().any(|span|span.start>span.end || span.end>total) {
        return Err(invalid("physical image manifest mismatch"));
    }
    let manifest = ObjectManifest {version:1,pages,len:total,
        digest:format!("{:x}",whole.finalize()),list_spans:image.list_spans.clone()};
    let encoded = serde_json::to_vec(&manifest).map_err(io::Error::other)?;
    let manifest_digest = format!("{:x}",Sha256::digest(&encoded));
    let directory = root.join("manifests"); fs::create_dir_all(&directory)?;
    let path = directory.join(&manifest_digest);
    if !matches(&path,&encoded) {
        let temp = path.with_extension(format!("pending-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::Relaxed)));
        let result = (|| {
            let mut output=OpenOptions::new().create_new(true).write(true).open(&temp)?;
            output.write_all(&encoded)?; drop(output);
            if path.exists() && !matches(&path,&encoded) {fs::remove_file(&path)?;}
            match fs::rename(&temp,&path) {Ok(())=>Ok(()),Err(_) if matches(&path,&encoded)=>Ok(()),Err(error)=>Err(error)}
        })();
        let _=fs::remove_file(&temp); result?;
    }
    Ok(StoredDmb {root,manifest,manifest_digest})
}

/// Addressed manifest restore. All structural bounds and manifest SHA are
/// checked here; page SHA checks occur during streaming before publication.
pub fn load(root: &Path, manifest_digest: &str) -> io::Result<StoredDmb> {
    let valid_digest = |digest:&str|digest.len()==64 && digest.bytes().all(|b|b.is_ascii_hexdigit());
    if !valid_digest(manifest_digest) {return Err(invalid("invalid object manifest key"));}
    let root=root.join("dmb-object-pages-v1");
    let file=File::open(root.join("manifests").join(manifest_digest))?;
    if file.metadata()?.len()>16*1024*1024 {return Err(invalid("object manifest exceeds bound"));}
    let mut bytes=Vec::new(); file.take(16*1024*1024+1).read_to_end(&mut bytes)?;
    if format!("{:x}",Sha256::digest(&bytes))!=manifest_digest {return Err(invalid("object manifest digest mismatch"));}
    let manifest:ObjectManifest=serde_json::from_slice(&bytes).map_err(io::Error::other)?;
    let total=manifest.pages.iter().try_fold(0usize,|sum,page|sum.checked_add(page.len));
    if manifest.version!=1 || !valid_digest(&manifest.digest) || total!=Some(manifest.len)
        || manifest.pages.iter().any(|page|!valid_digest(&page.digest) || page.len>16*1024*1024)
        || manifest.list_spans.iter().any(|span|span.start>span.end || span.end>manifest.len) {
        return Err(invalid("invalid object manifest"));
    }
    Ok(StoredDmb {root,manifest,manifest_digest:manifest_digest.to_owned()})
}

/// Incremental immutable-page sink. Only one bounded physical encoder page is
/// borrowed at a time; retained state contains identities and offsets only.
pub struct PageBuilder {
    root:PathBuf, whole:Sha256, pages:Vec<PageRef>, total:usize, pending:Vec<u8>,
}
impl PageBuilder {
    pub fn new(root:&Path)->Self {Self {root:root.join("dmb-object-pages-v1"),whole:Sha256::new(),pages:Vec::new(),total:0,pending:Vec::with_capacity(256*1024)}}
    pub fn append(&mut self,mut bytes:&[u8])->io::Result<()> {
        self.total=self.total.checked_add(bytes.len()).ok_or_else(||invalid("object size overflow"))?;
        self.whole.update(bytes);
        while !bytes.is_empty() {
            let count=(256*1024-self.pending.len()).min(bytes.len());
            self.pending.extend_from_slice(&bytes[..count]);bytes=&bytes[count..];
            if self.pending.len()==256*1024 {self.flush_page()?;}
        }
        Ok(())
    }
    fn flush_page(&mut self)->io::Result<()> {
        if self.pending.is_empty() {return Ok(());}
        let bytes=self.pending.as_slice();
            let digest=format!("{:x}",Sha256::digest(bytes));let path=page_path(&self.root,&digest);
            if !matches(&path,bytes) {
                fs::create_dir_all(path.parent().unwrap())?;
                let temp=path.with_extension(format!("pending-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::Relaxed)));
                let result=(|| {let mut output=OpenOptions::new().create_new(true).write(true).open(&temp)?;
                    output.write_all(bytes)?;drop(output);
                    if path.exists()&&!matches(&path,bytes) {fs::remove_file(&path)?;}
                    match fs::rename(&temp,&path) {Ok(())=>Ok(()),Err(_) if matches(&path,bytes)=>Ok(()),Err(error)=>Err(error)}
                })();let _=fs::remove_file(&temp);result?;
            }
            self.pages.push(PageRef {digest,len:bytes.len()});
            self.pending.clear();Ok(())
    }
    pub fn finish(mut self,len:usize,list_spans:Vec<std::ops::Range<usize>>)->io::Result<StoredDmb> {
        self.flush_page()?;
        if self.total!=len||list_spans.iter().any(|span|span.start>span.end||span.end>len) {return Err(invalid("streamed image manifest mismatch"));}
        let manifest=ObjectManifest {version:1,pages:self.pages,len,digest:format!("{:x}",self.whole.finalize()),list_spans};
        let encoded=serde_json::to_vec(&manifest).map_err(io::Error::other)?;let manifest_digest=format!("{:x}",Sha256::digest(&encoded));
        let directory=self.root.join("manifests");fs::create_dir_all(&directory)?;let path=directory.join(&manifest_digest);
        if !matches(&path,&encoded) {
            let temp=path.with_extension(format!("pending-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::Relaxed)));
            let result=(|| {let mut output=OpenOptions::new().create_new(true).write(true).open(&temp)?;output.write_all(&encoded)?;drop(output);
                if path.exists()&&!matches(&path,&encoded) {fs::remove_file(&path)?;}
                match fs::rename(&temp,&path) {Ok(())=>Ok(()),Err(_) if matches(&path,&encoded)=>Ok(()),Err(error)=>Err(error)}
            })();let _=fs::remove_file(&temp);result?;
        }
        Ok(StoredDmb {root:self.root,manifest,manifest_digest})
    }
}
