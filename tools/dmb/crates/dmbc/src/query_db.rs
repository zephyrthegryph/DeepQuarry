//! The session's query database (doc/incremental_core.md, migration step 1).
//!
//! One [`dm_query::Db`] per retained session. Each request is a revision: its inputs are the
//! prepared source files (`source(path)`, content-hashed) and the project configuration
//! (`project`). The derived `program` query reads every input in canonical order; it is green
//! exactly when no input changed. Later steps hang the frontend, per-unit and output queries off
//! these inputs and replace the per-stage stores.
use dm_query::{Db, Key, Kind, Outcome, QueryError, Value};
use std::collections::BTreeMap;
use std::path::PathBuf;
use dm_preprocess::regions::prepared_source::PreparedSource;
use std::sync::{Arc, Mutex};

const SOURCE: Kind = Kind(1);
const PROJECT: Kind = Kind(2);
const PROGRAM: Kind = Kind(3);

fn source_key(path: &std::path::Path) -> Key {
    Key::new(SOURCE, dm_query::hash_bytes(path.as_os_str().as_encoded_bytes()))
}
const PROJECT_KEY: Key = Key { kind: PROJECT, id: 0 };
const PROGRAM_KEY: Key = Key { kind: PROGRAM, id: 0 };

/// What one revision did.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Revision {
    pub revision: u64,
    pub sources: usize,
    pub changed: usize,
    pub removed: usize,
    /// The program query revalidated without running (no input changed).
    pub green: bool,
}

pub struct QueryDb {
    db: Db,
    /// Sources of the previous revision by path: key, the prepared owner (held, so an unchanged
    /// capture is recognised by identity without rehashing) and its content hash.
    sources: Mutex<BTreeMap<PathBuf, (Key, Arc<PreparedSource>, u128)>>,
}
impl Default for QueryDb {
    fn default() -> Self {
        let db = Db::new();
        db.define_input(SOURCE, "source");
        db.define_input(PROJECT, "project");
        db.define(PROGRAM, "program", |ctx, params| {
            let keys = params
                .downcast_ref::<Vec<Key>>()
                .ok_or(QueryError::Missing(PROGRAM_KEY))?;
            let mut hasher = xxhash_rust::xxh3::Xxh3::new();
            hasher.update(&ctx.observe_input(PROJECT_KEY)?.to_le_bytes());
            for key in keys {
                hasher.update(&key.id.to_le_bytes());
                hasher.update(&ctx.observe_input(*key)?.to_le_bytes());
            }
            let hash = hasher.digest128();
            Ok(Outcome::new(hash, hash, 16))
        });
        Self {
            db,
            sources: Mutex::new(BTreeMap::new()),
        }
    }
}
impl QueryDb {
    pub fn db(&self) -> &Db {
        &self.db
    }
    /// Advance to this request's inputs and revalidate the program query.
    pub fn revise(
        &self,
        sources: &dm_preprocess::regions::prepared_source::PreparedSources,
        project: u128,
    ) -> Result<Revision, QueryError> {
        let computed_before = self.db.stats(PROGRAM).computed;
        let mut previous = self.sources.lock().unwrap_or_else(|error| error.into_inner());
        let mut current = BTreeMap::new();
        let mut changed = 0;
        for (path, source) in sources.iter() {
            let (key, hash) = match previous.get(path) {
                Some((key, held, hash)) if Arc::ptr_eq(held, source) => (*key, *hash),
                _ => (
                    source_key(path),
                    dm_query::hash_bytes(source.original().as_str().as_bytes()),
                ),
            };
            if self.db.set_input(key, (), hash) {
                changed += 1;
            }
            current.insert(path.clone(), (key, Arc::clone(source), hash));
        }
        let mut removed = 0;
        for (path, (key, _, _)) in previous.iter() {
            if !current.contains_key(path) && self.db.remove(*key) {
                removed += 1;
            }
        }
        self.db.set_input(PROJECT_KEY, (), project);
        let keys: Vec<Key> = current.values().map(|(key, _, _)| *key).collect();
        let count = keys.len();
        *previous = current;
        drop(previous);
        let params: Value = Arc::new(keys);
        self.db.hash(PROGRAM_KEY, params)?;
        Ok(Revision {
            revision: self.db.revision(),
            sources: count,
            changed,
            removed,
            green: self.db.stats(PROGRAM).computed == computed_before,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_preprocess::regions::prepared_source::PreparedSources;

    fn sources(files: &[(&str, &str)]) -> PreparedSources {
        PreparedSources::from_prepared(files.iter().map(|(path, text)| {
            (PathBuf::from(path), Arc::new(PreparedSource::new(Arc::from(*text))))
        }))
        .unwrap()
    }

    #[test]
    fn program_is_green_only_when_no_input_changed() {
        let db = QueryDb::default();
        let first = db.revise(&sources(&[("a.dm", "x"), ("b.dm", "y")]), 1).unwrap();
        assert!(!first.green);
        assert_eq!((first.sources, first.changed), (2, 2));
        let same = db.revise(&sources(&[("a.dm", "x"), ("b.dm", "y")]), 1).unwrap();
        assert!(same.green, "{same:?}");
        let edited = db.revise(&sources(&[("a.dm", "x2"), ("b.dm", "y")]), 1).unwrap();
        assert!(!edited.green);
        assert_eq!(edited.changed, 1);
        let removed = db.revise(&sources(&[("a.dm", "x2")]), 1).unwrap();
        assert!(!removed.green);
        assert_eq!(removed.removed, 1);
        let project = db.revise(&sources(&[("a.dm", "x2")]), 2).unwrap();
        assert!(!project.green);
        assert!(db.revise(&sources(&[("a.dm", "x2")]), 2).unwrap().green);
    }
}
