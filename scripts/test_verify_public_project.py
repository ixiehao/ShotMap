"""Language alternates and Markdown reading links have different semantics."""
import contextlib
import io
import re
import unittest
from unittest.mock import patch
import verify_public_project as verify

class PublicLanguageLinks(unittest.TestCase):
    def test_markdown_alternate_does_not_count_as_an_extra_language(self):
        verify.verify_page(verify.ROOT/'website/index.html', 'en')

    def test_a_missing_language_still_fails(self):
        path = verify.ROOT/'website/index.html'
        text = path.read_text()
        text, count = re.subn(r'    <link rel="alternate" hreflang="ja"[^>]*>\n', '', text)
        self.assertEqual(count, 1)
        error = io.StringIO()
        with patch.object(verify, 'require_text', return_value=text), contextlib.redirect_stderr(error):
            with self.assertRaises(SystemExit) as failed:
                verify.verify_page(path, 'en')
        self.assertEqual(failed.exception.code, 1)
        self.assertIn('incomplete hreflang', error.getvalue())

if __name__ == '__main__':
    unittest.main()
