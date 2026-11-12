"""Generate exact asset data-block totals for the native loading meter."""
import sys
from pathlib import Path
assets=Path(__file__).resolve().parents[2]/'generated'
common=['game_gems_32.idx','select.pcm','fall.pcm','match1.pcm','match2.pcm','match3.pcm']
# GEM.PAT is generated from the existing gem sprite-pattern asset.
base=sum((assets.joinpath(name).stat().st_size+511)//512 for name in common)
out=Path(sys.argv[1])
data='#pragma once\n'+''.join(f'#define LOADING_{mode}_BLOCKS {base+(assets.joinpath(scene).stat().st_size+511)//512}u\n' for mode,scene in [('TIMED','game_scene.rle'),('ENDLESS','game_endless.rle')])
if not out.exists() or out.read_text()!=data:out.write_text(data)
