use byond_dmb::{
    dmb::{Dmb, ResourceAttachment, ResourceLookup},
    rsc::{read_entry, NamedResource},
};
use std::io::ErrorKind;

#[test]
fn malformed_resource_length_is_rejected_without_reading_payload() {
    let header = u32::MAX.to_le_bytes();
    assert_eq!(
        read_entry(&mut header.as_slice()).unwrap_err().kind(),
        ErrorKind::InvalidData
    );
}

#[test]
fn writer_rejects_dangling_proc_reference() {
    let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    dmb.classes[0].lists_and_procs[2] = dmb.procs.len() as u32 + 1;
    assert_eq!(dmb.to_bytes().unwrap_err().kind(), ErrorKind::InvalidData);
}

#[test]
fn indexed_asset_batch_reuses_dmb_and_rsc_entries() {
    let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let mut archive = Vec::new();
    let asset =
        NamedResource::from_data(6, b"fixture.txt".to_vec(), b"contents".to_vec(), 0, 0).unwrap();
    let id = {
        let mut batch = ResourceAttachment::new(&mut dmb, &mut archive);
        let id = batch.attach(asset.clone()).unwrap();
        assert_eq!(batch.attach(asset.clone()).unwrap(), id);
        id
    };
    assert_eq!(archive.len(), 1);
    assert_eq!(ResourceLookup::new(&archive).get(&dmb, id), Some(&asset));
}
