import path from 'node:path';

// Exact canonical production roster accepted by dmbc's GenerationRequest.
const generators = [
  'actions', 'auto_tracked', 'declare', 'declare_ids', 'deps', 'derived_reads',
  'plans', 'reads', 'stats', 'system_accessors', 'tracked_lists', 'ui_types',
] as const;

export function nativeGenerationRequest(root: string, cacheRoot: string, workers: number) {
  return {
    check: false,
    build: {
      command: 'PrepareQuery',
      project: path.join(root, 'deepquarry.dme'),
      defines: {},
      workers,
      engine_template: null,
      bootstrap_catalog: false,
      progress_enabled: false,
      output_store: null,
      exact_inputs: true,
      no_cache: false,
      cache_root: cacheRoot,
      record_inputs: null,
      replay_inputs: null,
      artifact_directory: null,
      no_daemon: false,
      trace_path: null,
      timeout_seconds: 300,
      policy_inputs: {
        analysis_context: 'original_analyze0290',
        files: [],
        search_folders: [],
        workspace_generators: generators,
        workspace_auxiliary: [],
        workspace: {
          root,
          recursive_roots: [path.join(root, 'code')],
          configuration: path.join(root, 'tools/ci/lint_scopes.toml'),
        },
      },
    },
  };
}

/** The dmbc CLI has already validated the terminal, spool hash and report rows. */
export function nativeGenerationWrittenCount(output: string): number {
  const [headerLine, reportLine, ...remainder] = output.trimEnd().split('\n');
  const header = JSON.parse(headerLine);
  const report = JSON.parse(reportLine);
  if (remainder.length || header.schema !== 'native-generation-batch-v1'
      || header.row !== 'generation_batch' || header.status !== 'completed'
      || header.clean !== true || header.cleanup_warnings !== 0
      || report.schema !== 'native-generation-v1' || report.clean !== true
      || typeof header.committed !== 'boolean' || header.committed !== report.committed
      || !Array.isArray(report.changed)
      || !report.changed.every((file: unknown) => typeof file === 'string' && path.isAbsolute(file))
      || new Set(report.changed).size !== report.changed.length
      || header.committed !== (report.changed.length !== 0)) {
    throw new Error('native generation did not return a completed clean report');
  }
  return report.changed.length;
}
