//! Actual previous diagnostic-only owner and retained preparation payloads.
use super::*;
pub(super) fn inspect(census:&mut HeapCensus,state:&dm_tree::frontend::RetainedSemanticTree){
 use dm_tree::frontend::AnalysisRetentionStorage as V;
 let mut present=false;state.visit_previous_analysis_storage(|view|{present=true;match view{
  V::Allocation{address,bytes}=>{census.buffer("retained_analysis.owners",address,bytes,bytes);},
  V::Source(view)=>{census.frontend_storage(view.storage_view());census.body_archive(view.archive());},
  V::Declarations(index)=>{census.slice("retained_analysis.declaration_roster",index.shared_roster(),true);for(_,owner)in index.owners(){super::retained_normalization::contribution(census,owner);}if !index.is_empty(){census.unknown("retained_analysis.declarations","private keyed-declaration BTree node backing is not exposed; actual shared owner/roster payloads counted");}},
  V::Symbols(symbols)=>census.symbols(symbols),
  V::SymbolTable(symbols)=>{census.symbol_table_storage("retained_analysis.symbol_catalog",symbols);census.unknown("retained_analysis.symbol_catalog","private SymbolTable index bucket geometry remains unexposed");},
  V::Engine(engine)=>{census.symbol_table_storage("retained_analysis.engine_symbols",&engine.symbols);census.vec_payload("retained_analysis.engine_parents",&engine.hierarchy.parents);census.slice("retained_analysis.engine_intrinsics",&engine.intrinsics,true);census.slice("retained_analysis.engine_fields",&engine.fields,true);census.unknown("retained_analysis.engine_symbols","private SymbolTable index bucket geometry remains unexposed");},
  V::Receipt(receipt)=>{if census.arc_object("retained_analysis.receipt",receipt){receipt.visit_error_storage(|address,len,capacity|{census.buffer("retained_analysis.receipt.errors",address,len,capacity);});}},
 }});
 if present{census.unknown("retained_analysis.owners","standard Arc control blocks/allocator overhead are unexposed; actual inline owner/records/catalog payload sizes are counted at original pointers");}
}
