"""Static CFG debug coverage from an explicit decoded instruction sidecar.

Input schema: {dmb_sha256, procedures:[{identity,instructions:[
 {offset,successors:[word_offsets],kind:'ordinary'|'DbgFile'|'DbgLine',
  file_bytes_hex: optional, line: optional}]}]}.
Every successor list is mandatory, including [] for terminal instructions.
The existing Rust debug_coverage report omits edges and cannot be used directly.
No decoder/edge guessing and no runtime-ownership claim is made here.
"""
import argparse
import hashlib
import json
from collections import deque
from pathlib import Path


def inspect_procedure(procedure):
    rows = procedure['instructions']
    indexes = {}
    for row in rows:
        offset = row['offset']
        if not isinstance(offset, int) or offset < 0 or offset in indexes:
            raise ValueError('invalid/duplicate instruction offset')
        if row.get('kind') not in ('ordinary', 'DbgFile', 'DbgLine'):
            raise ValueError('unknown instruction kind')
        if not isinstance(row.get('successors'), list):
            raise ValueError('explicit successor list required')
        indexes[offset] = row
    for row in rows:
        if any(target not in indexes for target in row['successors']):
            raise ValueError('edge target is not an instruction boundary')
    if not rows:
        return {'identity': procedure['identity'], 'instructions': [], 'unknown_joins': []}
    # A component independently becomes unknown when any incoming paths disagree.
    incoming = {rows[0]['offset']: (None, None)}
    queue = deque([rows[0]['offset']])
    queued = set(queue)
    while queue:
        offset = queue.popleft()
        queued.remove(offset)
        row = indexes[offset]
        file, line = incoming[offset]
        if row['kind'] == 'DbgFile':
            value = row.get('file_bytes_hex')
            try:
                raw = bytes.fromhex(value) if isinstance(value, str) else b''
            except ValueError:
                raw = b''
            file, line = (raw.hex() if raw else None), None
        elif row['kind'] == 'DbgLine':
            value = row.get('line')
            line = value if isinstance(value, int) and value > 0 else None
        outgoing = (file, line)
        for target in row['successors']:
            old = incoming.get(target)
            merged = outgoing if old is None else tuple(a if a == b else None for a, b in zip(old, outgoing))
            if old != merged:
                incoming[target] = merged
                if target not in queued:
                    queue.append(target)
                    queued.add(target)
    predecessors = {offset: [] for offset in indexes}
    for row in rows:
        for target in row['successors']:
            if row['offset'] in incoming:
                predecessors[target].append(row['offset'])
    result = []
    joins = []
    for row in rows:
        offset = row['offset']
        state = incoming.get(offset)
        located = state is not None and all(value is not None for value in state)
        if len(predecessors[offset]) > 1 and state is not None and not located:
            joins.append(offset)
        result.append({'offset': offset, 'reachable': state is not None,
                       'entry_file_bytes_hex': state[0] if state else None,
                       'entry_line': state[1] if state else None,
                       'located_on_all_incoming_paths': located})
    return {'identity': procedure['identity'], 'instructions': result, 'unknown_joins': joins}


def report(dmb, sidecar):
    payload = dmb.read_bytes()
    decoded_bytes = sidecar.read_bytes()
    decoded = json.loads(decoded_bytes)
    digest = hashlib.sha256(payload).hexdigest()
    if decoded.get('dmb_sha256') != digest:
        raise ValueError('decoded sidecar belongs to another DMB')
    return {'schema': 'static-cfg-debug-coverage-v1', 'runtime_ownership_certified': False,
            'edge_completeness_certified': False,
            'limitations': ['Edges and instruction classification are supplied by the decoded sidecar; this tool does not independently decode the DMB.',
                            'Agreement of incoming debug state does not establish runtime execution or error ownership.'],
            'dmb_sha256': digest, 'dmb_bytes': len(payload),
            'decoded_sidecar_sha256': hashlib.sha256(decoded_bytes).hexdigest(),
            'procedures': [inspect_procedure(p) for p in decoded['procedures']]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dmb', type=Path)
    parser.add_argument('decoded_sidecar', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(report(args.dmb, args.decoded_sidecar), indent=2) + '\n', encoding='utf-8')
