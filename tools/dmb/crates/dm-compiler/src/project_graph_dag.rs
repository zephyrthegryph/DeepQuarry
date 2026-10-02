//! Persistent, content-addressed semantic read sets. Session headers only point
//! at immutable fact/value/readset rows, so worktrees share declaration strings.
use super::*;

fn read_nodes(p: &Persistence, keys: &[dm_store::Key], content_addressed: bool) -> io::Result<BTreeMap<dm_store::Key, Vec<u8>>> {
    let mut result = BTreeMap::new();
    for group in keys.chunks(4096) {
        let batch = p.store.read_grouped_bounded(group,128,MAX_HEADER,PREFETCH_BATCH_BYTES,PREFETCH_BATCH_BYTES,None);
        let batch = match batch {
            Ok(batch) => batch,
            Err(error) if error.kind() == io::ErrorKind::InvalidInput && group.len()>1 => {
                result.extend(read_nodes(p, &group[..group.len()/2], content_addressed)?);
                result.extend(read_nodes(p, &group[group.len()/2..], content_addressed)?);
                continue;
            }
            Err(error) => return Err(error),
        };
        for (key, bytes) in group.iter().zip(batch.values) {
            let Some(bytes) = bytes else { continue; };
            if content_addressed && format!("{:x}", Sha256::digest(&bytes)) != key.name { continue; }
            result.insert(key.clone(), bytes);
        }
    }
    Ok(result)
}

impl ProjectProcedureGraph {
    /// Cold starts open only the database. The caller requests compact semantic
    /// headers in source-order windows; deleted/unrequested projects are never
    /// scanned. Payload bytes remain independently lazy.
    pub fn prepare_keys(&mut self, keys: &[ProcKey]) -> io::Result<usize> {
        let started = std::time::Instant::now();
        let Some(p) = self.persistence.as_ref() else { return Ok(0); };
        let requested: Vec<_> = keys.iter().filter(|key| !p.headers_seen.contains(*key) && !self.records.contains_key(*key)).cloned().collect();
        let mut restored = 0;
        let mut read_seconds = 0.0f64;
        let mut decode_seconds = 0.0f64;
        let mut install_seconds = 0.0f64;
        for window in requested.chunks(4096) {
            // Batch header I/O independently from bounded witness decoding.
            // All rows are addressed by authored keys; no namespace scan occurs.
            let p = self.persistence.as_ref().unwrap();
            let names: Vec<_> = window.iter().map(|key| {
                dm_store::Key::new(&p.headers_namespace, format!("{:x}", Sha256::digest(serde_json::to_vec(key).expect("procedure key serialization"))))
            }).collect();
            let read_started = std::time::Instant::now();
            let rows = read_nodes(p, &names, false)?;
            read_seconds += read_started.elapsed().as_secs_f64();
            for (group, names) in window.chunks(256).zip(names.chunks(256)) {
            // Leave room for one bounded raw-node page. Never discard decoded
            // rows during its reconstruction: requested keys may intentionally
            // have skipped reads because they were already cached.
            if self.decoded_nodes.bytes > 8*1024*1024 {
                self.stats.metadata_bytes = self.stats.metadata_bytes.saturating_sub(self.decoded_nodes.bytes);
                self.decoded_nodes = DecodedDagNodes::default();
            }
            let p = self.persistence.as_ref().unwrap();
            let mut headers = Vec::new();
            for (key, name) in group.iter().zip(names) {
                let Some(bytes) = rows.get(name).filter(|bytes| !bytes.is_empty()) else { continue; };
                if let Ok(header) = serde_json::from_slice::<DiskHeader>(bytes) {
                    if header.key == *key { headers.push(header); }
                }
            }
            let readset_keys: Vec<_> = headers.iter().filter_map(|header| header.readset.as_ref()).map(|name| dm_store::Key::new(&p.readsets_namespace, name)).collect::<BTreeSet<_>>().into_iter().collect();
            let read_started = std::time::Instant::now();
            let readset_rows = read_nodes(p, &readset_keys, true)?;
            read_seconds += read_started.elapsed().as_secs_f64();
            let readsets: BTreeMap<_,_> = readset_rows.into_iter().filter_map(|(key, bytes)| serde_json::from_slice::<DiskReadSet>(&bytes).ok().map(|set| (key.name, set))).collect();
            let node_keys: Vec<_> = readsets.values().flat_map(|set| set.witnesses.iter()).flat_map(|(fact, value)| {
                [(!self.decoded_nodes.facts.contains_key(fact)).then(|| dm_store::Key::new(&p.facts_namespace, fact)),
                 (!self.decoded_nodes.values.contains_key(value)).then(|| dm_store::Key::new(&p.values_namespace, value))].into_iter().flatten()
            }).collect::<BTreeSet<_>>().into_iter().collect();
            let read_started = std::time::Instant::now();
            let nodes = read_nodes(p, &node_keys, true)?;
            read_seconds += read_started.elapsed().as_secs_f64();
            let decode_started = std::time::Instant::now();
            let facts_namespace = p.facts_namespace.clone();
            let values_namespace = p.values_namespace.clone();
            let mut page_facts = BTreeMap::new();
            let mut page_values = BTreeMap::new();
            for (key, bytes) in nodes {
                let charge = key.name.capacity()+128;
                if key.namespace == facts_namespace {
                    if let Ok(fact) = serde_json::from_slice::<BindingFact>(&bytes) {
                        let id = self.intern_fact(&fact);
                        if self.decoded_nodes.bytes+charge <= 16*1024*1024 {
                            self.decoded_nodes.bytes += charge; self.stats.metadata_bytes += charge;
                            self.decoded_nodes.facts.insert(key.name.clone(), id);
                        }
                        page_facts.insert(key.name, id);
                    }
                } else if key.namespace == values_namespace {
                    if let Ok(value) = serde_json::from_slice::<FactValue>(&bytes) {
                        let value = self.intern_value(&value);
                        let charge = charge+value_heap(&value);
                        if self.decoded_nodes.bytes+charge <= 16*1024*1024 {
                            self.decoded_nodes.bytes += charge; self.stats.metadata_bytes += charge;
                            self.decoded_nodes.values.insert(key.name.clone(), Arc::clone(&value));
                        }
                        page_values.insert(key.name, value);
                    }
                }
            }
            self.stats.header_read_batches += 1;
            self.stats.metadata_bytes += group.iter().map(|key| key.path.len()+96).sum::<usize>();
            self.persistence.as_mut().unwrap().headers_seen.extend(group.iter().cloned());
            decode_seconds += decode_started.elapsed().as_secs_f64();
            let install_started = std::time::Instant::now();
            for mut header in headers {
                if let Some(readset) = &header.readset {
                    let Some(set) = readsets.get(readset) else { self.stats.corrupt_records += 1; continue; };
                    let decoded: Option<Vec<BindingWitness>> = set.witnesses.iter().map(|(fact, value)| {
                        Some(BindingWitness {
                            fact: (*self.fact_names[*self.decoded_nodes.facts.get(fact).or_else(|| page_facts.get(fact))? as usize]).clone(),
                            value: (**self.decoded_nodes.values.get(value).or_else(|| page_values.get(value))?).clone(),
                        })
                    }).collect();
                    let Some(decoded) = decoded else { self.stats.corrupt_records += 1; continue; };
                    header.dependencies = decoded;
                }
                if self.install_candidate(header.key, header.descriptor, header.dependencies.into(), None, Some(ProcedureMemoRef { key: header.payload }), true) {
                    restored += 1;
                }
            }
            install_seconds += install_started.elapsed().as_secs_f64();
            }
            if std::env::var_os("DM_BUILD_TRACE").is_some() { eprintln!("DM_BUILD_TRACE procedure headers: {restored} restored of {} requested in {:.3}s; read={read_seconds:.3}s decode={decode_seconds:.3}s install={install_seconds:.3}s",requested.len(),started.elapsed().as_secs_f64()); }
        }
        self.stats.restored_procedures += restored;
        // Newly loaded facts require the next resolver replay even if its
        // declaration revision otherwise equals the previous page's revision.
        if restored>0 { self.revision = None; }
        self.stats.prepared_header_seconds += started.elapsed().as_secs_f64();
        Ok(restored)
    }

    /// Validates Salsa witnesses without reading or decoding body payloads.
    /// Identity includes the exact immutable candidate and cannot equate two
    /// lowering results merely because the authored descriptor stayed equal.
    pub fn probe_identity(&mut self, key: &ProcKey, descriptor: &ProcDescriptor) -> Option<String> {
        let started = std::time::Instant::now();
        self.stats.identity_probes += 1;
        let result = self.probe_identity_inner(key, descriptor);
        self.stats.identity_probe_seconds += started.elapsed().as_secs_f64();
        result
    }
    fn probe_identity_inner(&mut self, key: &ProcKey, descriptor: &ProcDescriptor) -> Option<String> {
        if !self.ensure_record(key, descriptor) { return None; }
        let candidate = current_candidate(&self.db, self.records[key].input).as_ref()?;
        if let Some(disk) = &candidate.disk { return Some(disk.key.clone()); }
        let mut digest = Sha256::new();
        digest.update(candidate.descriptor.body_digest.as_bytes());
        digest.update(candidate.descriptor.frame_digest.as_bytes());
        for witness in candidate.dependencies.iter() {
            digest.update(serde_json::to_vec(self.fact_names[witness.fact as usize].as_ref()).ok()?);
            digest.update(serde_json::to_vec(witness.value.as_ref()).ok()?);
        }
        Some(format!("{:x}", digest.finalize()))
    }
    pub fn probe_validity(&mut self, key: &ProcKey, descriptor: &ProcDescriptor) -> Option<String> { self.probe_identity(key, descriptor) }
}
