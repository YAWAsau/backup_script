"""Regression vectors from official OpenCC with the pinned profile dictionaries."""
from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
JAVA = ROOT / 'dex/app/src/main/java/com/xayah/dex'


def main():
    vectors = json.loads((ROOT / 'ci/tests/opencc-profiles.json').read_text(encoding='utf-8'))
    with tempfile.TemporaryDirectory() as tmp:
        harness = Path(tmp) / 'ProfileTest.java'
        harness.write_text('''package com.xayah.dex;
import java.io.*; import java.nio.charset.StandardCharsets;
public class ProfileTest {
 public static void main(String[] args) throws Exception {
  BufferedReader in=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8));
  BufferedWriter out=new BufferedWriter(new OutputStreamWriter(System.out,StandardCharsets.UTF_8));
  String line;
  while((line=in.readLine())!=null){out.write(OpenCcPhrases.convert(line,args[0].equals("s2twp")));out.write(10);}
  out.flush();
 }
}''', encoding='utf-8')
        subprocess.run(['javac', '-encoding', 'UTF-8', '-d', tmp,
                        *[str(JAVA / n) for n in ['CCHelper.java', 'OpenCcPhrases.java', 'OpenCcPhraseData.java', 'CCUtil.java', 'ScriptRoundTrip.java']], str(harness)], check=True)
        for mode in ['s2twp', 'tw2sp']:
            inputs = [v['input'] for v in vectors['vectors']]
            expected = [v[mode] for v in vectors['vectors']]
            result = subprocess.run(['java', '-cp', tmp, 'com.xayah.dex.ProfileTest', mode],
                                    input='\n'.join(inputs)+'\n', encoding='utf-8', capture_output=True, check=True)
            actual = result.stdout.splitlines()
            assert len(actual) == len(expected)
            for text, a, e in zip(inputs, actual, expected):
                assert a == e, (mode, text, a, e)
            print(mode, len(inputs), 'official-reference vectors passed')
        result = subprocess.run(['java', '-cp', tmp, 'com.xayah.dex.CCUtil', 'selftest'], capture_output=True, check=True)
        assert b'CCUTIL_SELFTEST_OK' in result.stdout
        print('Shared product glossary selftest passed')


if __name__ == '__main__':
    main()
