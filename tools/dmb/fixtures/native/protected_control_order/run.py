"""Unwinding observation via existing owned paired core; no guessed reference."""
import importlib.util,re
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('protected_core',HERE.parent/'initializer_dependent_order/run.py')
core=importlib.util.module_from_spec(spec);spec.loader.exec_module(core)
def observations(file):
    raw=file.read_bytes()
    if len(raw)>1024*1024:raise ValueError('tiny log exceeds1MiB')
    text=raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
    markers=[line[line.index('DQ_PROTECTED '):] for line in text.splitlines() if 'DQ_PROTECTED ' in line]
    if len(markers)!=4 or any(not row.startswith('DQ_PROTECTED '+prefix) for row,prefix in zip(markers,['return=','loop=','switch=','finished'])):
        raise ValueError('protected control observation incomplete')
    if re.search(r'runtime error:',text,re.I):raise ValueError('fixture logged runtime')
    return {'markers':markers,'runtimes':{}}
core.HERE=HERE;core.observations=observations
if __name__=='__main__':raise SystemExit(core.main())
