#!/usr/bin/env python3
"""Real Forever map geometry for offline service audits (no network).

Run the actual Database.MapForArea/FromClassicMap/Points/Geo.WorldToMap code
against pinned client rectangles rather than wowmock's synthetic map roster.
The full-map, non-WMO assignment with lowest OrderIndex/ID wins. Partial and
WMO assignments are deliberately excluded: these are outdoor zone positions.
"""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = '1.60.1.70862'

def read_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as handle:
        return list(csv.DictReader(handle))

def tables():
    base = ROOT / 'tools/fixtures/client'
    names = {int(r['ID']): r for r in read_csv(base / f'UiMap-{BUILD}-enUS.csv')}
    rows = sorted(read_csv(base / f'UiMapAssignment-{BUILD}-enUS.csv'),
                  key=lambda r: (int(r['OrderIndex']), int(r['ID'])))
    maps = {}; areas = {}
    for r in rows:
        mid = int(r['UiMapID'])
        if mid in maps or mid not in names or any(float(r[k]) != v for k, v in
                [('UiMin_0', 0), ('UiMin_1', 0), ('UiMax_0', 1), ('UiMax_1', 1)]):
            continue
        if int(r['WMODoodadPlacementID']) or int(r['WMOGroupID']):
            continue
        top, left = float(r['Region_3']), float(r['Region_4'])
        w, h = left - float(r['Region_1']), top - float(r['Region_0'])
        if w <= 0 or h <= 0:
            continue
        n = names[mid]
        maps[mid] = dict(mapID=mid, name=n['Name_lang'], mapType=int(n['Type']),
                         parentMapID=int(n['ParentUiMapID']), cont=int(r['MapID']),
                         top=top, left=left, w=w, h=h)
        if int(r['AreaID']):
            areas[int(r['AreaID'])] = n['Name_lang']
    # Real area names, including subzones, from the same client build.
    for r in read_csv(base / f'AreaTable-{BUILD}-enUS.csv'):
        areas.setdefault(int(r['ID']), r['AreaName_lang'])
    return maps, areas

def lua_prelude():
    maps, areas = tables()
    def literal(v):
        return json.dumps(v, ensure_ascii=False)
    code = ["package.path='./tests/?.lua;'..package.path", "local M=require('wowmock')", 'M.maps={}']
    for mid, r in sorted(maps.items()):
        code.append('M.maps[%d]={%s}' % (mid, ','.join(k+'='+literal(v) for k,v in r.items())))
    code += ['local areas={'+','.join('[%d]=%s' % (i,literal(n)) for i,n in sorted(areas.items()))+'}',
             'C_Map.GetAreaInfo=function(id) return areas[id] end',
             '''C_Map.GetBestMapForUnit=function()
 local best,size
 for id,m in pairs(M.maps) do
  if m.cont==M.player.inst and m.mapType==3 then
   local x,y=(m.left-M.player.wy)/m.w,(m.top-M.player.wx)/m.h
   if x>=0 and x<=1 and y>=0 and y<=1 and (not size or m.w*m.h<size) then best,size=id,m.w*m.h end
  end
 end
 return best
end''',
             # The stock mock supports only explicit-map calls. Implement the
             # client's continent fallback with the smallest containing zone.
             '''local explicitWorld=C_Map.GetMapPosFromWorldPos
C_Map.GetMapPosFromWorldPos=function(cont,vec,override)
 if override then return explicitWorld(cont,vec,override) end
 local best,size
 for id,m in pairs(M.maps) do
  if m.cont==cont and m.mapType==3 then
   local x,y=(m.left-vec.y)/m.w,(m.top-vec.x)/m.h
   if x>=0 and x<=1 and y>=0 and y<=1 and (not size or m.w*m.h<size or (m.w*m.h==size and id<best)) then best,size=id,m.w*m.h end
  end
 end
 if best then return explicitWorld(cont,vec,best) end
end''']
    return '\n'.join(code)+'\n'
