//! Actual source, not expected diagnostics or a replacement oracle.
pub const CASES:usize=7;
pub fn configuration(case:usize)->String{match case{2=>"[lint.doc_snippets]\nexempt_files=[\"code/names.dm\"]\n".into(),3=>"[lint.doc_snippets]\nexempt_files=[\"doc/rewrite/a.md\"]\n".into(),_=>String::new()}}
pub fn files(case:usize)->Vec<(&'static str,String)>{assert!(case<CASES);let mut rows:Vec<(&'static str,String)>=vec![
 ("code/names.dm","/proc/doc_known()\n    return\n/obj/doc_owner/proc/inherited_doc()\n    return\n/obj/doc_other/proc/foreign_doc()\n    return\n#define DOC_MACRO(value) value\n".into()),
 ("code/.hidden/not_indexed.dm","/proc/hidden_doc_name()\n    return\n".into()),
 ("doc/rewrite/a.md","# real doc fixture\n```dm\n/obj/doc_owner/child/proc/example()\n    doc_known()\n    inherited_doc()\n    DOC_MACRO(1)\n    missing_doc(); missing_doc()\n    foreign_doc()\n    src.foreign_doc()\n    permitted_doc() // ALLOW(doc_snippets): retained documentation example is deliberately unresolved\n```\n```dm fragment\n/proc/local_doc()\n    return\nlocal_doc()\nnew runtime_type()\nsrc.Add()\nhidden_doc_name()\n```\n```dm before\nold_absent_doc()\n```\n".into()),
 ("doc/rewrite/z.md","Unicode indentation\n\u{2003}```dm sketch\n\u{2003}another_missing_doc()\n\u{2003}```\n```dm\n// an unclosed complete block is retained\nunclosed_doc()\n".into()),
 ("doc/rewrite/archive/old.md","```dm\narchive_missing_doc()\n```\n".into()),
 ("doc/rewrite/.hidden.md","```dm\nhidden_missing_doc()\n```\n".into()),
 ("tools/ci/doc_snippets_baseline.txt","# initial original baseline\ndoc_legacy_block\tdoc/rewrite/a.md\t/obj/doc_owner/child/proc/example()\ndoc_legacy_block\tdoc/rewrite/z.md\t// an unclosed complete block is retained\n".into()),
 ("deepquarry.dme","#include \"code/names.dm\"\n".into())];
 if case==1{rows.iter_mut().find(|(p,_)|*p=="doc/rewrite/a.md").unwrap().1.push_str("```dm\n/proc/new_complete_doc()\n    fresh_missing_doc()\n```\n");}
 if case==4{rows.iter_mut().find(|(p,_)|*p=="doc/rewrite/a.md").unwrap().1="# no code blocks\n".into();rows.iter_mut().find(|(p,_)|*p=="doc/rewrite/z.md").unwrap().1="# no code blocks either\n".into();}
 if case==5{rows.retain(|(p,_)|*p!="tools/ci/doc_snippets_baseline.txt");}
 // Raw-name checking must survive an unrelated malformed compiled project.
 if case==6{rows.iter_mut().find(|(p,_)|*p=="deepquarry.dme").unwrap().1="#include \"not_a_real_compilation_input.dm\"\n".into();}
 rows}
