#!/usr/bin/env python3
"""Inventory the pinned checker's diagnostic construction sites, not parity.

Literal family names alone are insufficient: untagged diagnostics, registration
helpers and dynamically forwarded errors remain in the work list as well.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

from unified_frontend_inventory import PIN, code_view

FAMILY = re.compile(r'\bwith_errortype\s*\(\s*"([^"\\]+)"\s*\)')
CONSTRUCTION = re.compile(r'\b(?:error|DMError::new)\s*\(')
FUNCTION = re.compile(r'\bfn\s+([A-Za-z_][A-Za-z_0-9]*)\b')


def destination(function: str) -> str:
    if function == 'check_var_defs':
        return 'native declaration queries'
    if any(word in function for word in ('directive', 'gather_settings')):
        return 'native configuration and procedure-setting queries'
    if any(word in function for word in ('call_tree', 'propagate', 'finish_check_kwargs')):
        return 'native SCC inference and retractable call contributions'
    if 'kwargs' in function:
        return 'native signature and override queries'
    return 'native typed-body, CFG and expression queries'


def sites(source: str, relative: str) -> dict:
    code = code_view(source)
    functions = list(FUNCTION.finditer(code))

    def context(offset: int) -> dict:
        function = next((match[1] for match in reversed(functions)
                         if match.start() < offset), '<module>')
        return {'file': relative, 'line': source.count('\n', 0, offset) + 1,
                'function': function, 'destination': destination(function)}

    families = []
    for match in FAMILY.finditer(source):
        if code.startswith('with_errortype', match.start()):
            families.append({'family': match[1], **context(match.start())})
    constructions = []
    for match in CONSTRUCTION.finditer(code):
        # The helper's definition constructs no diagnostic by itself.
        if re.search(r'\bfn\s*$', code[max(0, match.start() - 12):match.start()]):
            continue
        constructions.append(context(match.start()))
    return {'families': families, 'construction_sites': constructions}


def inventory(source_root: Path) -> dict:
    crate = source_root / 'crates/dreamchecker'
    if not (crate / 'Cargo.toml').is_file():
        raise ValueError('expected a complete pinned SpacemanDMM source checkout')
    license_file = source_root / 'LICENSE'
    if not license_file.is_file():
        raise ValueError('reference source license is missing')
    family_sites = []
    construction_sites = []
    files = []
    for path in sorted((crate / 'src').rglob('*.rs')):
        relative = path.relative_to(source_root).as_posix()
        raw = path.read_bytes()
        found = sites(raw.decode('utf-8'), relative)
        family_sites.extend(found['families'])
        construction_sites.extend(found['construction_sites'])
        files.append({'file': relative, 'sha256': hashlib.sha256(raw).hexdigest()})
    if not files or not construction_sites:
        raise ValueError('checker source contains no diagnostic construction sites')
    families = []
    for family in sorted({site['family'] for site in family_sites}):
        locations = [site for site in family_sites if site['family'] == family]
        families.append({'family': family, 'sites': locations,
                         'status': 'reference-only; native parity not established'})
    return {
        'schema': 'dq-checker-coverage-worklist-v1', 'required_commit': PIN,
        'source_pin_verified_by_this_tool': False,
        'license_sha256': hashlib.sha256(license_file.read_bytes()).hexdigest(),
        'files': files, 'families': families, 'construction_sites': construction_sites,
        'coverage_complete': False,
        'unclassified_contracts': [
            'Untagged constructions and forwarded parser/constant errors need message and location parity.',
            'Pragmas, severity defaults, suppression, multiplicity and note order require differential fixtures.',
            'A lexical worklist does not prove inference coverage or native grammar completeness.',
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checker-source', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        result = inventory(args.checker_source)
    except (OSError, UnicodeError, ValueError) as error:
        print(f'checker inventory: {error}', file=sys.stderr)
        return 2
    text = json.dumps(result, indent=2, sort_keys=True) + '\n'
    if args.output:
        args.output.write_text(text, encoding='utf-8')
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
