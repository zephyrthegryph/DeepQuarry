//! Native-only executable client. It never loads the legacy Analyze engine.
fn main()->std::process::ExitCode{
 let args=std::env::args().skip(1).collect::<Vec<_>>();
 if let Some(exit)=dq_analyze::native_cli_client::workspace_check(&args){return exit;}
 match args.first().map(String::as_str){
  Some("query"|"native-query")=>dq_analyze::native_cli_client::cli(&args[1..]),
  Some("native-exclusions")=>dq_analyze::native_cli_client::exclusions_cli(&args[1..]),
  Some("native-image-dir")=>dq_analyze::native_cli_client::image_dir_cli(&args[1..]),
  Some("native-check")=>dq_analyze::native_cli_client::policy_cli(&args[1..],false),
  Some("native-baseline")=>dq_analyze::native_cli_client::policy_cli(&args[1..],true),
  Some("gen"|"native-gen")=>dq_analyze::native_cli_client::generation_cli(&args[1..]),
  _=>{eprintln!("usage: analyze-native (query|native-check|native-baseline|native-exclusions|native-image-dir|gen) [options]");std::process::ExitCode::from(2)}
 }
}
