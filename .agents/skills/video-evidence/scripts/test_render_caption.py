"""Contract checks; set VIDEO_EVIDENCE_FONT to a Noto Sans CJK Japanese face."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image


SCRIPT = Path(__file__).with_name("render-caption.py")
FONT = os.environ["VIDEO_EVIDENCE_FONT"]


class CaptionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "注釈 '100%'.txt"
        self.output = self.root / "結果 '100%'.png"

    def run_caption(self, text="指を左へ：ページ切替\n確認：1 → 2", width=1140, height=340, extra=()):
        self.source.write_text(text, encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(width), str(height), str(self.source),
             str(self.output), "--font", FONT, *extra], capture_output=True, text=True, cwd=self.root
        )
        self.assertEqual(self.source.read_text(encoding="utf-8"), text)
        self.assertEqual(result.stdout, "")
        return result

    def test_japanese_and_literal_metacharacters(self):
        result = self.run_caption("① 指を左へ 100% 'quoted'\n$(touch SENTINEL) `echo` : ; \\ → 2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "SENTINEL").exists())
        with Image.open(self.output) as image:
            self.assertEqual(image.size, (1140, 340))
            self.assertEqual(image.mode, "RGB")
            self.assertGreater(sum(min(pixel) > 230 for pixel in image.getdata()), 500)

    def test_automatic_wrap_and_combining_mark(self):
        result = self.run_caption("日本語の長い文が画像幅に合わせて折り返される。か\u3099", 320, 600)
        self.assertEqual(result.returncode, 0, result.stderr)
        with Image.open(self.output) as image:
            white_rows = [y for y in range(image.height)
                          if any(min(image.getpixel((x, y))) > 230 for x in range(image.width))]
            self.assertGreater(max(white_rows) - min(white_rows), 32)
            self.assertTrue(all(image.getpixel((0, y)) == (14, 20, 33) for y in range(image.height)))

    def test_existing_output_is_preserved(self):
        self.output.write_bytes(b"existing evidence")
        self.assertNotEqual(self.run_caption().returncode, 0)
        self.assertEqual(self.output.read_bytes(), b"existing evidence")

    def test_dangling_symlink_is_preserved(self):
        target = self.root / "absent.png"
        self.output.symlink_to(target)
        self.assertNotEqual(self.run_caption().returncode, 0)
        self.assertFalse(target.exists())

    def test_overflow_produces_no_output(self):
        result = self.run_caption("画面を確認\n" * 50)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("overflows", result.stderr)
        self.assertFalse(self.output.exists())

    def test_missing_glyph_produces_no_output(self):
        result = self.run_caption("結果\U0001F984")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("U+1F984", result.stderr)
        self.assertFalse(self.output.exists())

    def test_invalid_inputs_produce_no_output(self):
        cases = [{"text": "  \n"}, {"text": "hidden\x00value"}, {"width": 319},
                 {"height": 199}, {"extra": ("--font-size", "0")},
                 {"extra": ("--font-size", "161")}, {"extra": ("--font-index", "-1")},
                 {"extra": ("--font", str(self.root / "absent.ttf"))}]
        for case in cases:
            with self.subTest(case=case):
                self.assertNotEqual(self.run_caption(**case).returncode, 0)
                self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
