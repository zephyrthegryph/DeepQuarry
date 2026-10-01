use byond_dmb::{dmb::{Dmb, attach_resource_refs}, rsc::{NamedResource,Entry,write_all,named_archive_bytes}};

#[test]
fn borrowed_archive_matches_owned_and_deduplicates_content() {
    let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let first = NamedResource::from_data(0,b"first.txt".to_vec(),vec![42;32768],0,0).unwrap();
    let mut alias = first.clone(); alias.name = b"alias.txt".to_vec();
    let (ids,archive) = attach_resource_refs(&mut dmb,[&first,&alias]).unwrap();
    assert_eq!(ids[0],ids[1]);
    assert_eq!(archive.len(),1);
    assert!(std::ptr::eq(archive[0],&first));
    let bytes = named_archive_bytes(&archive).unwrap();
    assert_eq!(bytes.capacity(),bytes.len());
    let mut expected = Vec::new();
    write_all(&mut expected,&[Entry::Named(first)]).unwrap();
    assert_eq!(bytes,expected);
}

#[test]
fn borrowed_archive_rejects_bad_hash_and_unsafe_name() {
    let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let mut resource = NamedResource::from_data(0,b"test.txt".to_vec(),b"hello".to_vec(),0,0).unwrap();
    resource.id ^= 1;
    assert!(attach_resource_refs(&mut dmb,[&resource]).is_err());
    resource.name.push(0);
    assert!(named_archive_bytes(&[&resource]).is_err());
}
