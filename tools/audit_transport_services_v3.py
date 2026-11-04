#!/usr/bin/env python3
"""Supplement v3 taxi audit with local GameObjects and TransportAnimation.

Read-only CASC access; no WTF; only explicitly supplied NEW output is written.
Client object rows are static data, not proof of current server spawns/access.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from audit_transport_v3 import decode_wdc5, compare_csv
from verify_legs_casc import LocalCASC, require

ANIMATION = (1140686, 0x6B9AEBE5, 3861033221, None,
             [('Pos','f',3),('SequenceID','i',1),('TimeIndex','i',1)])
OBJECTS = (841620, 0x13C403A5, 0x44BD453C, 3, [
    ('Name_lang','s',1),('Pos','f',3),('Rot','f',4),('ID','i',1),('OwnerID','i',1),
    ('DisplayID','i',1),('Flags','i',1),('Scale','f',1),('TypeID','i',1),
    ('PhaseUseFlags','i',1),('PhaseID','i',1),('PhaseGroupID','i',1),
    ('Field_11_0_0_54210_011','i',1),('PropValue','i',8)])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    require(not args.output.exists(),'refusing to overwrite existing file')
    casc=LocalCASC('/Applications/World of Warcraft')
    require(casc.build['Version!STRING:0']=='1.60.1.70338','requires build 70338')
    animations=decode_wdc5(casc.file(ANIMATION[0],'TransportAnimation'),ANIMATION,'TransportID')
    cache=Path(__file__).resolve().parents[1]/'tools/.cache/travel/TransportAnimation.csv'
    raw_cache=cache.read_bytes()
    cells=compare_csv(animations,raw_cache)
    objects=decode_wdc5(casc.file(OBJECTS[0],'GameObjects'),OBJECTS)
    tram={}
    for row in animations:
        if row['TransportID'] in (176080,176081,176082,176083,176084,176085,657020,657021,657022,657023,657024,657025):
            tram.setdefault(str(row['TransportID']),[]).append(row)
    for ps in tram.values():ps.sort(key=lambda r:r['TimeIndex'])
    relevant=[r for r in objects if any(k in r['Name_lang'].lower() for k in
                ('portal','tram','boat','zeppelin','skycutter','transport','ship','tidegear','powderfuse'))]
    evidence=dict(build=casc.build,casc_files=casc.manifest,
                  animation_rows=len(animations),animation_cache_cells_verified=cells,
                  animation_cache_sha256=hashlib.sha256(raw_cache).hexdigest(),gameobject_rows=len(objects),
                  tram_animation_candidates=tram,relevant_client_objects=relevant,
                  unavailable={'SpellMisc':'Local CASC reader reports encrypted BLTE mode E; no bypass attempted.'},
                  notes=['Tram TimeIndex values are animation milliseconds, not exterior-entrance-to-entrance time.',
                         'TransportID identifies object entry; instance/phase/spawn is not established.',
                         'GameObjects is not the server gameobject_template table.'])
    with args.output.open('x') as stream:json.dump(evidence,stream,indent=2);stream.write('\n')
    print(json.dumps(dict(animation_rows=len(animations),verified_cells=cells,objects=len(objects),
                         relevant_objects=len(relevant),tram_candidates=list(tram)),indent=2))


if __name__=='__main__':main()
