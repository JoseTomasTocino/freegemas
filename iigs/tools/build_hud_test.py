"""Native LCD pixel-test fixture: production renderers, deterministic value mailbox."""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]; MERLIN=ROOT/'iigs/merlin32'; STAGE=MERLIN/'build/hud-test'
STUB='''
* Test-only mailbox. Production drawScore/drawTime are unchanged; omit the
* software pointer so it cannot cover the pixels being measured.
hudTestPoll lda dHudTestReady
         beq htDone
         cmp #1
         beq htStart
         cmp #3
         beq htSwap
         cmp #4
         beq htOver
         cmp #5
         beq htTitle
         lda dHudTestScore
         sta dScore
         lda dHudTestTime
         sta dTimeLeft
         jsr drawScore
         jsr drawTime
         stz dHudTestReady
htDone   rts
htStart  stz dMode
         jsr startGame
         stz dClockActive
         stz dHudTestReady
         rts
htSwap   lda dCursor
         jsr drawCellIndex
         jsr findHint
         lda dHintA
         sta dSwapA
         lda dHintB
         sta dSwapB
         jsr animSwap
         jsr swapCells
         jsr scanBoard
         jsr resolveBoard
         lda #$FFFF
         sta dSelCell
         lda dSwapB
         sta dCursor
         jsr setFrameCell
         jsr frameWhite
         jsr drawFrame
         stz dHudTestReady
         rts
htTitle  stz dState
         jsr showTitleScreen
         stz dHudTestReady
         rts
htOver   stz dTimeLeft
         jsr drawTime
         jsr gameOver
         stz dHudTestReady
         rts
dHudTestReady dw 0
dHudTestScore dw 0
dHudTestTime dw 120
'''


def main():
    STAGE.mkdir(parents=True,exist_ok=True)
    text=(MERLIN/'src/main.s').read_text(encoding='utf-8')
    text=text.replace('../build/FREEGEM.S16','../build/hud-test/FREEGEM.S16')
    text=text.replace('gameExit jsr ptrStep','gameExit jsr hudTestPoll\n         jsr musStep\n         jsr vsyncPoll\n         brl gameExit')
    text=re.sub(r'^(\s+adrl\s+dEmBank\s*)$',r'\1\n         adrl dHudTestReady\n         adrl dHudTestScore\n         adrl dHudTestTime',text,flags=re.M)
    text=re.sub(r'^\s+END\s*$',STUB+'\n         END\n',text,flags=re.M)
    with tempfile.NamedTemporaryFile(dir=MERLIN/'src',prefix='hud_test_',suffix='.s',delete=False) as file: path=Path(file.name)
    try:
        path.write_text(text,encoding='utf-8',newline='\n')
        result=subprocess.run(['C:/dev/Merlin32.exe','macros',str(path)],cwd=MERLIN,capture_output=True,text=True)
        (STAGE/'assembly.log').write_text(result.stdout+result.stderr,encoding='utf-8')
        if result.returncode or '[Error]' in result.stdout+result.stderr: raise RuntimeError('HUD fixture assembly failed')
    finally: path.unlink()
    for pattern in ('*.RAW','*.PCM','*.DAT'):
        for file in (MERLIN/'build').glob(pattern): shutil.copyfile(file,STAGE/file.name)
    subprocess.run([sys.executable,ROOT/'iigs/tools/pack_disk.py','--build',STAGE,'--image',MERLIN/'build/hudtest.2mg'],cwd=MERLIN,check=True)


if __name__=='__main__': main()
