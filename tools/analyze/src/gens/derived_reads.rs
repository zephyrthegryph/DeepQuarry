//! `analyze gen derived_reads` -> `code/_generated/reads.dm`: the hand-written `derived()` lists' generated reads, as the `derived_reads` lint judges them.
//! The file lives beside the legacy `_generated` directory (not under `code/engine/_generated/`), so the generator reports it through `files()`, which
//! `analyze gen --check` compares byte for byte like every other generated file.

use crate::lints::derived_reads::{generated_for, GENERATED_REL};
use crate::sem::gen::{GenCx, GenOut, Generator};
use crate::tree::CODE_DM;

struct DerivedReadsGen;

impl Generator for DerivedReadsGen {
    fn name(&self) -> &'static str {
        "derived_reads"
    }

    fn stage(&self) -> u8 {
        1
    }

    fn output(&self) -> &'static str {
        ""
    }

    fn generate(&self, _cx: &GenCx, _out: &mut GenOut) {}

    fn files(&self, cx: &GenCx, _out: &mut GenOut) -> Vec<(String, String)> {
        let files = cx.tree.select(&CODE_DM);
        vec![(GENERATED_REL.to_string(), generated_for(cx.tree, &files))]
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(DerivedReadsGen));
}
