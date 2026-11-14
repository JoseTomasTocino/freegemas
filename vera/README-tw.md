# Freegemas for Apple //e VERA

[English](README.md) | 繁體中文

這是 Freegemas 的 Apple //e VERA 移植版。遊戲以 LLVM-MOS C 編譯為 65C02 程式，使用 VERA 320×240、8bpp bitmap、常駐 gem sprites 與頂部遮罩繪圖，透過 ProDOS HDV 分段載入標題、遊戲和說明／設定畫面。

建置後會產生可開機的 [`freegemas.hdv`](freegemas.hdv)，容量 2048 KB；這個產物不進版控。

## 建置

需要 Node.js、Python（NumPy）、ffmpeg／ffprobe、CMake、LLVM-MOS SDK 與 Cadius。請將 Cadius 放入 `PATH`，或以 `-DCADIUS_EXECUTABLE=/path/to/cadius` 指定。

打包還需要 `PRODOS#FF0000` 與 `CLOCK.SYSTEM#FF0000`。這兩個系統檔不隨 repo 散布；請從你有權使用的 ProDOS 發行版複製到 `vera/assets/prodos-system/`，或用 `-DVERA_PRODOS_DIR` 指向包含這兩個檔案的目錄。

在 repo 根目錄執行：

```powershell
node vera\tools\build_assets.mjs
cmake -S vera\llvm -B vera\llvm\build `
  -DLLVM_MOS_SDK=C:\path\to\llvm-mos-sdk\install `
  -DCADIUS_EXECUTABLE=C:\path\to\cadius.exe `
  -DVERA_PRODOS_DIR=C:\path\to\prodos-system
cmake --build vera\llvm\build --target disk --parallel 4
```

`build_assets.mjs` 從 repo 的 `media/` 產生 indexed bitmap、sprites、palette 與 RLE 場景。CMake 會建立 slot 2／slot 4 的遊戲 binary，`build_hdv.py` 再將它們和場景檔打包成 `vera/freegemas.hdv`。

`LLVM_MOS_SDK` 請設為 SDK 根目錄（內含 `bin/`），或用 CMake 的 `-DLLVM_MOS_SDK=...` 指定。HDV builder 使用 Cadius 建立新的 2048 KB ProDOS volume，再加入系統檔與遊戲檔案，不再依賴 HDV 範本。

AppleWin 範例：

```powershell
AppleWin.exe -s2 vera -s7 hdc -h1 vera\freegemas.hdv
```

AppleWin 若正掛載映像，重建前先關閉模擬器，避免 HDV 被鎖住。

## 以 ProDOS 檔案安裝

HDV volume name 為 `FREEGEMAS`。若要安裝到其他 ProDOS volume 或子目錄，請將 HDV 內所有檔案複製到目標位置，唯獨不複製 `PRODOS`。請保留 `FREEGEMAS` marker 檔，將 ProDOS prefix 設為該位置，再執行 `FREEGEM.SYSTEM`。Loader 和遊戲會依檔名開啟程式、場景、圖樣、音樂、音效及 `HISCORE.DAT`，不依賴原 HDV 的 block 配置。新產生的檔案目錄項目會寫入本機建置日期與時間，格式符合 ProDOS。

舊版以範本建立的 HDV 已用 AppleWin 確認可直接開機、進入遊戲並返回 Title；檔案層級安裝到 VeraSD 也已確認可執行且 `HISCORE.DAT` 能持久寫入。新的 Cadius HDV 已建置並檢查 ProDOS catalog，但仍需重新驗證開機。

啟動時先偵測 slot 2／4 的 VERA；兩者皆無卡時仍完整顯示作者、網址、滑鼠偵測及操作說明。STATUS 顯示 `VERA NOT DETECTED`，下方顯示 `STOPPED: VERA REQUIRED IN SLOT 2 OR 4` 並停止；按鍵也不會進入 Title 或遊戲。

## 操作

- Title：方向鍵選擇；Space／Enter 開啟 Time Trial、Endless、How to Play 或 Options。
- How to Play：任意鍵返回 Title。
- Options：上下移動；Space／Enter 將 Music 依序切換 PCM／PSG／Off、切換 Sound，或選 Back；Esc 返回 Title。
- 遊戲：方向鍵或 Apple Mouse Card 移動游標；Space 或滑鼠點擊選取／交換，H 顯示提示，R 重設，Esc 返回 Title。滑鼠顯示原作手形游標，也可點左側 Show Hint、Reset Game、Exit。滑鼠支援 slot 4／5；VERA 裝在 slot 4 時，Mouse Card 請裝 slot 5。
- Title 的 EXIT：保存高分後，以 ProDOS QUIT 回到 Bitsy Bye 檔案選單。
- 啟動時先顯示作者 ANOMIXER 2026 與操作鍵說明；按任意鍵或等 5 秒進入 Title，遊戲回 Title 不重播。
- 開機 STATUS 也顯示 `MOUSE: SLOT 4`／`MOUSE: SLOT 5`／`MOUSE: NONE`，確認滑鼠卡偵測結果。

Sound 使用原作 `select.ogg`、`fall.ogg`、`match1–3.ogg`，以 signed 8-bit mono VERA PCM、rate 21（8010.86 Hz）與原作增益轉換，五份合計 9740 bytes，全部預載到 VERA VRAM `$14800` 之後，播放零磁碟讀取、不佔輔助 RAM。

PCM 音樂模式中，音樂與音效共用 VERA PCM FIFO 並以軟體混音。音樂峰值約 ±61、音效約 ±37，signed 8-bit 相加不會溢位；PCM volume 13（38/64）讓 apple2ts／AppleWin 的兩倍混音保留餘裕，音量比 volume 15 低約 4.5 dB。音效 staging 保留 VERA 繪圖狀態。

PCM 模式從磁碟串流整首錄音：`MUSIC.PCM` 為 1012224 bytes（1977 個 ProDOS block、126.35 秒）。`tools/build_music_pcm.py` 以 ffmpeg 產生（linear-interp 重採樣到 8011 Hz、衰減到約 0.48 全刻度、40-sample fade）；原始音軌本身已接近全刻度，再加 6 dB 只會讓 limiter 削波。0.70 limiter 現在只是保險上限，不會被觸發。遊戲以 1KB ring buffer 從磁碟串流，FIFO 維持約 1024 bytes，每 VSYNC 補 133／134 samples；當 frame 超過 VSYNC、`waitvsync` 沒等到就返回時，只要 audio-low（ISR bit 3，FIFO < 1024）顯示佇列已低於目標深度，就持續補 128 samples 的追趕批次（`MUSIC_CATCHUP`），直到回到目標深度，以減少 FIFO 缺料，但超過緩衝餘裕的停頓仍可能造成斷音。長時間的 CPU 迴圈（無解掃描、棋盤生成）會呼叫 `frame_pump()`，在 VSYNC latch 已設時就地付掉音訊工作。實際送進 FIFO 的 sample 數同時被當成機器的實時參考：`music_frames_elapsed()` 把它換算成整數個 VSYNC tick（一 frame 133514 個千分位），Time Trial 倒數改加這些 ticks，所以兩分鐘的計時現在真的按實時前進，而不是每個迴圈只加一次（以前 1.6 frame 的連鎖動畫只跳 1.6 tick，音樂卻播了兩個 frame）。每次 loop 只做一次 SET_MARK，之後連續 MLI READ 最多 1KB；短讀取退回 512-byte 讀取。整首循環播放。

PSG 模式沿用原本的 `music_pure_gained.psg` 編曲，進入遊戲時由 `MUSIC.PSG` 預載至輔助 RAM；播放 PSG 音樂與已預載 PCM 音效時不需讀取音樂或音效檔。啟動、R 重載場景、切換畫面與儲存高分仍可能存取磁碟。YM2151 probe 僅供顯示，目前不使用 FM 音樂。

使用者已在 Apple2TS 試玩最終測試映像，確認 PCM 音效、PSG 播放與寶石下落正常；此版本尚未重新驗證 AppleWin 或實機。

Sound／Music 互不連動；音樂只在遊戲畫面播放，R 從頭重播，Esc 會靜音、關閉檔案並把磁碟交回 loader。

`LOADING GAME...` 在遊戲程式載入後會顯示 186 個資產 block 的進度條、百分比與階段；棋盤準備完成才到 100%，下方顯示 `GAME START`。遊戲 binary 本身載入期間仍是原本文字提示；`MUSIC.PCM` 不列入這個進度條，它是在遊戲中邊玩邊從磁碟串流。

無合法交換時依原作規則：Endless 結束並顯示 Game Over；Time Trial 自動讓寶石掉出、補入新棋盤，保留分數並繼續倒數。R 則是重新開始本局。

## 專案內容

- `llvm/src/`：loader、title、menu screens、遊戲與棋盤邏輯。
- `llvm/tools/build_hdv.py`：建立 ProDOS HDV。
- `assets/prodos-system/`：可選的本機 ProDOS／CLOCK.SYSTEM 放置位置，已由 `.gitignore` 排除。
- `tools/build_assets.mjs`：從原作素材產生 VERA assets。
- `generated/`：重建 binary 所需的 palette、sprite、tile 和 RLE 輸入檔。

## 目前範圍

滑鼠支援 Title 選項、Options 的 Music／Sound／Back，以及 How to Play 點擊返回。遊戲可點選兩顆相鄰 gem，或按住第一顆拖至相鄰 gem 立即交換；每次拖曳只觸發一次。Show Hint、Reset Game、Exit 亦可點擊，所有頁面使用原作手形游標。Fullscreen 固定 ON。

Title、How to Play、Options、兩種遊戲模式、match／cascade／計分、消除星芒、得分浮字與 Game Over 動畫已移植。gem 落地保留 sprites，不整張重畫棋盤；HUD 只更新變動數字。Title 色盤已重新量化並改善漸層。

Options 下方顯示兩種模式的最高分，回選單時保存至 `HISCORE.DAT`，已做 AppleWin 寫入／重開讀回測試。未回選單就強制關閉，尚未保存的紀錄會丟失；重新建置 HDV 會保留既有有效紀錄。

目前提交的最終映像中，兩種模式的最高分皆已重設為 0。

PCM 現階段為 **原作錄音的移植原型，不是 100% 原作音訊**：signed 8-bit mono、VERA rate 21（8010.86 Hz），原作是 44.1／48 kHz，部分音效是 stereo。五個音效共 9740 bytes，開局全部預載進 VERA VRAM `$14800` 之後，不再使用輔助 RAM；播放只從 VRAM 補 FIFO，零音效磁碟讀取，未新增有損壓縮。PCM 音樂與音效共用 FIFO，以軟體相加混音；PSG 音樂使用獨立 PSG 聲道。新音效會中斷舊音效，Title／Options 導航聲尚未接入。1 MHz CPU 仍須每 VSYNC 補 FIFO，預載不等於 CPU 不需工作；實際聽感仍需試聽。disk target 自動執行 `tools/build_sound.mjs` 與 `tools/build_music_pcm.py`，產生 PCM 和 `llvm/build/*.wav` 試聽檔。音訊設定目前只在同一次執行期間保留。

## 音樂轉換研究

`tools/build_music_pcm.py` 與 `tools/build_sound.mjs` 是目前使用的音訊轉換器。早期 WAV→PSG、MIDI 配器與 YM2151 實驗記錄在 [`docs/music-conversion-research.md`](docs/music-conversion-research.md)；PSG 模式直接使用之前核准的素材。

## 回歸測試指令

```powershell
python -m pip install py65 numpy
python -u vera\llvm\tools\test_mos.py
python -u vera\llvm\tools\test_sound.py
python -u vera\llvm\tools\test_music.py
python -u vera\llvm\tools\test_psg_music.py
python -u vera\llvm\tools\test_pcm_clock.py
python -u vera\llvm\tools\test_mouse.py
python -u vera\llvm\tools\test_vera_detect.py
```

執行實際的 65C02 binaries，使用可追蹤 VRAM 寫入的 VERA／MLI model，涵蓋 slot 2／4、連鎖、局部更新、Hint、時間到／R 與高分讀寫。磁碟是記憶體中的副本，不會寫入測試分數到交付映像。這是補充測試，不能取代 AppleWin 和實機驗證。

`test_music.py` 在兩個 slot 逐 byte 串流完整的 1012224 bytes `MUSIC.PCM`，並驗證磁碟讀取、loop 點、OFF／ON、音效逐 sample 混音、R 重播與 Esc 靜音。`test_sound.py` 驗證五個音效在 VRAM 的實際位址與 byte、OFF／ON、替換、自然播完、port 保留，以及播放音效不會重新開啟檔案。`test_pcm_clock.py` 依 CPU cycle 以 8010.86 Hz 消耗 FIFO，比對實際渲染串流與來源 PCM，包含 230 ms 饑餓缺口與音效混音區間。

`test_mos.py` 的 model 現在除了 block 讀寫（`$80`／`$81`）也實作 resident loader 用到的檔案層 MLI（`GET_PREFIX` `$C7`、`OPEN` `$C8`、`READ` `$CA`、`WRITE` `$CB`、`SET_MARK` `$CE`、`GET_EOF` `$D1`、`CLOSE` `$CC`、`QUIT` `$65`），冷開機、Title 與遊戲內路徑都能在 harness 跑完。`test_loading_progress.py` 依磁碟實際檔案計出 186 個資產 block。這些仍是 model 測試，不是 AppleWin 或實機驗證。
