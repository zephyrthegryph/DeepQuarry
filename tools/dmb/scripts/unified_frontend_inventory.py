#!/usr/bin/env python3
"""Read-only migration inventory for the unified native analysis frontend.

This is a source dependency audit, not a semantic coverage certificate. It never
starts compilers, changes baselines or declares a diagnostic family migrated.
Run with --root PATH; optionally supply --checker-source PINNED_SPACEMANDMM.
Output is deterministic JSON on stdout. Missing checker source is explicit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import tomllib

PIN = '0290db5c752fa292f9824521515b603a2afd11dc'
SCHEMA = 'dq-unified-frontend-inventory-v1'
ANCHORS = {
    'query_dependencies': 'tools/dmb/crates/dm-query/src/lib.rs',
    'typed_syntax': 'tools/dmb/crates/dm-syntax/src/lib.rs',
    'borrowed_body_visitor': 'tools/dmb/crates/dm-analysis/src/typed_body.rs',
    'lexical_bindings': 'tools/dmb/crates/dm-analysis/src/typed_body_lexical.rs',
    'selected_references': 'tools/dmb/crates/dm-analysis/src/typed_body_selected_bound.rs',
    'builtin_catalog': 'tools/dmb/crates/dmbc/src/engine_catalog.rs',
    'host_analysis': 'tools/dmb/crates/dmbc/src/runner_analysis.rs',
}
RAW_STRING = re.compile(r'(?:br|cr|r)(#*)"')
CHAR_LITERAL = re.compile(r"'(?:\\(?:u\{[0-9a-fA-F_]+\}|x[0-9a-fA-F]{2}|.)|[^'\\\n])'")
DEPENDENCIES = {
    'parser_types': r'\bdreammaker\s*::',
    'object_tree': r'\b(?:objtree|ObjectTree)\b',
    'semantic_facade': r'\b(?:sem\s*::|Sem\b)',
    'body_ast': r'\b(?:ProcBody|Expression|Statement|Block)\b',
    'whole_tree_scan': r'\bfn\s+scan_tree\b',
    'text_frontend': r'\b(?:FrontendKind|DreamMakerFrontend|Program)\b',
}


def code_view(source: str) -> str:
    """Blank Rust comments and string/char literals, retaining newlines/offsets.

    Handles nested block comments and raw strings; Rust lifetimes remain code.
    This is deliberately lexical: unqualified names can be false positives.
    """
    out = list(source)
    n = len(source)
    i = 0
    while i < n:
        start = i
        if source.startswith('//', i):
            end = source.find('\n', i)
            i = n if end < 0 else end
        elif source.startswith('/*', i):
            depth = 1
            i += 2
            while i < n and depth:
                if source.startswith('/*', i):
                    depth += 1
                    i += 2
                elif source.startswith('*/', i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
        else:
            raw = RAW_STRING.match(source, i)
            if raw and (i == 0 or not (source[i - 1].isalnum() or source[i - 1] == '_')):
                terminator = '"' + raw.group(1)
                end = source.find(terminator, raw.end())
                i = n if end < 0 else end + len(terminator)
            elif source[i] == '"':
                i += 1
                while i < n:
                    if source[i] == '\\':
                        i += 2
                    elif source[i] == '"':
                        i += 1
                        break
                    else:
                        i += 1
            elif source[i] == "'" and (char := CHAR_LITERAL.match(source, i)):
                i = char.end()
            else:
                i += 1
                continue
        for j in range(start, min(i, n)):
            if source[j] not in '\r\n':
                out[j] = ' '
    return ''.join(out)


def file_record(path: Path, root: Path) -> dict:
    raw = path.read_bytes()
    text = raw.decode('utf-8-sig')
    code = code_view(text)
    dependencies = {}
    for name, pattern in DEPENDENCIES.items():
        lines = sorted({code.count('\n', 0, match.start()) + 1 for match in re.finditer(pattern, code)})
        if lines:
            dependencies[name] = lines
    return {
        'file': path.relative_to(root).as_posix(),
        'sha256': hashlib.sha256(raw).hexdigest(),
        'dependencies': dependencies,
        'status': 'needs_semantic_review' if dependencies else 'no_lexical_dependency_found',
    }


def checker_inventory(source: Path | None) -> dict:
    if source is None:
        return {'status': 'source_unavailable', 'required_commit': PIN,
                'families': None, 'coverage_complete': False}
    # No assumption about source files or pass architecture beyond the crate.
    candidates = [source / 'crates/dreamchecker', source / 'dreamchecker', source]
    crate = next((p for p in candidates if (p / 'Cargo.toml').is_file()
                  and 'dreamchecker' == tomllib.loads((p / 'Cargo.toml').read_text(encoding='utf-8'))
                  .get('package', {}).get('name')), None)
    if crate is None:
        raise ValueError('checker source must contain the dreamchecker Cargo package')
    files = [file_record(p, crate) for p in sorted((crate / 'src').rglob('*.rs'))]
    if not files:
        raise ValueError('checker source contains no Rust source files')
    return {'status': 'source_present_pin_not_verified', 'required_commit': PIN,
            'files': files, 'families': None, 'coverage_complete': False,
            'next_gate': 'Verify source commit and enumerate diagnostic registration/pass families; file inventory is not checker coverage.'}


def inventory(root: Path, checker_source: Path | None = None) -> dict:
    analyze = root / 'tools/analyze'
    manifest = tomllib.loads((analyze / 'Cargo.toml').read_text(encoding='utf-8'))
    files = [file_record(p, root) for p in sorted((analyze / 'src').rglob('*.rs'))]
    if not files:
        raise ValueError('Analyze source directory is empty')
    anchors = {}
    for name, relative in ANCHORS.items():
        path = root / relative
        anchors[name] = file_record(path, root) if path.is_file() else {'file': relative, 'status': 'missing'}
    consumers = {}
    for category in ('lints', 'gens', 'codemods', 'sem', 'frontend'):
        prefix = f'tools/analyze/src/{category}/'
        rows = [f for f in files if f['file'].startswith(prefix)]
        consumers[category] = {
            'files': rows,
            'file_count': len(rows),
            'direct_parser_files': sum('parser_types' in f['dependencies'] for f in rows),
            'semantic_review_files': sum(bool(f['dependencies']) for f in rows),
        }
    config_path = root / 'SpacemanDMM.toml'
    return {
        'schema': SCHEMA,
        'limitations': [
            'Lexical dependencies are migration candidates, not a type-resolved call graph.',
            'No lexical match does not prove a consumer is independent: follow helper dependencies.',
            'Checker rules and semantic parity remain unverified; no production cutover is certified.',
        ],
        'analyze_parser_dependency': manifest.get('dependencies', {}).get('dreammaker'),
        'consumers': consumers,
        'other_analyze_files': [f for f in files if not any(
            f['file'].startswith(f'tools/analyze/src/{c}/') for c in consumers)],
        'native_contracts': anchors,
        'checker': checker_inventory(checker_source),
        'checker_config': tomllib.loads(config_path.read_text(encoding='utf-8')) if config_path.is_file() else None,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--checker-source', type=Path)
    parser.add_argument('--require-checker-source', action='store_true',
                        help='fail if source is missing; this does not certify source pin or checker coverage')
    args = parser.parse_args(argv)
    try:
        result = inventory(args.root, args.checker_source)
    except (OSError, ValueError, tomllib.TOMLDecodeError) as error:
        print(f'unified inventory: {error}', file=sys.stderr)
        return 2
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write('\n')
    return 1 if args.require_checker_source and args.checker_source is None else 0


if __name__ == '__main__':
    raise SystemExit(main())
