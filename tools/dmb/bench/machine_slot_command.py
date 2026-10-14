"""Command preparation for the existing machine-wide slot protocol.

No process is started here. Caller must launch the returned command inside its
existing owned Job and include queue waiting in the same child deadline. This
adapter is only for direct heavy children: repository build orchestration must
acquire its own per-stage slots, never an outer slot around the entire build.
"""
import hashlib,json,os,stat
from pathlib import Path
SCRIPT=Path('E:/projects/CHOMPStation2/tools/dq_machine_slots.sh')
SCRIPT_SHA256='d711a1c716c528347d4ec328b5bfe6ae527eacc14a6a7d7acaece06646db9be4'
BASH=Path('D:/Program Files/Git/bin/bash.exe')
BASH_SHA256='f70ff98512a90090ac394429cc051e54412fb27fbf86a04ed5c1bb1de7365fde'
CAPS={'DQ_SLOTS_DM_COMPILE':'2','DQ_SLOTS_TEST_WORLD':'3','DQ_SLOTS_CARGO':'1','DQ_SLOTS_LOOK_STATE_PIN':'2'}

def nonreparse(value):
    path=Path(os.path.abspath(value))
    if not Path(value).is_absolute():raise ValueError('absolute path required')
    for component in (path,*path.parents):
        try:info=component.lstat()
        except FileNotFoundError:continue
        if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&0x400:
            raise ValueError('reparse path declined: '+str(component))
    return path

def tool_pin(path,expected):
    path=nonreparse(path);info=path.lstat()
    if not stat.S_ISREG(info.st_mode):raise ValueError('slot tool must be regular')
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    if digest!=expected:raise ValueError('machine-slot tool pin changed')
    return {'path':str(path),'sha256':digest,'bytes':info.st_size}

def slot_command(kind,command,worktree,inherited,*,label,hosted_unit_test=False,fixture_test_world=False):
    if kind not in ('dm_compile','test_world','cargo'):raise ValueError('unsupported direct heavy-child slot class')
    if kind=='test_world' and not (hosted_unit_test or fixture_test_world):raise ValueError('explicit hosted or fixture test-world mode required')
    if not command or any(not isinstance(value,str) or '\0' in value for value in command):raise ValueError('invalid direct argv')
    if any(Path(value.replace('\\','/')).name in ('build.sh','build.bat','build.ts','runtime-suite.py','dq_focused_test.sh') for value in command):
        raise ValueError('do not hold an outer slot around slot-aware orchestration')
    owner=nonreparse(worktree)
    if not owner.is_dir() or not owner.is_relative_to(Path('E:/projects')):raise ValueError('explicit E workspace owner required')
    directory=nonreparse(Path('E:/dq-cache/slots'))
    tools={'script':tool_pin(SCRIPT,SCRIPT_SHA256),'bash':tool_pin(BASH,BASH_SHA256)}
    environment=dict(inherited)
    for name in ('DQ_SLOT_PRIORITY','DQ_LOOK_PIN_SLOTS'):environment.pop(name,None)
    environment.update(CAPS,DQ_SLOTS='1',DQ_SLOTS_DIR=str(directory),DQ_SLOT_WORKTREE=str(owner))
    return {'command':[tools['bash']['path'],tools['script']['path'],'run',kind,'--label',label,'--',*command],
            'environment':environment,'evidence':{'kind':kind,'tools':tools,'worktree':str(owner),'slotDirectory':str(directory),
            'worldMode':('fixture' if fixture_test_world else 'hosted' if hosted_unit_test else None),'capacities':dict(CAPS),'waitIncludedInOwnedChildDeadline':True,'jobContainment':'caller must add suspended bash to existing Job before resume'}}

def claim_workspace_target(target,worktree):
    """Exclusive operational owner marker only; never licenses compiler outputs.

    Fresh targets can be claimed; historical unmarked targets fail closed rather
    than silently assigning a cache another workspace may currently be using.
    """
    target=nonreparse(target);owner=nonreparse(worktree)
    if not target.is_relative_to(Path('E:/dq-cache')) or not owner.is_relative_to(Path('E:/projects')) or not owner.is_dir():raise ValueError('owned E target/workspace required')
    marker=target/'.dq-workspace-owner-v1.json';expected={'schema':1,'worktree':str(owner)}
    if target.exists():
        nonreparse(marker);info=marker.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or info.st_size>4096 or json.loads(marker.read_text())!=expected:
            raise ValueError('Cargo target belongs to another or unissued workspace')
    else:
        target.mkdir(parents=True);nonreparse(target)
        with marker.open('x',encoding='utf-8') as file:json.dump(expected,file)
    return {'target':str(target),'owner':expected,'marker':str(marker),'scope':'operational target ownership only, not cache/source admission'}
