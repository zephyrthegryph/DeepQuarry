//! Immutable certificate pages with local fact/value arenas. Mutable addressed
//! locators publish alongside their page in the existing graph transaction.
use super::*;
const PAGE_MAGIC: &[u8; 8] = b"DMCERT01";
const PAGE_RAW_BYTES: usize = 8 * 1024 * 1024;
const PAGE_DECODED_BYTES: usize = 32 * 1024 * 1024;

pub(super) struct PendingCertificate {
    pub header: DiskHeader,
    pub witnesses: Vec<(WitnessRow, WitnessRow)>,
}
#[derive(Serialize, Deserialize)]
struct Locator { version: u8, page: String, slot: u32 }
#[derive(Serialize, Deserialize)]
struct PackedHeader { header: DiskHeader, witnesses: Vec<(u32, u32)> }
#[derive(Serialize, Deserialize)]
struct CertificatePage {
    version: u8,
    facts: Vec<Vec<u8>>,
    values: Vec<Vec<u8>>,
    headers: Vec<PackedHeader>,
}

pub(super) fn seal(p: &mut Persistence) {
    let certificates = std::mem::take(&mut p.pending_certificates);
    p.pending_certificate_bytes = 0;
    for group in certificates.chunks(1024) { seal_group(p, group); }
}
fn seal_group(p: &mut Persistence, group: &[PendingCertificate]) {
    if group.is_empty() { return; }
    let mut facts = BTreeMap::new();
    let mut values = BTreeMap::new();
    let mut page = CertificatePage { version: 1, facts: Vec::new(), values: Vec::new(), headers: Vec::new() };
    for certificate in group {
        let mut witnesses = Vec::with_capacity(certificate.witnesses.len());
        for (fact, value) in &certificate.witnesses {
            let fact_id = *facts.entry(fact.name.as_str()).or_insert_with(|| {
                let id = page.facts.len() as u32; page.facts.push(fact.bytes.to_vec()); id
            });
            let value_id = *values.entry(value.name.as_str()).or_insert_with(|| {
                let id = page.values.len() as u32; page.values.push(value.bytes.to_vec()); id
            });
            witnesses.push((fact_id, value_id));
        }
        page.headers.push(PackedHeader { header: certificate.header.clone(), witnesses });
    }
    let Ok(raw) = rmp_serde::to_vec(&page) else { return; };
    if raw.len() > PAGE_RAW_BYTES {
        if group.len()>1 { let middle=group.len()/2; seal_group(p,&group[..middle]); seal_group(p,&group[middle..]); }
        return;
    }
    let mut encoded = PAGE_MAGIC.to_vec();
    encoded.extend(lz4_flex::compress_prepend_size(&raw));
    let digest = format!("{:x}", Sha256::digest(&encoded));
    let mut records = vec![(dm_store::Key::new(&p.certificate_pages_namespace, &digest), encoded)];
    for (slot, certificate) in group.iter().enumerate() {
        let Ok(key_bytes) = serde_json::to_vec(&certificate.header.key) else { continue; };
        let name = format!("{:x}", Sha256::digest(key_bytes));
        let locator = Locator { version: 1, page: digest.clone(), slot: slot as u32 };
        if let Ok(bytes) = rmp_serde::to_vec(&locator) {
            records.push((dm_store::Key::new(&p.certificate_heads_namespace, name), bytes));
        }
    }
    for (key, bytes) in records {
        let charge = pending_record_bytes(&key,&bytes);
        if let Some((old_key, old)) = p.pending.get_key_value(&key) {
            p.pending_bytes = p.pending_bytes.saturating_sub(pending_record_bytes(old_key,old));
        }
        p.pending_bytes = p.pending_bytes.saturating_add(charge);
        p.pending.insert(key,bytes);
    }
}

impl ProjectProcedureGraph {
    /// Addressed locator read followed by one shared arena read. Corrupt or
    /// absent pages leave the corresponding legacy header eligible for restore.
    pub(super) fn restore_packed_window(&mut self, keys: &[ProcKey]) -> io::Result<BTreeSet<ProcKey>> {
        let Some(p)=self.persistence.as_ref() else { return Ok(BTreeSet::new()); };
        let names: Vec<_> = keys.iter().map(|key| dm_store::Key::new(&p.certificate_heads_namespace,
            format!("{:x}",Sha256::digest(serde_json::to_vec(key).expect("procedure key"))))).collect();
        let heads = p.store.read_grouped_bounded(&names,128,1024, PAGE_RAW_BYTES,PAGE_RAW_BYTES,None)?;
        let mut requests: BTreeMap<String, Vec<(ProcKey,u32)>> = BTreeMap::new();
        for (key, bytes) in keys.iter().zip(heads.values) {
            let Some(bytes)=bytes else { continue; };
            let Ok(locator)=rmp_serde::from_slice::<Locator>(&bytes) else { continue; };
            if locator.version==1 && locator.page.len()==64 && locator.slot<1024 {
                requests.entry(locator.page).or_default().push((key.clone(),locator.slot));
            }
        }
        let page_names: Vec<_> = requests.keys().map(|name| dm_store::Key::new(&p.certificate_pages_namespace,name)).collect();
        // Bound decoded pages independently: consume each addressed page before
        // moving to the next rather than retaining an entire project's arenas.
        let mut restored = BTreeSet::new();
        for names in page_names.chunks(8) {
            let store=self.persistence.as_ref().unwrap().store.clone();
            let batch = match store.read_grouped_bounded(names,1,PAGE_RAW_BYTES+16,PAGE_RAW_BYTES+48,32*1024*1024,None) {
                Ok(batch)=>batch,
                Err(error) if error.kind()==io::ErrorKind::InvalidInput => {
                    // Unusually large pages are read individually.
                    for name in names {
                        if let Ok(batch)=store.read_many_bounded(&[name.clone()],PAGE_RAW_BYTES+16,PAGE_RAW_BYTES+48,None) {
                            if let Some(Some(bytes))=batch.values.into_iter().next() {
                                self.install_packed_page(name,&bytes,&requests,&mut restored);
                            }
                        }
                    }
                    continue;
                }
                Err(_)=>continue,
            };
            for (name,bytes) in names.iter().zip(batch.values) {
                if let Some(bytes)=bytes { self.install_packed_page(name,&bytes,&requests,&mut restored); }
            }
        }
        Ok(restored)
    }
    fn install_packed_page(&mut self, name: &dm_store::Key, bytes: &[u8], requests: &BTreeMap<String,Vec<(ProcKey,u32)>>, restored: &mut BTreeSet<ProcKey>) {
        if !bytes.starts_with(PAGE_MAGIC) || bytes.len()<12 || format!("{:x}",Sha256::digest(bytes))!=name.name { return; }
        let raw_len=u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize;
        if raw_len>PAGE_RAW_BYTES { return; }
        let Ok(raw)=lz4_flex::decompress_size_prepended(&bytes[8..]) else { return; };
        let Ok(page)=rmp_serde::from_slice::<CertificatePage>(&raw) else { return; };
        if page.version!=1 || page.headers.len()>1024 || page.facts.len()>64_000 || page.values.len()>64_000 { return; }
        let facts: Option<Vec<BindingFact>>=page.facts.iter().map(|bytes|serde_json::from_slice(bytes).ok()).collect();
        let values: Option<Vec<FactValue>>=page.values.iter().map(|bytes|serde_json::from_slice(bytes).ok()).collect();
        let (Some(facts),Some(values))=(facts,values) else { return; };
        let charge=facts.iter().map(fact_heap).sum::<usize>().saturating_add(values.iter().map(value_heap).sum::<usize>())
            .saturating_add(page.headers.iter().map(|header|header.witnesses.len().saturating_mul(16)+header.header.key.path.len()+512).sum::<usize>());
        if charge>PAGE_DECODED_BYTES { return; }
        // One interner lookup per arena entry, rather than one clone and JSON
        // encoding per procedure edge. These handles are bounded by this page;
        // the existing graph collection/epoch mechanism owns their retention.
        let fact_ids: Vec<_> = facts.iter().map(|fact| self.intern_fact(fact)).collect();
        let value_refs: Vec<_> = values.iter().map(|value| self.intern_value(value)).collect();
        for (key,slot) in &requests[&name.name] {
            let Some(header)=page.headers.get(*slot as usize).filter(|header|header.header.key==*key) else { continue; };
            if header.witnesses.len()>64_000 || header.header.payload.len()!=64 { continue; }
            let dependency_charge: Option<usize>=header.witnesses.iter().try_fold(0usize,|total,(fact,value)| {
                Some(total.saturating_add(fact_heap(facts.get(*fact as usize)?)).saturating_add(value_heap(values.get(*value as usize)?)).saturating_add(64))
            });
            if !dependency_charge.is_some_and(|bytes|bytes<=PAGE_DECODED_BYTES) { continue; }
            let dependencies: Option<Vec<CompactWitness>>=header.witnesses.iter().map(|(fact,value)|Some(CompactWitness {
                fact:*fact_ids.get(*fact as usize)?,value:Arc::clone(value_refs.get(*value as usize)?),
            })).collect();
            let Some(dependencies)=dependencies else { continue; };
            if self.install_compact_candidate(key.clone(),header.header.descriptor.clone(),dependencies,None,
                Some(ProcedureMemoRef{key:header.header.payload.clone()}),true) {
                self.persistence.as_mut().unwrap().headers_seen.insert(key.clone());
                self.stats.metadata_bytes+=key.path.len()+96;
                restored.insert(key.clone());
            }
        }
    }
}
