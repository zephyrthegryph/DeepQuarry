//! Same-boot admission for immutable files written or authenticated by this store.
use super::*;
use crate::input_snapshot::{FileSystemInputs, SnapshotProvider, Stamp};

#[derive(Serialize, Deserialize)]
struct ResourceVerification {
    schema: u32,
    boot: [u8; 16],
    identity: ResourceIdentity,
    stamp: Stamp,
}

impl PairStore {
    pub(super) fn remember_verified(
        &self,
        pair: &OutputPair,
        stable: Vec<Stamp>,
    ) -> io::Result<()> {
        self.verified
            .lock()
            .map_err(|_| invalid("pair verification lock poisoned"))?
            .insert(pair.id, (pair.clone(), stable.clone()));
        if let Some(boot) = boot_identity() {
            if stable.iter().all(|stamp| stamp.file_id.is_some()) {
                let receipt = BootVerification {
                    schema: 1,
                    boot,
                    pair: pair.clone(),
                    stamps: stable,
                };
                self.cache_receipt(&format!("{:032x}.json", pair.id), &receipt);
            }
        }
        Ok(())
    }

    fn cache_receipt(&self, name: &str, value: &impl Serialize) {
        // Receipt failure never invalidates successfully authenticated output.
        // The next process repeats full authentication instead.
        if let Ok(directory) = self.temporary("verification") {
            let staged = StagedPath::new(directory);
            let temp = staged.path().join("receipt.json");
            if write_json(&temp, value).is_ok() {
                let _ = atomic_replace(&temp, &self.root.join("verified").join(name));
            }
        }
    }

    pub(super) fn remember_resource(
        &self,
        path: &Path,
        identity: ResourceIdentity,
        expected: &Stamp,
    ) -> io::Result<Stamp> {
        let stamp = FileSystemInputs.stamp(path)?;
        if &stamp != expected {
            return Err(invalid("resource inode changed before admission"));
        }
        if stamp.size != identity.bytes {
            return Err(invalid("resource admission size mismatch"));
        }
        self.verified_resources
            .lock()
            .map_err(|_| invalid("resource verification lock poisoned"))?
            .insert((identity.bytes, identity.hash), stamp.clone());
        if let Some(boot) = boot_identity() {
            if stamp.file_id.is_some() {
                self.cache_receipt(
                    &format!("resource-{:032x}-{}.json", identity.hash, identity.bytes),
                    &ResourceVerification {
                        schema: 1,
                        boot,
                        identity,
                        stamp: stamp.clone(),
                    },
                );
            }
        }
        Ok(stamp)
    }

    pub(super) fn authenticate_resource(
        &self,
        path: &Path,
        identity: ResourceIdentity,
        exact: bool,
    ) -> io::Result<Stamp> {
        let stamp = FileSystemInputs.stamp(path)?;
        if stamp.size != identity.bytes {
            return Err(invalid("shared resource size mismatch"));
        }
        if !exact && stamp.file_id.is_some() {
            if self
                .verified_resources
                .lock()
                .map_err(|_| invalid("resource verification lock poisoned"))?
                .get(&(identity.bytes, identity.hash))
                == Some(&stamp)
            {
                return Ok(stamp);
            }
            if let Some(boot) = boot_identity() {
                let receipt_path = self.root.join("verified").join(format!(
                    "resource-{:032x}-{}.json",
                    identity.hash, identity.bytes
                ));
                if let Ok(file) = File::open(receipt_path) {
                    let mut bytes = Vec::new();
                    if file.take(65537).read_to_end(&mut bytes).is_ok() && bytes.len() <= 65536 {
                        if let Ok(receipt) = serde_json::from_slice::<ResourceVerification>(&bytes)
                        {
                            if receipt.schema == 1
                                && receipt.boot == boot
                                && receipt.identity == identity
                                && receipt.stamp == stamp
                                && FileSystemInputs.stamp(path)? == stamp
                            {
                                return self.remember_resource(path, identity, &stamp);
                            }
                        }
                    }
                }
            }
        }
        #[cfg(test)]
        publication_fault("resource_authentication_read")?;
        if file_identity(path)? != (identity.bytes, identity.hash)
            || FileSystemInputs.stamp(path)? != stamp
        {
            return Err(invalid("shared RSC bytes do not match identity"));
        }
        self.remember_resource(path, identity, &stamp)
    }
}
