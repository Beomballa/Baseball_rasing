"""Source atlas contract checks; never reads or writes player saves."""
import json
from pathlib import Path
import struct
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

if __name__ == '__main__':
    unittest.main()
