#!/usr/bin/env python3
"""Create an explicit publication tree. Private analysis and unknown samples stay local."""
import argparse, pathlib, shutil
root=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('destination',type=pathlib.Path);args=parser.parse_args()
dest=args.destination.resolve()
if dest.exists() and any(dest.iterdir()):raise SystemExit('Destination must be empty')
if dest==root or root in dest.parents:raise SystemExit('Publication tree must be outside the source directory')
dest.mkdir(parents=True,exist_ok=True)
blocked_suffixes={'.p12','.pfx','.cer','.key','.mobileprovision','.pkg','.zip','.tgz','.hwp','.ttf','.otf','.ttc'}
# Generated, permitted examples are JSON, not copied office sample documents.
def ignored(directory,names):
 result=[]
 for name in names:
  p=pathlib.Path(directory)/name
  if name in {'.DS_Store','__pycache__','node_modules','.git','native'} or p.suffix.lower() in blocked_suffixes or name.startswith('.env'):result.append(name)
 return result
for rel in ['Sources','Resources','Tools','packaging','site','.github']:
 if (root/rel).exists():shutil.copytree(root/rel,dest/rel,ignore=ignored,dirs_exist_ok=True)
for rel in ['Tests/AgentCLI','Tests/Distribution','Tests/StartWindow','Tests/Editing','Tests/Interaction','Tests/PasteboardGuard','docs/cli','docs/legal']:
 if (root/rel).exists():shutil.copytree(root/rel,dest/rel,ignore=ignored,dirs_exist_ok=True)
for rel in ['Tests/formulas.tsv','Tests/run-editing.sh','Tests/run-interaction.sh','README.md','LICENSE','NOTICE','PROVENANCE.md','build-app.sh','build-cli.sh','build-pkg.sh','dev-build.sh','install-cli.sh','.gitignore']:
 if (root/rel).is_file():
  (dest/rel).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/rel,dest/rel)
print(dest)
