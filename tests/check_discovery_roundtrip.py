#!/usr/bin/env python3
"""Fresh Lua 5.1 SavedVariables VMs; table matrix plus real review identities."""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from service_maps import lua_prelude


def run(script, *args, cwd=ROOT, faction='Alliance'):
    result = subprocess.run(['perl', '-e', 'alarm shift; exec @ARGV', '60',
                             os.environ.get('LUA51') or shutil.which('lua5.1'), str(script), *map(str,args)],
                            cwd=cwd, env=dict(os.environ, WT_FACTION=faction, WT_ROUNDTRIP_BASELINE='1' if cwd!=ROOT else '0'),
                            capture_output=True, text=True, timeout=65)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout


def main():
    baseline=Path(sys.argv[2]).resolve() if len(sys.argv)==3 and sys.argv[1]=='--baseline' else None
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        script = tmp / 'matrix.lua'
        script.write_text(lua_prelude() + (ROOT / 'tests/discovery_roundtrip.lua').read_text())
        for faction in ('Alliance', 'Horde'):
            state = tmp / (faction + '.lua')
            before = run(script, 'observe', state, faction=faction)
            after = run(script, 'reload', state, faction=faction)
            if baseline:
                old_state=tmp/(faction+'-baseline.lua')
                old=run(script,'observe',old_state,cwd=baseline,faction=faction)
                old_after=run(script,'reload',old_state,cwd=baseline,faction=faction)
                assert old==old_after,'baseline roundtrip changed'
                # Supplement replacement/compaction is new in 1.4.1. The
                # other four sources must preserve released 1.4.0 semantics.
                def comparable(text):
                    rows=[]
                    for line in text.splitlines():
                        if not line.startswith('CASE\t') or line.startswith('CASE\tsupplement\t'): continue
                        fields=line.split('\t')
                        # 1.4.1 deliberately excludes explicit hostile services;
                        # keep comparing their Find/export/save semantics.
                        if fields[2]=='hostile': fields[6]=''
                        rows.append(fields)
                    return rows
                assert comparable(old)==comparable(before),faction+' differs from released baseline'
            assert before == after, faction + ' changed Nearest/Find/export/save after fresh reload\n' + before + '\n' + after
        script=tmp/'real.lua'
        script.write_text(lua_prelude()+(ROOT/'tests/discovery_real_roundtrip.lua').read_text())
        for faction in ('Alliance','Horde'):
            state=tmp/(faction+'-real.lua')
            before=run(script,'observe',state,faction=faction)
            after=run(script,'reload',state,faction=faction)
            assert before==after,faction+' real identities changed after reload'
            run(script,'import',state,faction=faction)
        script=tmp/'passive.lua'
        script.write_text(lua_prelude()+(ROOT/'tests/discovery_passive_trainers.lua').read_text())
        for faction in ('Alliance','Horde'):
            for source in ('personal','import'):
                for path in ('merge','ticker'):
                    state=tmp/(faction+source+path+'.lua')
                    before=run(script,'observe',state,source,path,faction=faction)
                    after=run(script,'reload',state,source,path,faction=faction)
                    assert before==after,'passive trainer changed after fresh-interpreter reload'
        print('Discovery roundtrip: 60 source/reaction/access cases x both factions; fresh VMs identical')


if __name__ == '__main__':
    main()
