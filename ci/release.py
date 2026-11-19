"""Local release entry point: snapshot, ordered build, and reviewed delta packaging."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,sys,zipfile
ROOT=Path(__file__).resolve().parent.parent
RUNTIME={'VERSION','versions.properties','CHANGELOG.md','start.sh','webui.sh'}
ARTIFACTS={'tools/classes.dex','tools/speednative','webview/embedded/speedbackup-webview.apk','webview/embedded/metadata.json'}
def digest(data):return hashlib.sha256(data).hexdigest()
def inventory():
    names=set(json.loads((ROOT/'source-package.json').read_text(encoding='utf8'))['files'])|ARTIFACTS
    for name in names:
        if name.startswith(('/', '\\')) or '..' in Path(name).parts:raise ValueError('Unsafe inventory path')
    return names
def snapshot(target):
    if target.exists():raise ValueError('Baseline already exists')
    hashes={n:digest((ROOT/n).read_bytes()) for n in sorted(inventory())}
    target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf8')
def run(command,log):
    print('Running',log.name,flush=True)
    with log.open('w',encoding='utf8') as out:subprocess.run(command,cwd=ROOT,stdout=out,stderr=subprocess.STDOUT,check=True)
def build(args):
    args.logs.mkdir(parents=True,exist_ok=True)
    command=['pwsh','-NoProfile','-File',str(ROOT/'build.ps1'),'-JavaHome',str(args.java_home.resolve()),'-SigningDir',str(args.signing_dir.resolve()),'-Offline']
    if args.license_metadata:
        command+=['-WebviewLicenseMetadata',str(args.license_metadata[0].resolve()),'-DexLicenseMetadata',str(args.license_metadata[1].resolve())]
    run(command,args.logs/'components-build.log')
    verify(args)
def verify(args):
    args.logs.mkdir(parents=True,exist_ok=True)
    run([sys.executable,'-X','utf8',str(ROOT/'ci/check_repository.py'),'check'],args.logs/'repository-build.log')
    # Packaging rejects stale build evidence even if an old log says PASS.
    (args.logs/'verified-hashes.json').write_text(json.dumps({n:digest((ROOT/n).read_bytes()) for n in sorted(inventory())}),encoding='utf8')
def review(args):
    before={n:digest((ROOT/n).read_bytes()) for n in inventory()}
    if args.output.exists():raise ValueError('Review output already exists')
    command=[str(args.claude_exe.resolve()),'-p','--model','sonnet','--effort','medium','--safe-mode','--tools','Read,Grep,Glob','--allowedTools','Read,Grep,Glob','--permission-mode','dontAsk','--output-format','json','--no-session-persistence']
    result=subprocess.run(command,input=args.prompt.read_text(encoding='utf8'),text=True,encoding='utf8',capture_output=True,cwd=ROOT,check=True,env={**os.environ,'CLAUDE_CODE_MAX_OUTPUT_TOKENS':'6000'})
    data=json.loads(result.stdout)
    after={n:digest((ROOT/n).read_bytes()) for n in inventory()}
    if after!=before:raise ValueError('Sources changed during review')
    data['_reviewed_hashes']=before
    args.output.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(data.get('result',''),flush=True)
def package(args):
    verified=json.loads((args.logs/'verified-hashes.json').read_text(encoding='utf8'))
    current={n:digest((ROOT/n).read_bytes()) for n in inventory()}
    if current!=verified:raise ValueError('Sources/artifacts changed since verified build')
    baseline=json.loads(args.baseline.read_text(encoding='utf8'))
    if set(baseline)-set(current):raise ValueError('Deleted files require a full release or explicit migration')
    reviews=[]
    for path in args.review:
        review=json.loads(path.read_text(encoding='utf8'))
        if review.get('is_error') or not re.match(r'^\s*(?:\*\*)?APPROVED\b',review.get('result','')) or review.get('permission_denials'):
            raise ValueError('Review must be successful and explicitly APPROVED')
        if review.get('_reviewed_hashes')!=current:raise ValueError('Review belongs to another source snapshot')
        reviews.append({'result':review['result'],'session_id':review.get('session_id')})
    changed={n:(ROOT/n).read_bytes() for n,h in current.items() if baseline.get(n)!=h}
    if not changed:raise ValueError('No changed files')
    versions=dict(line.split('=',1) for line in (ROOT/'versions.properties').read_text().splitlines() if line and not line.startswith('#'))
    ui=json.loads((ROOT/'webview/embedded/metadata.json').read_text())['version']
    args.output.mkdir(parents=True,exist_ok=True)
    for suffix,files in [('FROM_'+args.base_version+'_CHANGED_ONLY',{n:b for n,b in changed.items() if n.startswith('tools/') or n in RUNTIME}),('PROJECT_CHANGED_ONLY',changed)]:
        payload=dict(files);payload['UPDATE_VALIDATION.md']=args.validation.read_bytes()
        payload['UPDATE_CLAUDE_REVIEW.json']=json.dumps(reviews,ensure_ascii=False,indent=2).encode()
        payload['UPDATE_SHA256SUMS.txt']=''.join(digest(b)+'  '+n+'\n' for n,b in sorted(payload.items())).encode()
        target=args.output/f'SpeedBackup_{versions["build"]}_UI1.{ui}_{suffix}.zip'
        with zipfile.ZipFile(target,'x',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
            for n,b in sorted(payload.items()):archive.writestr(n,b)
        with zipfile.ZipFile(target) as archive:
            # read() validates each member's CRC while comparing the exact bytes.
            # Check the inventory too, so an unexpected/duplicate member cannot escape validation.
            try:
                if sorted(archive.namelist())!=sorted(payload) or any(archive.read(n)!=b for n,b in payload.items()):raise ValueError('Package verification failed')
            except zipfile.BadZipFile as error:
                raise ValueError('Package verification failed') from error
        print(target,digest(target.read_bytes()),flush=True)
def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='command',required=True)
    p=sub.add_parser('snapshot');p.add_argument('--output',type=Path,required=True)
    p=sub.add_parser('build');p.add_argument('--logs',type=Path,required=True);p.add_argument('--java-home',type=Path,required=True);p.add_argument('--signing-dir',type=Path,required=True);p.add_argument('--license-metadata',type=Path,nargs=2)
    p=sub.add_parser('review');p.add_argument('--claude-exe',type=Path,required=True);p.add_argument('--prompt',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p=sub.add_parser('verify');p.add_argument('--logs',type=Path,required=True)
    p=sub.add_parser('package');p.add_argument('--logs',type=Path,required=True);p.add_argument('--baseline',type=Path,required=True);p.add_argument('--base-version',required=True);p.add_argument('--review',type=Path,action='append',required=True);p.add_argument('--validation',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.command=='snapshot':snapshot(args.output)
    elif args.command=='build':build(args)
    elif args.command=='review':review(args)
    elif args.command=='verify':verify(args)
    else:package(args)
if __name__=='__main__':main()
