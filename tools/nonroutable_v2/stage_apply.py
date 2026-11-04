#!/usr/bin/env python3
"""Create proposed bytes and a patch in a NEW directory. Never modify repository files.
Usage: python3 tools/nonroutable_v2/stage_apply.py --out /tmp/wt-v2-review-UNIQUE
"""
import argparse,difflib,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];PACKAGE=ROOT/'tools/nonroutable_v2/package'

def proposal():
    current=(ROOT/'WaypointTracker_Data/Curated.lua').read_text()
    if 'sourceRecoveryV2' in current:raise ValueError('Recovery already present; do not append twice')
    overlay=(PACKAGE/'SourceRecovery.lua').read_text()
    original=(ROOT/'tools/nonroutable_references.tsv').read_text()
    expected={tuple(r.split('\t')[:4]) for r in (ROOT/'tools/nonroutable_v2/input.tsv').read_text().splitlines() if r and not r.startswith('#')}
    actual={tuple(r.split('\t')[:4]) for r in original.splitlines() if r and not r.startswith('#')}
    if actual!=expected:raise ValueError('Exception relationship set changed; reconcile with package ledger before applying')
    return {'WaypointTracker_Data/Curated.lua':(current,current.rstrip()+'\n\n'+overlay),'tools/nonroutable_references.tsv':(original,(PACKAGE/'remaining_exceptions.tsv').read_text())}

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    replacements=proposal();args.out.mkdir(parents=True,exist_ok=False);patch=[];manifest={}
    for name,(old,new) in replacements.items():
        path=args.out/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(new)
        patch.extend(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+name,tofile='b/'+name))
        manifest[name]={'before_sha256':hashlib.sha256(old.encode()).hexdigest(),'after_sha256':hashlib.sha256(new.encode()).hexdigest()}
    (args.out/'apply.patch').write_text(''.join(patch));(args.out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Created review patch:',args.out/'apply.patch');print('Repository files were not modified.')
if __name__=='__main__':main()
