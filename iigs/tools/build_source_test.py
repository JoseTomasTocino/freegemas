"""Build a separate playable original-source gloss test, preserving classic disk.

Run from anywhere: python iigs/tools/build_source_test.py
Requires the ordinary build's PCM/RAW files and GS/OS template already present.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
MERLIN=ROOT/'iigs/merlin32'
STAGE=MERLIN/'build/source-art'
GENERATED=STAGE/'generated'
IMAGE=MERLIN/'build/freegemas-source.2mg'


def run(arguments, **kwargs):
    subprocess.run([str(a) for a in arguments],check=True,**kwargs)


def main():
    STAGE.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,IIGS_ART_STYLE='source',IIGS_ASSET_DIR=str(GENERATED))
    run([sys.executable,ROOT/'iigs/tools/build_iigs_assets.py'],env=env)
    run([sys.executable,ROOT/'iigs/tools/check_gem_blitters.py'],env=env)
    source=(MERLIN/'src/main.s').read_text(encoding='utf-8')
    replacements={
        '../build/FREEGEM.S16':'../build/source-art/FREEGEM.S16',
        'put ../generated/gem_data.s':'put ../build/source-art/generated/gem_data.s',
        'esFill   lda #$FF':'esFill   lda #$00',
        'etFill   lda #$FF':'etFill   lda #$00',
        'lda #$00BB':'lda #$00EE',
        'lda #$00B0':'lda #$00E0',
        'lda #$000B':'lda #$000E',
        'lda #$00DD':'lda #$0022',
        'lda #$00D0':'lda #$0020',
        'lda #$000D':'lda #$0002',
    }
    for before,after in replacements.items():
        assert source.count(before)==1,before
        source=source.replace(before,after)
    # Keep the temporary source beside main.s so relative PUT paths resolve
    # identically. Remove only the temporary file created by this process.
    with tempfile.NamedTemporaryFile(dir=MERLIN/'src',prefix='source_test_',suffix='.s',delete=False) as file:
        variant=Path(file.name)
    try:
        variant.write_text(source,encoding='utf-8',newline='\n')
        result=subprocess.run([os.environ.get('MERLIN32','C:/dev/Merlin32.exe'),'macros',str(variant)],
                              cwd=MERLIN,capture_output=True,text=True)
        (STAGE/'assembly.log').write_text(result.stdout+result.stderr,encoding='utf-8')
        if result.returncode or '[Error]' in result.stdout+result.stderr:
            raise RuntimeError('Merlin32 failed; see '+str(STAGE/'assembly.log'))
    finally:
        variant.unlink()
    for pattern in ('*.PCM','*.DAT'):
        for file in (MERLIN/'build').glob(pattern): shutil.copyfile(file,STAGE/file.name)
    files={'scene_tt.bin':'SCENE4.RAW','scene_end.bin':'SCENE4E.RAW',
           'title_scene.bin':'TITLE.RAW','howto_scene.bin':'HOWTO.RAW','gem_rasters.bin':'GEMS.RAW'}
    files.update({f'gem_fast{i}.bin':f'GEMS{i}.RAW' for i in range(3)})
    for asset,name in files.items(): shutil.copyfile(GENERATED/asset,STAGE/name)
    run([sys.executable,ROOT/'iigs/tools/pack_disk.py','--build',STAGE,'--image',IMAGE],cwd=MERLIN)
    print('Playable source-art test:',IMAGE)
    print('Classic image preserved:',MERLIN/'build/freegemas.2mg')


if __name__=='__main__':
    main()
