"""Source atlas contract checks; never reads or writes player saves."""
import json
from pathlib import Path
import struct
import subprocess
import unittest
from check_staged import blob_issues

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / 'BM/Resources/MatchArt'
MANIFEST = json.loads((ART / 'fielders-v1.json').read_text())

class FieldSpriteSourceTests(unittest.TestCase):
    def test_eight_directions_and_eight_unique_actions(self):
        self.assertEqual(set(MANIFEST['sheets']), {'n','ne','e','se','s','sw','w','nw'})
        self.assertEqual(len(set(MANIFEST['actions'])), 8)
        self.assertEqual(MANIFEST['status'], 'source-preview-only')
        for sheet in MANIFEST['sheets'].values():
            self.assertEqual([f['action'] for f in sheet['frames']], MANIFEST['actions'])

    def test_rgba_png_and_reviewed_hashes(self):
        for sheet in MANIFEST['sheets'].values():
            path = ART / sheet['file']; data = path.read_bytes()
            self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
            self.assertEqual(list(struct.unpack('>II', data[16:24])), sheet['size'])
            self.assertEqual(data[25], 6, 'RGBA required')
            self.assertEqual(blob_issues(str(path.relative_to(ROOT)), data), [])

    def test_no_canvas_clipping_and_stable_foot_contract(self):
        for sheet in MANIFEST['sheets'].values():
            self.assertEqual(sheet['referenceHeight'], sheet['frames'][0]['rect'][3])
            for frame in sheet['frames']:
                x,y,w,h = frame['rect']; px,py = frame['pivot']
                self.assertTrue(x>0 and y>0 and x+w<sheet['size'][0] and y+h<sheet['size'][1])
                self.assertEqual((px,py), (w/2,h))
                self.assertGreater(frame['opaqueArea'],10000)
                self.assertTrue(frame['clipRows'])
                for row,left,width in frame['clipRows']:
                    self.assertTrue(0 <= row < h and 0 <= left < w and 0 < width <= w-left)

    def test_preview_has_no_save_or_remote_dependency(self):
        source=(ROOT/'scripts/preview_field_sprites.html').read_text()
        for forbidden in ['localStorage','sessionStorage','indexedDB','https://','http://']:
            self.assertNotIn(forbidden,source)
        self.assertIn('prefers-reduced-motion',source)
        self.assertIn('imageSmoothingEnabled=false',source)

class RuntimeSpriteTests(unittest.TestCase):
    def test_role_sources_contacts_and_masks_are_bundled(self):
        m=json.loads((ART/'field-runtime-v1.json').read_text())
        self.assertEqual(set(m['kinds']),{'fielder','runner','catcher'})
        for kind,entries in m['kinds'].items():
            self.assertEqual(set(entries),set(MANIFEST['directionOrder']))
            for sh in entries.values():
                actions={f['action'] for f in sh['frames']}
                required={'ready','runA','runB'} if kind=='runner' else {'ready','catch','gather','windup','release'}
                self.assertTrue(required<=actions)
                self.assertGreater(sh['referenceHeight'],100)
                for f in sh['frames']:
                    self.assertEqual(blob_issues(str((ART/f['file']).relative_to(ROOT)),(ART/f['file']).read_bytes()),[])
                    x,y,w,h=f['rect']
                    for row,left,width in f['clipRows']:
                        self.assertTrue(0<=row<h and 0<=left<w and 0<width<=w-left)
                    for anchor in ['hand','glove']:
                        self.assertTrue(0<=f[anchor][0]<=w and 0<=f[anchor][1]<=h)
                    self.assertIsInstance(f['sourceLeft'],bool)
                    if kind=='runner':self.assertTrue(f['file'].startswith('runner-'))

class ThrowPreviewTests(unittest.TestCase):
    def test_release_flight_arrival_catch_and_loop_for_all_targets(self):
        source=(ROOT/'scripts/preview_field_sprites.html').read_text()
        timeline=source[source.index('function throwSequence('):source.index('function anchor(')]
        assertions = """
const assert=require('node:assert/strict');
for(const key of ['first','second','third']){
 const before=throwSequence(3.899,key),release=throwSequence(3.9,key);
 assert.equal(before.ballVisible,false); assert.equal(before.caught,false);
 assert.equal(release.phase,6); assert.equal(release.ballVisible,true); assert.equal(release.progress,0);
 const arrival=release.arrival;
 const flying=throwSequence(arrival-.001,key),caught=throwSequence(arrival+.001,key);
 assert.equal(flying.ballVisible,true); assert.equal(flying.caught,false); assert.ok(flying.progress<1);
 assert.equal(caught.ballVisible,false); assert.equal(caught.caught,true); assert.equal(caught.receiverPhase,3);
 assert.equal(throwSequence(arrival+.81,key).receiverPhase,4);
 assert.equal(throwSequence(7.8,key).caught,false);
 assert.equal(throwSequence(7.8,key).ballVisible,false);
 assert.ok(arrival>4.7 && arrival<5.3);
}
assert.equal(throwSequence(4,'first').target.throwFacing,'e');
assert.equal(throwSequence(4,'second').target.throwFacing,'ne');
assert.equal(throwSequence(4,'third').target.throwFacing,'w');
"""
        subprocess.run(['node','-e',timeline+assertions],check=True,capture_output=True,text=True)

if __name__ == '__main__':
    unittest.main()
