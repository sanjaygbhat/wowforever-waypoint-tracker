#!/usr/bin/env python3
"""Exercise real service identities against the pinned client map geometry."""
import os,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from service_maps import lua_prelude

def main():
    code=lua_prelude()+(ROOT/'tests/service_regressions.lua').read_text()
    with tempfile.TemporaryDirectory() as tmp:
        script=Path(tmp)/'services.lua';script.write_text(code)
        result=subprocess.run([os.environ.get('LUA51') or shutil.which('lua5.1'),str(script)],cwd=ROOT,timeout=60)
        return result.returncode
if __name__=='__main__':sys.exit(main())
