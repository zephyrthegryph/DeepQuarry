//! Durable validation is licensed by a complete current binding namespace proof.
//! A matching context skips dependency reconstruction, never descriptor checks.
use super::*;
#[derive(Clone,Debug,Eq,PartialEq,Serialize,Deserialize)]
pub struct BindingContextProof {identity:String}
impl BindingContextProof {
    /// Components must include every shared/private resolver input, dense static
    /// assignment, owner namespace, generated helper policy and implementation
    /// identity. Producer owns canonical deterministic component ordering.
    pub fn from_components<T:Serialize>(components:&T)->io::Result<Self> {
        let identity=crate::content_hash::compact(b"dm-complete-binding-context-v1\0",components)
            .ok_or_else(||io::Error::other("binding context serialization failed"))?;
        Ok(Self {identity:crate::content_hash::text(identity)})
    }
}
#[derive(Serialize,Deserialize)]
struct ContextHead {version:u8,proof:BindingContextProof,keys:String,pages:Vec<String>,count:usize}
#[derive(Serialize,Deserialize)]
struct ContextRow {key:ProcKey,descriptor:CompactDescriptor,disk:CompactIdentity}
fn keys_digest(keys:&[ProcKey])->io::Result<String> {
    crate::content_hash::compact(b"",keys).map(crate::content_hash::text)
        .ok_or_else(||io::Error::other("context key serialization failed"))
}
impl ProjectProcedureGraph {
    /// A source-ordered range proof is derived from the same validated positive
    /// and negative readsets as individual output probes. It contains no decoded
    /// procedure artifact; changing any descriptor or candidate changes the root.
    pub fn validated_range_identity(&mut self, keys:&[ProcKey], descriptors:&[ProcDescriptor])->Option<String> {
        if keys.is_empty()||keys.len()>1024||keys.len()!=descriptors.len() {return None;}
        let rows:Option<Vec<_>>=keys.iter().zip(descriptors).map(|(key,descriptor)|
            self.probe_validity(key,descriptor).map(|identity|(key,descriptor,identity))).collect();
        crate::content_hash::compact(b"dm-validated-procedure-range-v1",&rows?).map(crate::content_hash::text)
    }
    /// Revoked context-only certificates have no live dependency inputs yet.
    /// The adapter must prepare their exact persisted readsets and resolver
    /// index even if its declaration revision string otherwise stayed equal.
    pub fn has_context_only_pending(&self)->bool {
        self.certificates.values().any(|certificate|certificate.context_only&&!certificate.valid&&certificate.active)
    }
    fn revoke_context_only(&mut self) {
        for (key,certificate) in &mut self.certificates {
            if certificate.context_only {certificate.valid=false;self.dirty.insert(key.clone());if let Some(p)=&mut self.persistence {p.headers_seen.remove(key);}}
        }
        self.accepted_context=None;
    }
    /// Call before preparing headers/fact deltas. Context changes revoke compact
    /// context-only rows so the ordinary persisted exact readset path restores
    /// their positive and negative facts before any structural invalidation.
    pub fn accept_context(&mut self,proof:&BindingContextProof,keys:&[ProcKey])->io::Result<bool> {
        if self.accepted_context.as_ref()==Some(proof)&&keys.iter().all(|key|self.certificates.get(key).is_some_and(|c|c.valid)||self.records.get(key).is_some_and(|r|current_candidate(&self.db,r.input).is_some())) {return Ok(true);}
        self.revoke_context_only();
        // Live full readsets must follow ordinary fact refresh: their current
        // Salsa values may still describe the preceding binding context.
        if !self.records.is_empty()||self.certificates.values().any(|c|!c.context_only) {return Ok(false);}
        let Some(p)=self.persistence.as_ref() else {return Ok(false);};
        let namespace=format!("{}-contexts-v1",p.headers_namespace);
        let head=p.store.read_many_bounded(&[dm_store::Key::new(&namespace,&proof.identity)],1024*1024,1024*1024,None)?;
        let Some(bytes)=head.values.into_iter().next().flatten() else {return Ok(false);};
        let head:ContextHead=match rmp_serde::from_slice(&bytes){Ok(head)=>head,Err(_)=>return Ok(false)};
        if head.version!=1||head.proof!=*proof||head.keys!=keys_digest(keys)?||head.count<keys.len()||head.count>128000||head.pages.len()>256{return Ok(false);}
        let page_namespace=format!("graph-context-pages-v1-{DISK_STAGE}");
        let mut rows=Vec::with_capacity(head.count);let mut total=0usize;
        for group in head.pages.chunks(8) {
            if group.iter().any(|name|name.len()!=64||!name.bytes().all(|b|b.is_ascii_hexdigit())) {return Ok(false);}
            let names:Vec<_>=group.iter().map(|name|dm_store::Key::new(&page_namespace,name)).collect();
            let batch=p.store.read_many_bounded(&names,4*1024*1024,32*1024*1024,None)?;
            for (name,bytes) in group.iter().zip(batch.values) {
                let Some(bytes)=bytes else {return Ok(false);};total+=bytes.len();if total>32*1024*1024||format!("{:x}",Sha256::digest(&bytes))!=*name{return Ok(false);}
                let page:Vec<ContextRow>=match rmp_serde::from_slice(&bytes){Ok(page)=>page,Err(_)=>return Ok(false)};
                if page.len()>1024||rows.len()+page.len()>head.count{return Ok(false);}
                rows.extend(page);
            }
        }
        if rows.len()!=head.count||rows.iter().take(keys.len()).zip(keys).any(|(row,key)|row.key!=*key||row.disk.text().len()!=64||row.key.path.len()>16384){return Ok(false);}
        if rows.iter().any(|row|!matches!(row.disk,CompactIdentity::Sha256(_))||row.key.path.len()>16384
            ||row.descriptor.body.heap_bytes()>256||row.descriptor.frame.heap_bytes()>256){return Ok(false);}
        for row in rows {
            if self.records.contains_key(&row.key){continue;}
            let id=if let Some(old)=self.certificates.get(&row.key){old.id}else{
                let id=u32::try_from(self.procedure_names.len()).map_err(io::Error::other)?;self.procedure_names.push(row.key.clone());id
            };
            self.certificates.insert(row.key.clone(),ValidatedCertificate {id,descriptor:row.descriptor,disk:row.disk,facts:Vec::new(),valid:true,active:true,context_only:true});
            self.dirty.remove(&row.key);self.persistence.as_mut().unwrap().headers_seen.insert(row.key);
        }
        self.accepted_context=Some(proof.clone());
        self.stats.procedures=self.records.len()+self.certificates.len();
        self.stats.metadata_bytes=self.certificates.iter().map(|(key,c)|certificate_heap(key,c)).sum::<usize>()
            +self.procedure_names.iter().map(|key|key.path.capacity()+96).sum::<usize>()
            +self.fact_names.iter().map(|fact|fact_heap(fact)+96).sum::<usize>()
            +self.compact_reverse.values().map(|ids|96+ids.capacity()*4).sum::<usize>();
        Ok(true)
    }
    /// Seal only a completed validated graph. Page+head publication is one
    /// transaction; concurrent builds may replace the head only with their own
    /// fully published generation, and descriptor checks disambiguate bodies.
    pub fn seal_context(&mut self,proof:&BindingContextProof,keys:&[ProcKey])->io::Result<bool> {
        if self.persistence.is_none(){return Ok(false);}
        self.flush()?;
        let mut rows=Vec::with_capacity(keys.len());
        for key in keys {
            let row=if let Some(c)=self.certificates.get(key).filter(|c|c.valid) {ContextRow {key:key.clone(),descriptor:c.descriptor.clone(),disk:c.disk.clone()}}
            else if let Some(record)=self.records.get(key) {
                let Some(candidate)=current_candidate(&self.db,record.input) else {return Ok(false);};let Some(disk)=&candidate.disk else{return Ok(false);};
                ContextRow {key:key.clone(),descriptor:CompactDescriptor::new(&candidate.descriptor),disk:CompactIdentity::new(&disk.key)}
            } else{return Ok(false);};
            if !matches!(row.disk,CompactIdentity::Sha256(_)){return Ok(false);}rows.push(row);
        }
        let primary:BTreeSet<_>=keys.iter().collect();
        for (key,c) in &self.certificates {
            if !primary.contains(key)&&c.valid&&c.active {rows.push(ContextRow {key:key.clone(),descriptor:c.descriptor.clone(),disk:c.disk.clone()});}
        }
        for (key,record) in &self.records {
            if primary.contains(key)||!record.active||self.certificates.contains_key(key){continue;}
            if let Some(candidate)=current_candidate(&self.db,record.input) {if let Some(disk)=&candidate.disk {
                rows.push(ContextRow {key:key.clone(),descriptor:CompactDescriptor::new(&candidate.descriptor),disk:CompactIdentity::new(&disk.key)});
            }}
        }
        if rows.len()>128000{return Ok(false);}
        let p=self.persistence.as_ref().unwrap();let namespace=format!("{}-contexts-v1",p.headers_namespace);let page_namespace=format!("graph-context-pages-v1-{DISK_STAGE}");
        let mut writes=Vec::new();let mut pages=Vec::new();let mut total=0usize;
        for group in rows.chunks(1024) {
            let bytes=rmp_serde::to_vec(group).map_err(io::Error::other)?;total+=bytes.len();if bytes.len()>4*1024*1024||total>32*1024*1024{return Ok(false);}
            let name=format!("{:x}",Sha256::digest(&bytes));pages.push(name.clone());writes.push((dm_store::Key::new(&page_namespace,name),bytes));
        }
        let head=ContextHead {version:1,proof:proof.clone(),keys:keys_digest(keys)?,pages,count:rows.len()};
        writes.push((dm_store::Key::new(namespace,&proof.identity),rmp_serde::to_vec(&head).map_err(io::Error::other)?));
        p.store.put_many(writes,None)?;
        // The durable complete-context proof now licenses these descriptors
        // directly. Keep compact candidate identities, not a second resident
        // copy of every unchanged dependency and Salsa input. A context change
        // revokes these rows and restores their persisted exact readsets.
        let mut certificates=BTreeMap::new();
        let mut names=Vec::with_capacity(rows.len());
        for row in rows {
            let id=u32::try_from(names.len()).map_err(io::Error::other)?;
            names.push(row.key.clone());
            certificates.insert(row.key,ValidatedCertificate {id,descriptor:row.descriptor,disk:row.disk,
                facts:Vec::new(),valid:true,active:true,context_only:true});
        }
        self.certificates=certificates;self.procedure_names=names;
        self.records.clear();self.shared_facts.clear();self.fact_ids.clear();self.fact_names=Vec::new();
        self.values.clear();self.reverse.clear();self.compact_reverse.clear();self.readsets.clear();
        self.decoded_nodes=DecodedDagNodes::default();self.dirty.clear();self.pending_shared.clear();
        self.pending_private.clear();self.lru.clear();self.db=Database::default();
        if let Some(p)=&mut self.persistence {p.fact_rows.clear();p.value_rows.clear();p.witness_memo_bytes=0;}
        self.stats.resident_bytes=0;self.stats.facts=0;self.stats.procedures=self.certificates.len();
        self.stats.metadata_bytes=self.certificates.iter().map(|(key,c)|certificate_heap(key,c)).sum::<usize>()
            +self.procedure_names.iter().map(|key|key.path.capacity()+std::mem::size_of::<ProcKey>()).sum::<usize>();
        self.accepted_context=Some(proof.clone());
        if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE sealed graph context retained: procedures={} metadata_bytes={}",self.certificates.len(),self.stats.metadata_bytes);}
        Ok(true)
    }
}
