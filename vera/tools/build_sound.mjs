import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
// Original recordings, signed 8-bit mono at VERA PCM rate 21 (8010.86 Hz).
// Effects are limited to 0.29 full scale so the music (0.70) and an effect
// can be added in software without clipping: |0.70| + |0.29| < 1.0.
const vera=path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const rate=Math.round(21*25000000/512/128);
const limit=0.29;
for(const name of ['select','fall','match1','match2','match3']) {
  const result=spawnSync('ffmpeg',['-v','error','-i',path.join(vera,'../media',name+'.ogg'),
    '-af',`aresample=${rate}:resampler=swr:filter_size=64:phase_shift=10,volume=0.35,alimiter=limit=${limit}:level=0:attack=1:release=20`,
    '-ac','1','-f','s8','pipe:1'],{maxBuffer:2**24});
  if(result.status!==0)throw new Error(result.stderr.toString());
  let outData = result.stdout;
  if(name.startsWith('match') && outData.length > Math.round(rate*0.300)) {
    outData = outData.subarray(0, Math.round(rate*0.300));
  }
  fs.writeFileSync(path.join(vera,'generated',name+'.pcm'), outData);
  const wav=spawnSync('ffmpeg',['-v','error','-y','-f','s8','-ar',String(rate),
    '-ac','1','-i','pipe:0',path.join(vera,'llvm/build',name+'_pcm.wav')],{input: outData});
  if(wav.status!==0)throw new Error(wav.stderr.toString());
  console.log(`${name}: ${outData.length} bytes, signed 8-bit, VERA rate 21 (${rate} Hz)`);
}
