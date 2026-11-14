"""Compare every emitted native and pinned Checker diagnostic in order.

The caller must bracket the independent runs with official same-frame input
observations. This comparator neither invokes an oracle nor validates source
input authority, and equality is not universal Checker parity. Selected native
reports and incomplete pinned runs fail closed. Source paths are normalized
lexically against the mandatory frozen absolute root, without filesystem reads.
Unrecorded path aliases remain differences; supply a sealed captured mapping in
a separately reviewed integration rather than resolving symlinks after capture.
"""
import argparse,json,re
from pathlib import Path, PurePosixPath, PureWindowsPath
PHASES=['reader_declarations','variable_declarations','settings_prelude','body','keyword_overrides','sleep_graph','purity_graph']
LOC=re.compile(r'^(.+), line ([0-9]+), column ([0-9]+):$')
MSG=re.compile(r'^(error|warning|info|hint): (.*)$')

def frozen_root(value):
    """Parse an observed absolute spelling; never stat/resolve/query aliases."""
    # Keep the caller/host's explicit flavour. In particular, a POSIX // root
    # must not turn a literal backslash filename into a Windows separator.
    if isinstance(value,(PureWindowsPath,PurePosixPath)):
        if value.is_absolute():return value
        raise ValueError('the observed root is not fully absolute in its path flavour')
    text=str(value)
    if text.startswith('//'):
        raise ValueError('ambiguous root requires an explicitly captured path flavour')
    win=PureWindowsPath(text)
    if win.is_absolute():return win
    posix=PurePosixPath(text)
    if posix.is_absolute() and not win.drive:return posix
    raise ValueError('a frozen absolute checkout root from the input observation is required')


def path_name(text,root):
    root=frozen_root(root)
    # Builtin/synthetic sentinels are wire spellings, never guessed files.
    if text in ('(builtins)','(unknown)'):
        return text
    win=PureWindowsPath(text)
    if isinstance(root,PureWindowsPath):
        if win.is_absolute():return win.as_posix()
        if win.drive or win.root:raise ValueError('ambiguous drive-relative/rooted Windows source path')
        return (root/win).as_posix()
    if win.drive:raise ValueError('Windows source spelling differs from frozen POSIX frame')
    posix=PurePosixPath(text)
    return (posix if posix.is_absolute() else root/posix).as_posix()
    # Pure paths preserve '..', case and extended namespaces. No unsealed
    # alias, case-folding or symlink-equivalence rule can qualify a difference.


def reference_rows(text,root):
    root=frozen_root(root)
    rows=[];where=None;current=None
    for line in text.splitlines():
        if not line:
            where=None;current=None;continue
        match=LOC.fullmatch(line)
        if match:
            where=(path_name(match[1],root),int(match[2]),int(match[3]));current=None;continue
        match=MSG.fullmatch(line)
        if match:
            if where is None:raise ValueError('diagnostic without complete location: '+line)
            current=dict(file=where[0],line=where[1],column=where[2],severity=match[1],message=match[2],notes=[])
            rows.append(current);continue
        if line.startswith('- '):
            if current is None:raise ValueError('unattached reference note')
            current['notes'].append(line[2:]);continue
        # Do not silently omit untagged/multiline/config/parse diagnostics.
        raise ValueError('unparsed pinned stderr content: '+line)
    return rows

def require_reference_completion(stdout,returncode,rows):
    # Exact pinned main.rs prints this only after actual parse/check completion.
    lines=stdout.splitlines()
    markers=['Analyzing variables...','Gathering proc settings...','Analyzing proc bodies...',
             'Analyzing proc override validity...','Analyzing proc call tree...']
    positions=[]
    for marker in markers:
        found=[at for at,line in enumerate(lines) if line==marker]
        if len(found)!=1:raise ValueError('pinned Checker did not execute every real CLI phase exactly once')
        positions.append(found[0])
    if positions!=sorted(positions):raise ValueError('pinned CLI phase order differs')
    summaries=[at for at,line in enumerate(lines) if re.fullmatch(r'Found [0-9]+ diagnostics',line)]
    if len(summaries)!=1 or summaries[0]<=positions[-1]:raise ValueError('pinned summary preceded completed final phase')
    counts=[match[1] for line in lines if (match:=re.fullmatch(r'Found ([0-9]+) diagnostics',line))]
    if len(counts)!=1 or int(counts[0])!=len(rows):
        raise ValueError('pinned summary disagrees with all parsed emitted rows')
    expected=1 if rows else 0
    if returncode!=expected:raise ValueError('pinned CLI operational/exit result disagrees')

def native_rows(report,root):
    root=frozen_root(root)
    if report.get('row')!='source_native_original_ordered_checker':raise ValueError('wrong native report')
    if report.get('full_checker_parity') is not False:raise ValueError('premature producer parity claim')
    receipt=report.get('scope_completion',{})
    if receipt.get('scope')!='whole_input_current_ordered_producers' or receipt.get('completed_phase_order')!=PHASES:
        raise ValueError('selected/partial phase report cannot qualify whole-input observation')
    count=receipt.get('visited_bodies')
    if not isinstance(count,int) or isinstance(count,bool) or count<0:raise ValueError('invalid body visitation receipt')
    if report.get('phase_order')!=PHASES:raise ValueError('native phase ordering differs')
    rows=[];prior=-1
    for row in report['diagnostics']:
        phase=PHASES.index(row['phase'])
        if phase<prior:raise ValueError('diagnostic phase order regressed')
        prior=phase
        if row['severity'] not in ('error','warning','info'):raise ValueError('not pinned CLI emitted levels')
        if row['location_kind'] not in ('source','builtin','parser_synthetic'):raise ValueError('unknown location contract')
        if not isinstance(row['notes'],list) or any(not isinstance(note,str) for note in row['notes']):raise ValueError('unrepresented notes')
        rows.append(dict(file=path_name(row['file'],root),line=row['line'],column=row['column'],severity=row['severity'],message=row['message'],notes=row['notes']))
    return rows

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--native',type=Path,required=True);p.add_argument('--pinned-stderr',type=Path,required=True);p.add_argument('--pinned-stdout',type=Path,required=True);p.add_argument('--pinned-exit',type=int,required=True);p.add_argument('--root',type=Path,required=True)
    a=p.parse_args();root=frozen_root(a.root)
    report=json.loads(a.native.read_text(encoding='utf8'));old=reference_rows(a.pinned_stderr.read_text(encoding='utf8'),root);require_reference_completion(a.pinned_stdout.read_text(encoding='utf8'),a.pinned_exit,old);new=native_rows(report,root)
    equal=old==new
    print(json.dumps(dict(all_emitted_rows_equal=equal,reference_count=len(old),native_count=len(new),source_frame_validated_by_this_tool=False,universal_checker_parity=False)))
    if not equal:print(json.dumps(dict(reference=old,native=new),indent=2))
    return 0 if equal else 1
if __name__=='__main__':raise SystemExit(main())
