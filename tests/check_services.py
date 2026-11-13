#!/usr/bin/env python3
"""Evidence, regeneration and real-client-map coverage gates for base Nearest."""
import copy
import csv
import hashlib
import json
import math
import re
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import build_services as b
import audit_services as audit
import service_maps

# Reviewed helper exclusions with faction bits: obsolete test endpoints. Other
# helpers lack service bits; instanced battleground stops are outside this addon.
FLIGHT_EXCLUSIONS={
    '3206': "zzOLDBolder'ok, Riverglades",
    '3207': 'zzOLDRiverglades, Farholde Keep',
    '3208': 'zzOLDPowderfuse Port, Riverglades',
}

def check_flight_inventory(test, text):
    source={r['ID']:r for r in service_maps.read_csv(ROOT/f'tools/fixtures/client/TaxiNodes-{service_maps.BUILD}-enUS.csv')}
    for rid,name in FLIGHT_EXCLUSIONS.items():test.assertEqual(source[rid]['Name_lang'],name)
    expected={rid for rid,r in source.items() if r['ContinentID'] in ('0','1') and int(r['Flags'] or 0)&3}-FLIGHT_EXCLUSIONS.keys()
    block=re.search(r'flights = \[\[(.*?)\]\]',text,re.S)[1]
    ids=[line.split('\t')[0] for line in block.strip().splitlines()]
    test.assertEqual(set(ids),expected,'complete client flight ID inventory')
    test.assertEqual(len(ids),len(expected),'unique client flight IDs')
    names=re.findall(r'(enUS|deDE|frFR|esES|esMX|ptBR|ruRU|zhCN|zhTW|koKR) = \{\s*flights = \[\[(.*?)\]\]',text,re.S)
    test.assertEqual({loc for loc,_ in names},set('enUS deDE frFR esES esMX ptBR ruRU zhCN zhTW koKR'.split()))
    for loc,block in names:
        ids=[line.split('\t')[0] for line in block.strip().splitlines()]
        test.assertEqual(set(ids),expected,loc+' complete flight names')
        test.assertEqual(len(ids),len(expected),loc+' unique flight names')

class Services(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows,cls.rejected=b.derive()
        cls.data=audit.summarize(audit.probe())
        cls.maps,_=service_maps.tables()

    def test_generated_output_and_preserved_wtl(self):
        text=b.OUTPUT.read_text()
        self.assertEqual(text.count(b.START),1)
        self.assertEqual(text.count(b.END),1)
        self.assertEqual(text,b.generate(text,self.rows))
        self.assertEqual(text.split(b.START)[0],b.generate(text,self.rows).split(b.START)[0])
        self.assertEqual(len(self.rows),801)
        self.assertGreaterEqual(sum(len(r['positions']) for r in self.rows),2245)

    def test_pinned_inputs(self):
        manifest=json.loads((ROOT/'tools/fixtures/manifest.json').read_text())
        for path in (ROOT/'tools/fixtures/services').iterdir():
            if path.is_file():
                name=str(path.relative_to(ROOT/'tools/fixtures'))
                self.assertIn(name,manifest)
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),manifest[name]['sha256'])
                self.assertIn('license',manifest[name])
                self.assertIn('source',manifest[name])

    def test_literal_evidence_per_row_and_position(self):
        evidence=json.loads(b.FIXTURE.read_text())
        for r in self.rows:
            self.assertTrue(r['name']);self.assertIn(r['fac'],('A','H','AH'))
            self.assertLessEqual(set(r['services']),b.SERVICES)
            for s in r['services']:
                ref=r['proof'][s];self.assertIsNotNone(ref)
                record=evidence['eg']['files'][ref['path']]['collections'][ref['collection']][ref['id']]
                if r['kind']=='O':self.assertIn(record['name'],('Mailbox','Meeting Stone'))
                else:
                    services=b.title_services(record.get('name',''),record.get('title',''))
                    services.update(b.INTERACTIONS[v] for v in record.get('interactions',[]) if v in b.INTERACTIONS)
                    if ref['collection']=='vendors':
                        services.add('vendor')
                        if record.get('repairs') is True:services.add('repair')
                    self.assertIn(s,services)
            for p in r['positions']:
                self.assertIn(p['m'],self.maps)
                self.assertTrue(0<=p['x']<=1 and 0<=p['y']<=1)
                ref=p['source']
                if 'att' in ref:
                    raw=evidence['att']['files'][ref['att']]['records'][ref['record']]
                    self.assertEqual(raw['id'],r['id']);self.assertIn('coords=',raw['literal'])
                else:
                    raw=evidence['eg']['files'][ref['path']]['collections'][ref['collection']][ref['id']]['positions'][ref['index']]
                    self.assertEqual((p['m'],p['x'],p['y']),(raw['uiMap'],raw['mapX'],raw['mapY']))
                    self.assertEqual(p['c'],self.maps[p['m']]['cont'])
                    if 'worldX' in raw and 'worldY' in raw:
                        m=self.maps[p['m']]
                        error=math.hypot(m['top']-p['y']*m['h']-raw['worldX'],m['left']-p['x']*m['w']-raw['worldY'])
                        self.assertLess(error,2,(r['id'],ref,'world/native agreement'))

    def test_unknown_access_excluded(self):
        for r in self.rejected:
            if r['reason']=='unknown faction access':
                self.assertFalse(any(v['kind']==r['kind'] and v['id']==r['id'] for v in self.rows))

    def test_no_trainers_in_supplement(self):
        self.assertFalse(any('trainer' in s for r in self.rows for s in r['services']))

    def test_explicit_vendor_titles_and_no_repair_inference(self):
        for title in ('Meat Vendor','Reagent Vendor','Bag Vendor','Food & Drink Merchant'):
            self.assertEqual(b.title_services('Example',title),{'vendor'})
        self.assertEqual(b.title_services('Example','Blacksmith'),set())
        self.assertEqual(b.title_services('Example','Assistant Innkeeper'),set())
        self.assertEqual(b.title_services('Example','Weapon Master'),set())

    def test_capitals_have_eight_local_services(self):
        keys=set('mailbox innkeeper banker auctioneer flight repair vendor stablemaster'.split())
        for faction,ids in audit.CAPITALS.items():
            for mid in ids:
                capital=self.maps[mid]['name']
                for s in keys:
                    matches=[r for r in self.data['nearest'] if r['faction']==faction and r['origin']==capital and r['service']==s]
                    self.assertEqual(len(matches),1)
                    r=matches[0];self.assertIsNotNone(r['distance'],(capital,s))
                    self.assertLess(r['distance'],2500,(capital,s,r))
                    # Darnassus uses Rut'theran's flight service outside the city.
                    if s=='flight' and mid==1457:self.assertEqual(r['map'],1438)
                    elif s!='flight':
                        dest=self.maps[r['map']];city=self.maps[mid]
                        wx=dest['top']-r['y']*dest['h'];wy=dest['left']-r['x']*dest['w']
                        self.assertTrue(0<=(city['left']-wy)/city['w']<=1 and 0<=(city['top']-wx)/city['h']<=1,(capital,s,r))

    def test_common_knowledge_regressions(self):
        near={(r['origin'],r['service']):r for r in self.data['nearest']}
        self.assertEqual(near['Ironforge','innkeeper']['id'],5111)
        self.assertEqual(near['Ironforge','innkeeper']['map'],1455)
        self.assertEqual(near['Stormwind City','auctioneer']['map'],1453)
        self.assertEqual(near['Stormwind City','flight']['map'],1453)
        self.assertNotIn('Generic',near['Stormwind City','flight']['name'])

    def test_all_town_service_results_measured(self):
        self.assertEqual(len(self.data['origins']),26)
        self.assertEqual(len(self.data['nearest']),286)
        for r in self.data['nearest']:
            self.assertIsNotNone(r['distance'],r)
            self.assertGreaterEqual(r['distance'],0)

    def test_minimum_identity_and_spawn_coverage(self):
        minimum={'mailbox':(85,150),'innkeeper':(28,29),'flight':(73,75),
                 'repair':(178,200),'vendor':(529,609),'banker':(17,20),
                 'auctioneer':(17,20),'stablemaster':(25,28),'spirithealer':(2,115),
                 'battlemaster':(12,90),'meetingstone':(20,35)}
        for key,s in self.data['summary'].items():
            ids,spawns=minimum[key.split('/')[0]]
            self.assertGreaterEqual(s['identities'],ids,key)
            self.assertGreaterEqual(s['spawns'],spawns,key)
        # Unknown maps and out-of-bounds points must never count as coverage.
        for r in self.data['entries']:
            for p in r['points']:
                self.assertIn(p['m'],self.maps)
                self.assertTrue(0<=p['x']<=1 and 0<=p['y']<=1,(r,p))
                self.assertNotEqual(r['learned'],'you')

    def test_mailboxes_and_stones_roster_accounted(self):
        # Every literal pfQuest spawn is audited, including omitted identities.
        raw={(r['service'],r['id']):r for r in self.data['roster']}
        for s in ('mailbox','meetingstone'):
            self.assertEqual(set(b.pf_services()[s]),{i for k,i in raw if k==s})
        complete=json.loads((ROOT/'tools/fixtures/services/pfquest-roster.json').read_text())
        self.assertEqual(complete['commit'],'104f35678ca39ab1fb78b655f815cc7016f5e0c8')
        for service,rows in complete['roster'].items():
            for rid,row in rows.items():
                actual=raw[service,int(rid)]
                wanted=sorted((int(p['3']),float(p['1']),float(p['2'])) for p in row['coords'].values())
                got=sorted((p['area'],p['classic_x'],p['classic_y']) for p in actual['spawns'])
                self.assertEqual(wanted,got,(service,rid,'complete source spawn inventory'))
                self.assertEqual(actual['fac'],row['fac'])
        self.assertEqual(sum(len(r['coords']) for r in complete['roster']['mailbox'].values()),60)
        self.assertEqual(sum(len(r['coords']) for r in complete['roster']['meetingstone'].values()),22)
        # Every Forever object observation has service evidence, never a quest
        # provider, similarly named NPC or guessed object position.
        for r in self.rows:
            if r['kind']=='O':self.assertIn(r['services'],[['mailbox'],['meetingstone']])

    def test_real_map_shapes_and_mock_crosscheck(self):
        self.assertEqual(self.maps[1455]['name'],'Ironforge')
        self.assertGreaterEqual(len(self.maps),50)
        # The one real rectangle in the original mock is rounded to centimetres.
        m=self.maps[1453]
        self.assertAlmostEqual(m['top'],-7995.83,places=2)
        self.assertAlmostEqual(m['left'],1722.92,places=2)
        self.assertAlmostEqual(m['w'],1737.504,places=2)
        self.assertAlmostEqual(m['h'],1158.34,places=2)

    def test_complete_metadata_access_inventory(self):
        expected=json.loads((ROOT/'tools/fixtures/services/pfquest-roster.json').read_text())['roster']
        self.assertEqual(set(b.pf_services()),b.SERVICES)
        for service,rows in expected.items():
            self.assertEqual(b.pf_services()[service],{int(rid):row['fac'] for rid,row in rows.items()},service)

    def test_neutral_witnessed_services(self):
        rows={r['id']:r for r in self.rows if r['kind']=='N'}
        for rid,name,x,y,services in [(260559,'Gilliwigs',.7929,.5467,['vendor']),
                                    (260566,'Fizzix Boomshot',.7856,.5358,['repair','vendor'])]:
            r=rows[rid]
            self.assertEqual((r['name'],r['fac'],r['services']),(name,'H',services))
            self.assertEqual([(p['m'],p['x'],p['y']) for p in r['positions']],[(2548,x,y)])

    def test_reactions_need_service_evidence_per_faction(self):
        for reactions,witnessed,wanted in [({'Horde':[4]},True,'H'),({'Alliance':[4],'Horde':[4]},True,'AH'),
                ({'Horde':[4]},False,None),({'Horde':[3,4]},True,None),({},True,None),({'Horde':[5]},False,None)]:
            evidence=json.loads(b.FIXTURE.read_text());files=evidence['eg']['files']
            prefix='data/wowf/1.60.1.70888/'
            files[prefix+'creatures.json']['collections']['creatures']['999999']={'name':'Synthetic','reactions':reactions}
            files[prefix+'creature_details.enUS.json']['collections']['creatures']['999999']={'name':'Synthetic','title':'Trade Goods'}
            files[prefix+'npcs.json']['collections']['npcs']['999999']={'name':'Synthetic','interactions':['Merchant'] if witnessed else ['Gossip']}
            rows,_=b.derive(evidence)
            actual=[r for r in rows if r['id']==999999]
            self.assertEqual(actual[0]['fac'] if actual else None,wanted,(reactions,witnessed))

    def test_no_taxi_helpers_or_precision_loss(self):
        text=(ROOT/'WaypointTracker_Data/Client.lua').read_text()
        check_flight_inventory(self,text)
        block=re.search(r'flights = \[\[(.*?)\]\]',text,re.S)[1]
        source={r['ID']:r for r in service_maps.read_csv(ROOT/f'tools/fixtures/client/TaxiNodes-{service_maps.BUILD}-enUS.csv')}
        for line in block.strip().splitlines():
            f=line.split('\t');r=source[f[0]]
            self.assertTrue(int(r['Flags'])&3)
            self.assertEqual((f[3],f[4]),(r['Pos_0'],r['Pos_1']))

    def test_flight_inventory_rejects_lost_real_stop_and_locales(self):
        text=(ROOT/'WaypointTracker_Data/Client.lua').read_text()
        mutated=re.sub(r'^559\t[^\n]*\n','',text,flags=re.M)
        self.assertNotEqual(mutated,text)
        with self.assertRaisesRegex(AssertionError,'559'):
            check_flight_inventory(self,mutated)

if __name__=='__main__':unittest.main()
