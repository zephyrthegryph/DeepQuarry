//! Shared lexical backing and its lazy span-fingerprint cache.
use super::*;
impl HeapCensus {
    /// SAME weak source owner: actual control allocation survives its payload.
    /// Never upgrade a known-dead source; live temporary loans drop here and
    /// are not cached/pinned. Every alias uses this census's existing dedup set.
    pub(crate) fn weak_source_text_resource(&mut self,owner:&str,value:&dm_preprocess::WeakSourceText){
        value.visit_derived_resource_storage(|pointer,bytes|{self.buffer(owner,pointer,bytes,bytes);});
        let mut live=false;value.visit_backing_storage(|_,logical,_|live=logical!=0);
        if live{if let Some(source)=value.upgrade(){self.source_text(owner,&source);return;}}
        value.visit_backing_storage(|pointer,logical,capacity|{self.buffer(owner,pointer,logical,capacity);});
    }

    pub(super) fn source_text(&mut self, owner: &str, value: &dm_preprocess::SourceText) {
        value.visit_derived_resource_storage(|pointer,bytes|{ self.buffer(owner,pointer,bytes,bytes); });
        value.visit_fingerprint_storage(|pointer, logical, capacity| {
            self.buffer(owner, pointer, logical, capacity);
        });
        value.visit_storage(|pointer, size, storage| {
            if self.buffer(owner, pointer, size, size) {
                match storage {
                    dm_preprocess::SourceTextStorage::Original(text) => self.arc_text(owner, text),
                    dm_preprocess::SourceTextStorage::Transformed(text) => self.string(owner, text),
                    dm_preprocess::SourceTextStorage::Reserved { text, committed } => {
                        self.buffer(owner, text.as_ptr() as usize, text.len(), committed);
                    }
                }
            }
        });
    }
}
