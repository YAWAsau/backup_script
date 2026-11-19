import importlib.util,json,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('release',Path(__file__).resolve().parents[1]/'release.py')
release=importlib.util.module_from_spec(spec);spec.loader.exec_module(release)

class ReleaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.patch=patch.object(release,'ROOT',self.root);self.patch.start()
        files={'tools/tools.sh':'new','versions.properties':'build=v2\n','source-package.json':json.dumps({'files':['tools/tools.sh','versions.properties','source-package.json']}),'webview/embedded/metadata.json':json.dumps({'version':2})}
        for n in release.ARTIFACTS:files.setdefault(n,'artifact')
        for n,v in files.items():
            p=self.root/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(v)
        self.hashes={n:release.digest((self.root/n).read_bytes()) for n in release.inventory()}
        self.logs=self.root/'logs';self.logs.mkdir();(self.logs/'verified-hashes.json').write_text(json.dumps(self.hashes))
        baseline=dict(self.hashes);baseline['tools/tools.sh']='old';self.baseline=self.root/'baseline.json';self.baseline.write_text(json.dumps(baseline))
        self.review=self.root/'review.json';self.review.write_text(json.dumps({'result':'APPROVED','_reviewed_hashes':self.hashes}))
        self.validation=self.root/'validation.md';self.validation.write_text('verified')
        self.args=SimpleNamespace(logs=self.logs,baseline=self.baseline,review=[self.review],validation=self.validation,output=self.root/'out',base_version='v1')
    def tearDown(self):self.patch.stop();self.tmp.cleanup()
    def test_verified_delta_and_no_overwrite(self):
        release.package(self.args)
        self.assertEqual(len(list(self.args.output.glob('*.zip'))),2)
        with self.assertRaises(FileExistsError):release.package(self.args)
    def test_changed_sources_invalidate_build(self):
        (self.root/'tools/tools.sh').write_text('later edit')
        with self.assertRaisesRegex(ValueError,'verified build'):release.package(self.args)
    def test_review_must_match_snapshot(self):
        self.review.write_text(json.dumps({'result':'APPROVED','_reviewed_hashes':{}}))
        with self.assertRaisesRegex(ValueError,'source snapshot'):release.package(self.args)
    def test_failed_review_cannot_ship(self):
        self.review.write_text(json.dumps({'result':'NOT APPROVED','_reviewed_hashes':self.hashes}))
        with self.assertRaisesRegex(ValueError,'APPROVED'):release.package(self.args)
    def test_build_delegates_generation_and_license_import_to_root(self):
        args=SimpleNamespace(logs=self.logs,java_home=self.root/'java',signing_dir=self.root/'signing',license_metadata=[self.root/'ui.json',self.root/'dex.json'])
        with patch.object(release,'run') as run,patch.object(release,'verify') as verify:
            release.build(args)
        run.assert_called_once();verify.assert_called_once_with(args)
        command=run.call_args.args[0]
        self.assertIn(str(self.root/'build.ps1'),command)
        self.assertEqual(command[command.index('-WebviewLicenseMetadata')+1],str(args.license_metadata[0].resolve()))
        self.assertEqual(command[command.index('-DexLicenseMetadata')+1],str(args.license_metadata[1].resolve()))
    def test_crc_error_in_last_member_rejects_package(self):
        real_zip=release.zipfile.ZipFile
        def corrupt_last_crc(path,mode='r',*args,**kwargs):
            archive=real_zip(path,mode,*args,**kwargs)
            if mode=='r':archive.infolist()[-1].CRC ^= 1
            return archive
        with patch.object(release.zipfile,'ZipFile',side_effect=corrupt_last_crc):
            with self.assertRaisesRegex(ValueError,'Package verification failed'):release.package(self.args)
    def test_unexpected_member_rejects_package(self):
        real_zip=release.zipfile.ZipFile
        def add_member(path,mode='r',*args,**kwargs):
            if mode=='r':
                with real_zip(path,'a') as archive:archive.writestr('unexpected.txt','unexpected')
            return real_zip(path,mode,*args,**kwargs)
        with patch.object(release.zipfile,'ZipFile',side_effect=add_member):
            with self.assertRaisesRegex(ValueError,'Package verification failed'):release.package(self.args)
if __name__=='__main__':unittest.main()
