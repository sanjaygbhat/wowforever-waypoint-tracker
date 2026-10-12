#!/usr/bin/env python3
"""Run the existing strict quest-data audit against proposed bytes, without disk edits.
Only the two proposed text reads are replaced; all validation logic/fixtures stay real.
"""
import importlib.util,sys
sys.dont_write_bytecode = True
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
def load(name,path):
 spec=importlib.util.spec_from_file_location(name,path);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
stage=load('v2_stage',ROOT/'tools/nonroutable_v2/stage_apply.py')
current=(ROOT/'WaypointTracker_Data/Curated.lua').read_text()
if 'sourceRecoveryV2' in current:
 # Once applied, audit the real bytes and keep the staging tool's duplicate
 # application rejection intact. Never silently accept a changed overlay.
 overlay=(stage.PACKAGE/'SourceRecovery.lua').read_text()
 assert current.rstrip().endswith(overlay.rstrip()), 'applied recovery differs from reviewed package'
 assert (ROOT/'tools/nonroutable_references.tsv').read_text()==(stage.PACKAGE/'remaining_exceptions.tsv').read_text(), 'applied exception ledger differs'
 try:stage.proposal()
 except ValueError as error:assert 'Recovery already present' in str(error)
 else:raise AssertionError('duplicate recovery application accepted')
 replacements={}
else:
 replacements={str((ROOT/p).resolve()):new for p,(old,new) in stage.proposal().items()}
audit=load('v2_audit',ROOT/'tools/validate_quest_data.py');read=Path.read_text

def proposed_read(path,*args,**kwargs):
 return replacements[str(path.resolve())] if str(path.resolve()) in replacements else read(path,*args,**kwargs)

sys.argv=['validate_quest_data.py','--repo',str(ROOT),'--max-issues','0']
with patch.object(Path,'read_text',proposed_read):audit.main()
