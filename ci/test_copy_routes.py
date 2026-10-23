import json
import tempfile
import unittest
from pathlib import Path
from check_copy_routes import check, scan


class CopyRoutesTest(unittest.TestCase):
    def test_changes_cannot_silently_expand_copy_routes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tools').mkdir()
            (root / 'ci').mkdir()
            script = root / 'tools/test.sh'
            original = 'old_copy() {\n  cp "$a" "$b"\n}\n'
            script.write_text(original)
            rows = [dict(file=f, context=c, line=l, count=n,
                         category='private-copy', reason='Private fixture working directory only')
                    for (f, c, l), n in scan(root).items()]
            inventory = root / 'ci/copy_routes.json'
            inventory.write_text(json.dumps(dict(schema=1, routes=rows)))
            check(root)
            for changed in [original.replace('"$b"', '"$public"'),
                            original.replace('old_copy', 'other_copy'),
                            original.replace('\n}', '\n  cp "$a" "$b"\n}'),
                            original + '\n/system/bin/cp x y\n',
                            original + '\nbusybox cp x y\n']:
                with self.subTest(changed=changed):
                    script.write_text(changed)
                    with self.assertRaises(ValueError):
                        check(root)
            script.write_text(original)
            new = root / 'tools/new.sh'
            new.write_text('cp x y\n')
            with self.assertRaises(ValueError):
                check(root)
            new.unlink()
            rows[0]['reason'] = ''
            inventory.write_text(json.dumps(dict(schema=1, routes=rows)))
            with self.assertRaises(ValueError):
                check(root)


if __name__ == '__main__':
    unittest.main()
