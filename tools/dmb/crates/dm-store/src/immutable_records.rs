//! Current named heads are small checksum-protected transactional descriptors.
//! Only full SHA verification constructs reusable immutable payload handles.
use super::*;
use std::sync::Arc;
#[derive(Clone,Debug)]
pub struct VerifiedRecord {bytes:Arc<[u8]>,identity:String}
impl VerifiedRecord {
    pub fn bytes(&self)->&[u8] {&self.bytes}
    pub fn identity(&self)->&str {&self.identity}
}
#[derive(Clone,Debug)]
pub struct SharedReadBatch {pub values:Vec<Option<VerifiedRecord>>,pub witnesses:Vec<ReadWitness>}
pub(super) fn hex(bytes:&[u8])->String {
    const HEX:&[u8;16]=b"0123456789abcdef";let mut result=String::with_capacity(bytes.len()*2);
    for &byte in bytes {result.push(HEX[(byte>>4) as usize] as char);result.push(HEX[(byte&15) as usize] as char);}result
}
pub(super) fn encode_head(identity:&[u8],len:usize)->Vec<u8> {
    let mut descriptor=identity.to_vec();descriptor.extend_from_slice(&(len as u64).to_le_bytes());encode_record(&descriptor)
}
pub(super) fn decode_head(bytes:&[u8])->io::Result<(String,usize)> {
    if bytes.len()!=72{return Err(invalid_data("invalid immutable record head wire length"));}
    let descriptor=decode_record(bytes)?;
    if descriptor.len()!=40{return Err(invalid_data("invalid immutable record head"));}
    let len=usize::try_from(u64::from_le_bytes(descriptor[32..40].try_into().unwrap())).map_err(error)?;
    if len>MAX_RECORD{return Err(invalid_data("immutable record head size exceeds limit"));}
    Ok((hex(&descriptor[..32]),len))
}
fn verify_payload(bytes:&[u8],expected:Option<(&str,usize)>)->io::Result<VerifiedRecord> {
    if expected.is_some_and(|(_,len)|bytes.len()!=len.saturating_add(32)) {
        return Err(invalid_data("immutable payload wire length does not match head"));
    }
    let payload=decode_record(bytes)?;let identity=hex(&bytes[..32]);
    if expected.is_some_and(|(name,len)|name!=identity||len!=payload.len()){return Err(invalid_data("immutable payload does not match head"));}
    Ok(VerifiedRecord {bytes:payload.into(),identity})
}
impl Store {
    /// Current head/checksum and absence are observed in one fresh transaction.
    /// Previously verified handles can avoid payload I/O only for exact matching
    /// SHA and length; new/legacy bytes always pass their complete checksum.
    /// Cached bytes count toward the same logical stage hydration budget.
    pub fn read_cached(&self,keys:&[Key],cached:&BTreeMap<Key,VerifiedRecord>,max_record_bytes:usize,max_batch_bytes:usize,cancel:Option<&AtomicBool>)->io::Result<SharedReadBatch> {
        self.read_shared_grouped(keys,cached,keys.len().max(1),max_record_bytes,max_batch_bytes,max_batch_bytes,cancel,false)
    }
    pub(super) fn read_shared_grouped(&self,keys:&[Key],cached:&BTreeMap<Key,VerifiedRecord>,group_records:usize,max_record_bytes:usize,max_group_bytes:usize,max_session_bytes:usize,cancel:Option<&AtomicBool>,prefix:bool)->io::Result<SharedReadBatch> {
        if group_records==0||keys.len()>64000{return Err(io::Error::new(io::ErrorKind::InvalidInput,"invalid shared read batch size"));}
        let mut encoded=Vec::with_capacity(keys.len());let mut key_bytes=0usize;
        for key in keys {
            if key.namespace.len().saturating_add(key.name.len())>1024*1024 {
                return Err(io::Error::new(io::ErrorKind::InvalidInput,"shared read individual key exceeds1MiB"));
            }
            let name=key.encode()?;
            key_bytes=key_bytes.checked_add(name.len()).ok_or_else(||invalid_data("shared read key size overflow"))?;
            if key_bytes>8*1024*1024{return Err(io::Error::new(io::ErrorKind::InvalidInput,"shared read encoded keys exceed8MiB"));}
            encoded.push(name);
        }
        self.access(cancel,|db| {
            let tx=db.begin_read().map_err(error)?;
            let legacy=tx.open_table(RECORDS).map_err(error)?;
            let heads=tx.open_table(HEADS).map_err(error)?;
            let payloads=tx.open_table(PAYLOADS).map_err(error)?;
            let mut result=SharedReadBatch {values:Vec::with_capacity(keys.len()),witnesses:Vec::with_capacity(keys.len())};
            let mut bytes=0usize;let mut group_bytes=0usize;
            for (ordinal,(key,name)) in keys.iter().zip(&encoded).enumerate() {
                if cancel.is_some_and(|flag|flag.load(Ordering::Relaxed)){return Err(io::Error::new(io::ErrorKind::Interrupted,"shared read cancelled"));}
                if ordinal%group_records==0 {group_bytes=0;}
                let head=heads.get(name.as_str()).map_err(error)?;
                let old=if head.is_none(){legacy.get(name.as_str()).map_err(error)?}else{None};
                let identity=head.as_ref().map(|head|decode_head(head.value())).transpose()?;
                let len=identity.as_ref().map_or_else(||old.as_ref().map_or(0,|old|old.value().len().saturating_sub(32)),|(_,len)|*len);
                let cost=if head.is_some()||old.is_some(){len.checked_add(32).ok_or_else(||invalid_data("shared read size overflow"))?}else{0};
                if len>max_record_bytes.min(MAX_RECORD)||cost>max_group_bytes.saturating_sub(group_bytes)||cost>max_session_bytes.min(128*1024*1024).saturating_sub(bytes) {
                    if prefix{break;}return Err(io::Error::new(io::ErrorKind::InvalidInput,"shared read exceeds stage byte limit"));
                }
                bytes+=cost;group_bytes+=cost;
                let value=if let Some((identity,len))=identity {
                    if let Some(value)=cached.get(key).filter(|value|value.identity==identity&&value.bytes.len()==len) {Some(value.clone())}
                    else {
                        let raw=payloads.get(identity.as_str()).map_err(error)?.ok_or_else(||invalid_data("immutable payload missing"))?;
                        Some(verify_payload(raw.value(),Some((&identity,len)))?)
                    }
                } else {old.as_ref().map(|old|verify_payload(old.value(),None)).transpose()?};
                result.witnesses.push(ReadWitness {key:key.clone(),value_digest:value.as_ref().map(|value|value.identity.clone())});result.values.push(value);
            }
            Ok(result)
        })
    }
}
