# iigs/tools/emu — GSSquared 桌面版自動化

給「換一台電腦接手」用的最小可跑組合。全部是 PowerShell 5.1 + Python 3 + .NET，
不需要編譯、不需要管理員權限。上層的環境清單與待辦順序看 [`iigs/AGENTS.md`](../../AGENTS.md)。

## 檔案

| 檔案 | 用途 |
| --- | --- |
| `gs2cli.cs` | C# P/Invoke 的 AF_UNIX client（Windows 的 CPython 沒有 `socket.AF_UNIX`，所以不能用官方 python client） |
| `fgemu.ps1` | 可 dot-source 的函式庫：啟動/停止模擬器、Pause、讀記憶體、按鍵、抓 SHR 畫面 |
| `fgcheck.ps1` | 端到端 smoke test：開機 → Title → Time Trial → 交換一組 gem → ESC → 標題，並錄音 |
| `audio_report.py` | 分析 SDL disk 錄音（raw S16LE）：peak、clipping、每 0.1 s 的 rms 與靜音窗 |
| `render_shot.py` | 把 `$012000` 的 32,000 B SHR framebuffer + palette 畫成 PNG（不需人手截圖） |

## 用法

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force   # 這台機器是 Restricted
cd C:\dev\freegemas
. .\iigs\tools\emu\fgemu.ps1          # 只載入函式庫
.\iigs\tools\emu\fgcheck.ps1          # 完整 smoke test（約 40 s，會覆蓋 build/freegemas.2mg 的掛載）
```

`fgcheck.ps1` 會印出五個時間點的 `dbgTab` 快照，正常長這樣（`nv` 是 `$01C029`，`ms` 是 `$019CFF`）：

```
up:    ms=7  nv=E1 state=0 score=0 ... mus=1/1/3/0  tot=4096
idle:  ms=7  nv=E1 state=0 ...
game:  ms=8  nv=E1 state=1 ...            <- Space 進 Time Trial
swap:  ms=8  nv=E1 state=1 snd=1/4/0 ...  <- 一組交換 + 音效 4 個暫存器寫入
title: ms=51 nv=E1 state=0 ...            <- ESC 回 Title
```

## 環境變數（都有預設值，換機器才需要改）

| 變數 | 預設 | 說明 |
| --- | --- | --- |
| `FG_GS2` | `C:\dev\emu\gssquared\GSSquared.exe` | 模擬器執行檔 |
| `FG_GS2CFG` | `C:\Users\USER\Documents\GSSquared\IIgs.gs2` | 機器設定（slot 7 = SCSI） |
| `FG_IMG` | `C:\dev\freegemas\iigs\merlin32\build\freegemas.2mg` | 要掛載的磁碟 |
| `FG_WORK` | `%TEMP%\fgemu` | socket、錄音、截圖的工作目錄 |
| `FG_SOCK` | `gs2-auto.sock` | debug socket（**必須是相對檔名**） |
| `FG_PYTHON` | `python` | 執行 `audio_report.py`／`render_shot.py` 的直譯器 |

## 手動操作（不跑 `fgcheck.ps1` 時）

```powershell
. .\iigs\tools\emu\fgemu.ps1
FG-Launch                       # 起模擬器（會自動 retry 10061）
FG-WaitUp                       # 輪詢到 ms>=7 且 nv=E1，回傳 $true
FG-Table                        # 找 dbgTab，印出位址
FG-Snap                         # Pause→讀 44 個變數→Continue，印一行摘要
FG-Key 44                       # Space（SDL scancode：W=26 A=4 S=22 D=7 SPACE=44 ESC=41 H=11 R=21）
FG-Write16 0x1C 120             # 直接把 dMouseX 之類的變數寫死
FG-Shot "$env:TEMP\fgemu\a.png"  # 抓 SHR 畫面轉 PNG
FG-Quit                         # 關掉模擬器（等 process 真的結束）
```

注意事項：

1. **一個模擬器 process 只能連一次 socket**：重跑前先 `FG-Quit`，否則會接到舊的 process。
2. 每個 `Pause` 都要配 `Continue`；忘了會讓模擬器停在 GSBug 外觀（讀值全凍結）。
3. 錄音靠 `SDL_AUDIODRIVER=disk`；`fgcheck.ps1` 已設好 `SDL_AUDIO_DISK_OUTPUT_FILE`。這台機器
   沒有實體音效輸出，聽感要在有喇叭的機器上驗。
4. `dbgTab` 的 entry 是 24-bit `adrl`，一定要 deref（`FG-Word`／`FG-Byte` 已經處理）。
5. 桌面版 debug 協定**不能注入滑鼠**；滑鼠手感只能在 web GSSquared（按 F1）或實機驗。
