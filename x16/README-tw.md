# Freegemas for Commander X16

[English](README.md) | 繁體中文

這是 Freegemas 的 Commander X16 移植版，使用
[LLVM-MOS SDK](https://github.com/llvm-mos/llvm-mos-sdk) 編譯成 65C02 原生
程式。畫面沿用 Apple //e VERA 版的素材與 `media/` 原始資產，但執行時使用
X16 的 VERA（`$9F20`）、KERNAL I/O 與鍵盤／搖桿 API。

程式分為常駐 `$2000` 的 loader，以及載入 `$3000` 的 intro、title、
How to Play、Options 與遊戲 overlay。畫面是 320x240、8bpp 的 VERA bitmap，
寶石與特效使用硬體 sprites。音樂是 **ZCM 串流**：8,011 Hz、單聲道、
signed 16-bit PCM，透過 KERNAL `MACPTR` 從 `hostfs/music.zcm` 讀取。五個短
音效是 signed 16-bit PCM，預載在 banked RAM，並與音樂混入同一個 VERA FIFO。

## 需求

- Windows PowerShell 7（`pwsh`）、Python 3 與 NumPy、LLVM-MOS SDK。
  請以 `-Sdk <llvm-mos-sdk>/bin` 指定 SDK，或將 `LLVM_MOS_SDK` 設為該目錄。
- `assets/music.zcm`（2,024,422 bytes，126.35 秒），已納入版控；一般建置
  只需將它複製到 `hostfs/`，不需要重新轉檔。
- `generated/`：`tools/build_assets.py` 使用的 palette、sprite、場景與 PCM
  音效輸入，已納入版控。
- **x16emu r49（Pyrite）或更新版本**。鍵盤使用 R49 的 `kbdbuf_get`
  extapi（A=18，`$FEAB`），舊 ROM 不保證可用。
- 512 KiB banked RAM：場景 chunk 使用 bank 30-39，音效 bank 24-28，HUD 快取
  bank 20；音樂不需要載入 banked RAM。

不需要 `ffmpeg`；音效 builder 使用 Python 的 `soundfile` 與 `soxr`。音樂的
重新產生方式見下文。

## 建置

在這個目錄執行：

```powershell
cd x16
.\build.ps1 -Sdk C:\path\to\llvm-mos-sdk\install\bin
```

或在 repo 根目錄執行：

```powershell
powershell -ExecutionPolicy Bypass -File .\x16\build.ps1
```

產物：

- `hostfs/`：可直接執行的 HostFS 目錄（程式、場景、PCM 音效、
  `music.zcm`）。
- `build/`：暫時性的 `.bin`、`.map` 與中介檔。

`build.ps1` 會先刪除並重建兩個輸出目錄，因此全新建置不會保留舊的
`hiscore.dat`。

## 執行

```powershell
x16emu.exe `
  -prg x16\hostfs\boot.prg `
  -run `
  -capture `
  -fsroot x16\hostfs `
  -scale 2
```

加上 `-capture`（或在視窗開啟後按 `Ctrl+M`）讓 x16emu 接收滑鼠；
遊戲會自己畫指標，因此宿主游標會隱藏。

要擷取聲音可加上 `-wav x16\out.wav`。HostFS 檔名為小寫且
區分大小寫。

## 瀏覽器版 web player

[`web/`](web/) 是獨立的瀏覽器版播放頁。它使用官方 x16-emulator
WebAssembly r49，並載入同一份產生的 `hostfs/`，因此瀏覽器裡跑的是真正的
X16 KERNAL 與 `boot.prg`。建置後會產生可放到任何靜態空間的 `dist/`：

```powershell
cd x16\web
.\build.ps1
python -m http.server 8123 --directory .\dist
```

開啟 <http://127.0.0.1:8123/>；加上 `?auto=1` 會自動開機。建置需求、
固定的模擬器 checksum、離線快取與「瀏覽器內高分只存活於本次頁面」的
說明見 [`web/README.md`](web/README.md)。

## 操作

- **Title**：方向鍵或滑鼠移動指標；Space、Enter 或滑鼠左鍵開啟項目。
- **How to Play**：任意鍵或滑鼠左鍵返回 Title。
- **Options**：方向鍵或滑鼠選擇；Space／左鍵切換 Music（ZCM/Off）、
  Sound（On/Off）或選擇 Back；Esc 返回 Title。
- **遊戲**：方向鍵或滑鼠移動游標；Space／左鍵選取寶石，再以相鄰方向或左鍵交換。
  畫面上的 Show hint、Reset game、Exit 也可直接用滑鼠點擊。`H` 顯示提示，
  `R` 重新開始，Esc 返回 Title。
- **Game Over**：`R` 重新開始；Esc 返回 Title 並儲存待寫入的高分。

X16 鍵盤搖桿對應的方向鍵與 A/B 也可操作（方向鍵、`X`/`Ctrl` 與
`Z`/`Alt` 分別對應 A/B）。目前只輪詢 joystick 0。

## Sprite 圖層與滑鼠游標

slot 0 屬於 KERNAL 滑鼠驅動，遊戲不使用。配置如下：寶石 **1-64**、手套
**65**、提示框 **66**、游標框 **67**、選取框 **68**、浮動數字 **69-88**、
粒子 **89-120**、選單指標 **127**。寶石用 VERA z-depth 2（layer 0 與
layer 1 之間），覆蓋層與手套用 z-depth 3（layer 1 前面）。同 z-depth 時
**attribute 位址較低**的 sprite 畫在前面，所以 slot 65 的手套會在 slot 67
游標框與 slot 68 選取框之上；舊版手套在 slot 126，才會被 slot 66 的框壓住。
slot 126 也太後面，提示框的右／下邊會被 VERA scanline sprite-clock 預算
截掉，因此提示框留在 slot 66。title 寶石同樣用 z-depth 2，讓 slot 127、
z-depth 3 的選單手套保持可見。選單手套使用 sprite palette offset 15 與
private entries 251/252（白、黑）；否則會繼承 title palette 的 index 15，
也就是暗紅色。

常數在 [effects.h](src/effects.h#L8)；寫入 VERA attribute 的程式在
[effects.c](src/effects.c#L36-L41) 與 [main.c](src/main.c#L331-L340)。

## 音樂與音訊路徑

- `media/music.ogg` 先解碼、downmix 成單聲道，使用 `soxr` VHQ 重取樣為
  **8,010.864 Hz**，乘上 `0.55`，再存成 ZCM 內的 signed 16-bit PCM。8-byte
  標頭是 `00 00 00 <24-bit sample count> 2F 15`：geometry `0x2F` 代表
  16-bit mono，VERA rate `21`。輸出的 `assets/music.zcm` 是 2,024,422 bytes，
  頭尾各 40 samples 的 fade 讓循環不會爆音。
- `music.c` 在啟動 I/O 完成後開啟 ZCM，用 `MACPTR` 讀取（跳過 8-byte
  標頭），所以 2 MB 音樂從不佔用 banked RAM。clock 暫停時先預填
  **2,048 bytes**（約 128 ms），之後依照**實際經過的 VSYNC 數**補資料，而
  不是每個迴圈固定補一個 frame。8,010.864 Hz 下一個 VSYNC 消耗
  **267.03 bytes**；feeder 用 VERA audio-low 旗標在 FIFO 空掉前補，
  每個 frame 最多做八次 510-byte catch-up。EOF 時先排空 pending 與 FIFO，
  再關閉串流並靜音。
- 五個音效由 `tools/build_effects.py` 從原始 OGG 重建：soxr VHQ 轉成
  8,010.864 Hz、mono、峰值正規化，存成 little-endian signed 16-bit PCM。
  每個音效各自預載到 bank 24-28 的 `$A000`，所以 4,806 bytes 的 match 音效
  不會跨過 `$BFFF` 邊界而截斷 MATCH3。`music.c` 的 `mix_effect16()` 在
  音樂 RAM buffer 裡做完整 16-bit 相加與 clip；`pcm_copy` 只寫完整的
  16-bit pair，沒送完的資料由 `music.c` 留到下一 frame。VERA 使用 16-bit
  mono、volume 10（`0x2A`）。
- 音效 stage 是 **`$1000` 的 512 bytes／256 samples**。一次 catch-up 最多
  要求 **510 bytes／255 samples**；舊的 320-byte（160-sample）stage 只混到
  該次要求的前段，其餘只剩音樂。舊程式另外會在 512-byte 載入後留下
  **1 sample** 的尾巴，下一次 255-sample run 只有那 1 sample 有音效，其餘
  又變成音樂。這兩個路徑都會讓 match 音效斷斷續續；現在 `sound_stage()`
  每次呼叫都重新載入一整段，修正了切碎感。
- X16 場景另外移除計時器面板的深藍色 `88:88` 殘影，並把 Show hint／
  Reset game／Exit 按鈕上那道硬的漸層橫線整平。計時器改用
  `media/fuentelcd.ttf` 產生的 12×18 LCD 字形，對齊到 x=75 的右緣；前景
  數字與 LED 高度一致，不會再留下比較大的黑色殘影。
- **目前找到的音訊爆音原因都已修正。** `pcm_read` 有兩個
  `beq pcm_read_done` 距離目標超過 127 bytes；組譯器把相對位移截成
  `B7`，所以每次讀取剛好消耗完剩餘 count 時，65C02 會**往回跳**到
  `$3142`，把 `FF AD 44` 當成 Rockwell `BBS7` 執行。這正是
  `Warning: encountered Rockwell instruction BBS at $00:3143` 的來源；
  它也會走進 `pcm_open_fail` 尾段，破壞讀取狀態。兩個分支已改成
  區域 `bne` 加 `jmp`，修正後的擷取不再出現這個警告。
  另外，`MACPTR` 的實際讀取數在 **X（低位）與 Y（高位）** 回傳，不是只有
  X；舊程式寫 `lda #0; sta pcm_read_hi`，把每次 267／510-byte 的讀取
  縮成 11／0 bytes，讓 16-bit 串流整體位移。現在 X、Y 都保留。
  `pcm_copy` 只寫完整 16-bit pair，未送完的尾巴由 `music.c` 保留；
  音效是 signed 16-bit PCM。先前的「相關性 1.0」說法是錯的，已移除。
- Music On/Off 是 Options 設定。即使 Music 關閉，串流仍會開啟但樣本清零，
  因此兩種模式共用同一套 16-bit 音效 mixer；Music Off 時只會聽到音效。
  按 `R` 只重設盤面與音效，**不重新開啟串流**（遊戲中重開 HostFS channel
  會讓後續讀取損壞）；Esc／Exit 會停止音樂並移除 VSYNC IRQ。
- 鍵盤使用 `kbdbuf_get`，因此音樂使用的 KERNAL channel 不會改寫鍵盤讀取。
  遊戲同時接受大寫與小寫的 `H`、`R`。

重新產生音樂與音效素材：

```powershell
python .\tools\build_music_zcm.py
python .\tools\build_effects.py
```

兩個 builder 都需要 Python 的 `soundfile`、`soxr` 與 NumPy。音樂 builder
覆寫 `assets/music.zcm`；音效 builder 覆寫 `hostfs/` 裡五個 16-bit
`*.pcm`。之後執行 `.\build.ps1` 重建 `hostfs/`；`build.ps1` 也會自動呼叫
兩個 builder。

## 高分與檔案

高分存在 `hostfs/hiscore.dat`：12 bytes 的 `FGH` version 1 標頭加上兩個
little-endian `uint32`。Game Over 後返回 Title，或從 Title 離開時寫入。
全新建置不會預設任何分數。

loader 以 HostFS 小寫檔名讀取所有素材，因此整個 `hostfs/` 目錄可直接
複製到其他 HostFS 根目錄。

## 驗證狀態

只在 **x16emu r49（Pyrite）**、Windows、以 WAV 與截圖驗證。**沒有實機
Commander X16**，也**沒有真人耳朵聽感測試**；下面對音訊的描述都是
envelope／peak／zero-run／頻譜量測，不是「聽起來如何」的主張。

- **滑鼠：** 使用 `-capture` 時，合成相對移動會推動遊戲指標（title
  截圖可證）；左鍵可啟動 Timetrial；遊戲中可在 cell 間移動游標。實際
  點擊一組有效相鄰寶石後，**分數由 0 變 15**，盤面消除並補位。這是
  x16emu 的原生滑鼠／KERNAL 驗證，不是實機。
- **Sprite 順序：** 用同一個 attribute 設定的測試 build 強制讓手套與
  游標／選取框重疊，確認手套在上；slot 66 的提示框也能完整畫出綠色
  邊框。這是原生 x16emu 測試，不是實機。
- **音樂：** 修正兩個 out-of-range 分支後，61.7 秒原生 WAV 沒有再出現
  `BBS`／Rockwell 警告。載入後音樂連續約 54 秒；該區間最長 zero run 為
  **0.389 ms**、最大絕對 sample **0.291**、沒有 sample ≥ 0.999；
  1 秒 spectral flatness 約 0.08-0.18，沒有寬頻爆音。另一個 24.3 秒的
  正常 title→Timetrial 擷取，在載入後 11 秒音樂段也沒有斷點。先前的
  30 秒爆音在這些擷取中沒有重現。
- **音效：** 19.7 秒原生 WAV 直接呼叫與消除寶石相同的
  `sound_play(SFX_MATCH1)`（音樂關閉），含 12 次 match，每次約 0.30 秒、
  peak **0.191**、無 clipping、無被截斷的片段；另一輪音樂＋match 混合
  在音樂開始後，沒有超過 **2 ms** 的 zero run。上面實際得分的 in-game match **沒有同一輪同步
  錄成 WAV**；音效 WAV 是另一輪的直接路徑擷取，也不是真人聽感。
- 原生 x16emu 已走過開機、intro、title、Timetrial、倒數、盤面互動與
  滑鼠選取。
- 計時器使用 12×18 `fuentelcd.ttf` 反鋸齒遮罩；原生截圖是細 LCD 筆畫，
  沒有粗黑殘影。
- 之前（這一輪未重跑）驗過 Game Over、高分寫入／讀回、Title Exit 回到
  BASIC，以及 overlay 往返後的 bitmap 乾淨。

這一輪沒有驗證：

- 完整 126.35 秒播到 EOF（最長只擷取 61.7 秒）；
- 實機 PCM 音量、音樂／音效平衡、時序與搖桿對應；
- 目前瀏覽器版的 runtime。`web/` 已用目前 `hostfs/` 重新建置，但這一輪
  沒有完成新的 headless browser 互動測試。之前只到 title 與 Timetrial；
  不要把瀏覽器滑鼠／音訊視為這一輪已驗證。

這次修的兩個具體音訊 bug 是：`MACPTR` 回傳數被截掉高位（現在 X、Y
都用），以及兩個 `beq` 被截成往回跳、執行 `FF AD 44`（`BBS7`）。
後者就是 Rockwell 警告與舊 30 秒故障前讀取狀態損壞的來源。
