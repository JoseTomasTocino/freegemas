# VERA PSG 音樂研究與目前取捨

清理說明：**目前建置與遊戲只使用 `generated/music.pcm`（`MUSIC.PCM` 串流）和五個 `generated/*.pcm` 音效**；下面所有 PSG／FM／FGM／VZM 章節都是歷史研究記錄，對應的工具與產物（`build_music.py`、`build_music_vzm.py`、`midi_psg_arrange.py`、`wav2psg.py`、`test_music_vzm.py`、`test_music_conversion.py`、`test_midi_arrangement.py`、`generated/music*.psg`／`*.vzm`／`*.zsm`／`*.h`）已經從 repo 刪除，只剩文字記錄。原始 MIDI `vera/assets/music.mid` 仍保留，作為 `build_music_pcm.py` 的輸入。

## 目前狀態：整首串流 PCM（2026-10-29）

使用者聽過 FM 版後要求「全部改成 PCM，像 IIgs 那樣」，且不要管機器有沒有 YM2151。現在的實作：

- `vera/tools/build_music_pcm.py` 讀 `media/music.ogg` → ffmpeg 解碼／`aresample=8011`／`volume=0.36`（衰減；來源本身已達 0.94 全刻度）／`alimiter=limit=0.70`（僅保險上限，正常不會觸發）／`-f s8`，輸出 `vera/generated/music.pcm`：signed 8-bit mono、1012224 bytes、1977 個 ProDOS block、約 126.35 秒，峰值 ±61、rms 9.1。40-sample fade 開頭避免起播爆音。
- `vera/tools/build_sound.mjs` 用同一取樣率 8011 Hz、`volume=0.35,alimiter=limit=0.29`、`-f s8` 產生五個音效（select 1100、fall 1431、match1／2／3 各 2403 bytes，合計 9740 bytes），全部預載到 VRAM `$14800`。音樂上限 61 + 音效上限 37 = 98，所以在 `pcm_mix` 用 signed 相加不會溢位；網頁版 apple2ts 把 `(PSG + PCM)` 乘 2 後 clamp 到 ±1.0，0.96 也不會削波（AppleWin 只做相加，超過 127 才 clamp）。
- 播放：`MUSIC_RATE 21` 對應 AppleWin 的 8010.86 Hz；每 VSYNC 從磁碟串流 133／134 bytes 進 1 KB ring，維持 FIFO 約 1024 bytes 深，音效和音樂共用同一條 FIFO。frame 超過 VSYNC 時 `waitvsync` 不等待就返回，單次補 133／134 會跟不上硬體連續消耗；`music_tick` 因此再讀 ISR bit 3（audio-low，FIFO < 1024），仍在目標深度之下就持續補 `MUSIC_CATCHUP` 128 samples 直到回滿，避免佇列滑到 0 而斷音；長 CPU 迴圈另以 `frame_pump()` 就地付掉音訊工作。送進 FIFO 的 sample 數同時作為實時時鐘（`music_frames_elapsed()`，一 frame 133514 個千分位），Time Trial 以它計時。
- 沒有 Aux RAM、沒有 PSG、沒有 FM 播放路徑；`fm_detect()` 只在 Intro 顯示 `FM: YM2151 DETECTED (OPM)`／`FM: NONE`，與播放無關。
- 驗證：`test_music.py`（整份 1012224 bytes、磁碟讀取、OFF／ON、混音、R 重播、Esc 靜音）、`test_sound.py`（五個檔案在 `$14800` 起 byte-exact）、`test_pcm_clock.py`（CPU cycle 推進 FIFO，無 PSG 寫入）、`test_loading_progress.py`（186 blocks），兩 slot 全綠。這些是 65C02／VERA model 比對，本環境 AppleWin 的 `-fm-wav-dump` 只產生全零樣本，**沒有** AppleWin 或實機聽感驗證。

## 歷史：已移除的 YM2151 FM 版 `MUSIC.VZM`（2026-10-28）

新增第二條音樂路徑：機器上有 A2VERA 的 YM2151 時，遊戲播放 `generated/music.vzm`（打包串流，HDV 上為 `MUSIC.VZM`），整首編曲走 8 個 FM 聲道（7 旋律 lead、0–1 bass、2–6 tine），不含 PSG 打擊；沒有晶片或檔案不存在時才回退到下方純音 PSG。

- **轉譜流程（2026-10-28 重做）**：`tools/build_music_vzm.py` 不再解 OGG 做 FFT，而是直接讀取 repo 內的 `assets/music.mid`（原作 OGG 的 MIDI 轉譜，format 0、3175 音符、122.78 秒、無鼓軌）。音高、音符起訖與力度取自 MIDI 音符清單，量化到 60 Hz tick 後指派聲部。因為來源沒有鼓軌，FM 版刻意不做打擊聲部；先前 FFT/onset 版誤判泛音、自行發明 PSG 打擊，是「聽起來亂七八糟」的主要來源。旋律仍不是人工校訂樂譜，也不是原作分軌，但錯誤只可能來自 MIDI 轉譜本身，不再來自音訊分析。
- **聲部**：低於 MIDI 52 的音分配到 2 個 bass FM 聲道（CON=4，TL 較高、衰減較長）；其他音符優先給目前最高音的 lead 聲道 7，其餘輪流給 tine 聲道 2–6；同一音符由 key-on 到 key-off 固定佔用同一聲道（不因更換旋律而重觸發），8 聲道滿時偷取最早結束的音。8 個音符同時發聲是上限。
- **ZSM 內容**：7367 個 tick（tick rate 60，約 122.8 秒），10959 次 FM 寫入、0 次 PSG 寫入、432 次 voice steal；未壓縮的 ZSM 為 32428 bytes，VZM 為 28534 bytes（去掉檔頭與 512-byte 記錄補齊、縮短延遲編碼），112 個 logical page。全部塞進當時的 800 KB HDV 後仍有空間同時放 `MUSIC.PSG`（現在映像是 2048 KB，且這條路徑已移除）。
- **音色**：三組 CON=4 patch（bass／tine／lead），frame 0 編程；carrier TL 只依 MIDI 力度在 note-on 寫一次，避免逐 tick 重送。所有 patch 的輸出音量已拉高到與 PSG 後備相近（preview peak 0.867、rms 0.176，無 clipping），不再重現舊版 −26 dBFS 的幾乎無聲。
- **寄存器去重**：轉換器維護 `fm_last[256]`／`psg_last[64]` 全零基線，只送變更值；`$08`（key mask）永遠送出，因為開關音不需要值相同。播放器在起播與每次 loop 也把 YM `$20–$FF` 清零、PSG 基線設為 `0,0,0,128`，所以去重假設在實機上成立（起播那一個 tick 會送出完整 patch）。
- **音高換算**：MIDI 音高 → KC 用 `block = midi//12-2`、code 14（C）處理 C，其他用 `block = midi//12-1` 加 `KC_INVERSE = (0,1,2,3,5,6,7,9,10,11,13)`；以 melodius 逐半音實測 MIDI 36–84 誤差 <40 cents。TL 每格約 0.75 dB，音量映射以 8 格 ≈ 6 dB 為單位。
- **成本**：起播與 loop 兩個 tick 各約 44k cycles（1.023 MHz 下約 43 ms），因為要清晶片並送完整 patch；其他 tick 平均約 743 cycles。這是模型量測，不是實機示波器或音訊擷取。
- **驗證**：`llvm/tools/test_music_vzm.py` 在 65C02 model 上比對 probe、Intro 文字、`music_init` 的選擇／後備，以及 7368 tick 的 PSG 寄存器影像與 YM2151 寫入順序；兩個 VERA slot 都 byte-exact。客觀聆聽比對：FM preview 與原作 OGG 的分段 chroma 相關係數 0.64–0.77（舊 FFT 版 0.47），99.8% 有聲 frame 覆蓋率，無 clipping。這些都只證明音符內容與播放器一致，**不證明 FM 音色或聽感正確**。
- **尚未完成**：本環境的 AppleWin 沒有可用音訊裝置（`-fm-wav-dump` 擷取全為靜音），因此仍沒有 AppleWin 或實機試聽；FM 音色只做了基本 carrier/modulator 設定，未逐聲道人工調音，也未加入原作鼓聲。`MUSIC.VZM` 與 `MUSIC.PSG` 的音量仍未互相對齊量測。

## 歷史：已移除的純音 PSG 版（2026-09）

後續音量追調：遊戲 Music gain 由2改為2.828427，相較前版約+3dB，相較來源PSG約+9dB；量化至VERA LUT，超過每聲道最高511則封頂。編排／音高／事件時間不改，核准的WAV本身未修改。音效预載是另一項尚未完成的工作，不能把音樂aux預載視為PCM音效也已預載。

使用者核准 `music_pure_player_linear_listen_louder.wav` 後，採其來源 `generated/music_midi_pure_smooth.psg` 的純音編排接入遊戲。`tools/build_music.py` 以 native PSG volume LUT 映射2倍增益，去重並bit-pack為 `generated/music.fgm`（41139 bytes／7398 frames，約123.3秒循環），disk target打包為 `MUSIC.FGM`。不用再取得ignored build內的原 MIDI 即可重建遊戲音樂。

`llvm/src/music.c`／`music_aux.S` 開局前預載至aux `$0800`起（不得超出 `$BFFF`），播放只從aux頁cache解碼，不做音樂 disk I/O。需要128KB Apple IIe；無aux安全停用。Options Music ON／OFF、R從頭、Esc停止再返回Title；目前Title／Options不播放。PCM音效與PSG音樂獨立。18-byte MAIN／AUX `$0300` reader鏡像避免RAMRD instruction-fetch切換造成崩潰，讀頁時關IRQ、結束恢復MAIN；loader下次launch會覆寫MAIN reader。

兩slot的實際65C02 binary經instrumented model逐frame比對全部7398frames通過，包含loop、OFF/ON、缺aux、Music初始OFF、graphics port保留、PCM互不影響、R／Esc和返回Title；音樂自身平均2801cycles、最高14948。遊戲／PCM／no-move／Options回歸通過；整體動畫仍約35.3kcycles平均（PCM串流等成本），並非1MHz全程60fps。尚未實際AppleWin／硬體試聽。

重要限制：核准WAV是高精度triangle／線性混音預覽，VERA實際波形6-bit與增益不同。遊戲是其純音音符／包絡的PSG版加約6dB，不是該WAV逐sample重播，不能聲稱响度或砂礫聲完全一致。若實機仍有不能接受的顆粒感，需另外評估PCM音樂、磁碟容量及與PCM音效混音的成本；本次沒有偷偷改回bass／打擊編排。

## Ensemble 短音清理（2026-09-27）

播放器排查：`tools/build_psgplay_compare.ps1` 建置 `llvm/build/psgplay_compare.exe`。Wrapper 編譯引用外部 veramusic 原始 player，不修改外部 repo；預設用 linear /16 headroom，`--original` 還原原版 tanh。`--render output.wav` 可用相同 oscillator／phase／register 更新方式離線輸出全曲。純音 PSG 實測混音 peak 0.903789（進 tanh 前除3），沒有高到足以直接認定嚴重飽和；不得把播放器 tanh 當已確認的砂礫聲來源。比較檔 `music_pure_player_original.wav` 與 `music_pure_player_linear_listen.wav`（linear /16 以16/3線性增益補回，近似原版小訊號增益）均無 PCM clipping，長度7398frames。預覽不是硬體擷取；線性播放器預設較小聲，測試時須注意響度差，尚未執行實際音訊播放驗證。使用者可再用 --original 作對照，PSG 音符不變。

純音排查版：`python vera/tools/midi_psg_arrange.py --pure --smooth`，輸出 `music_midi_pure_smooth.psg`。移除 note<48 與明確 GM drum／taiko，保留高音域的來源音符，統一 keys triangle 包絡；不加整數泛音、音域配器／鼓模擬／強音壓縮，保留短高音清理及 60Hz 平滑。來源沒有分軌，按音域移除 bass 也可能拿掉其他低音旋律；高音域內原轉錄的敲擊碎片不能聲稱完全分離。測試涵蓋 bass／drum 不輸出、單音不產生額外聲道與純 triangle。這是用來排查砂礫聲的版本，非原曲精確分軌，尚未接入遊戲。

使用者要求回 smooth_soft 單獨拿掉 taiko：`--style ensemble --no-overtones --smooth --soft-percussion --no-taiko`。MIDI 全 channel0／program0，並沒有真正 taiko 聲道。檢查約5.36／11.22／17.08／22.94秒都有強短 D2（note38）與短低音碎片群；以 note38、velocity>=75、75–150ms 作錨點，移除其前1秒／後0.8秒內 note<48、duration<=180ms 的配對事件。全曲同規則，非整段靜音；保留 marimba 與持續 bass，但可能刪掉該區域真正的短 bass，必須試聽確認。輸出 `music_midi_ensemble_no_overtones_smooth_soft_no_taiko.psg`，移除529事件對／90351 bytes，測試檢查四處錨點及持續 bass／marimba 保留，完整 stream 通過。尚未確認這些就是砂礫声來源，未接入遊戲。

無打擊樂對照：`--style ensemble --no-overtones --smooth --no-percussion`，移除啟發式 marimba（note 60–71）及明確 GM drum channel／taiko program 音符，保留 bass／guitar／celesta。來源 MIDI 沒有真正的打擊分軌，因此可能一併移除該音域的旋律，且 celesta／guitar 仍有 pluck 音色；不可稱為原曲分軌分離。輸出名稱 `music_midi_ensemble_no_overtones_smooth_no_percussion.psg`，保留其他版本供比較；測試檢查 marimba／drum 被省略且 guitar 不受開關影響，未接入遊戲。

大敲擊仍有砂礫感的第三份對照：`--style ensemble --no-overtones --smooth --soft-percussion`，輸出 `music_midi_ensemble_no_overtones_smooth_soft.psg`（103753 bytes）。對啟發式 guitar／marimba／celesta／drum 的音符力度套 soft knee：振幅 <=0.12 不改，以上以指數漸近至 0.20；bass 不改。這不是從 MIDI 找回真正敲擊分軌，也會降低較強的旋律 pluck。力度改變會影響 voice allocation（245 steals，原平滑版255）；來源事件／節奏／音高不改，但不能聲稱所有較輕音符的輸出 registers 完全相同。動態函式單調、不增益、低力度與 bass 保留測試及完整 stream 驗證通過。仍待 psgplay 試聽，不宣稱砂礫聲已消除。

砂礫聲第二份對照：在 `--no-overtones` 後加 `--smooth`，輸出 `music_midi_ensemble_no_overtones_smooth.psg`（105887 bytes／7398 frames）。關閉 20Hz 包絡節流、改每 frame 更新；gate／同聲道換音高的連續段套三 frame raised-cosine 起落，立即換音高前一 frame 靜音。保留來源音高與事件時間，但短音會較柔和，輸出事件數增加。測試涵蓋起落衰減、換音高靜音、音高不改及尾端靜音；PSG 流驗證通過。這不是 sample-level de-click，播放器相位／tanh 混音也未更改，砂礫聲是否消除仍待使用者試聽；未接入遊戲。

砂粒感對照版：`python vera/tools/midi_psg_arrange.py --style ensemble --no-overtones`，輸出 `generated/music_midi_ensemble_no_overtones.psg` 及同名 WAV／JSON。僅停用額外 2f／3f 短促泛音，主音配器、清理、力度與包絡不變；保留原 ensemble 檔供 A/B 試聽。單音測試確認無額外聲道且 primary registers 相同。此對照尚未證明砂粒聲來源，未接入 HDV。

依使用者回報檢查 0:23、1:11、1:13、1:17、1:21：MIDI 存在弱力度、高音域的短促音群。Ensemble 現在過濾 note >=84、velocity <=40、duration <=220ms 的疑似轉錄雜音，以及其前後 80ms 內 note >=72、velocity <=50、duration <=75ms 的短音。規則套用全曲，不按指定時間整段靜音；成對移除 note-on/off，保留較強或較長音符。這是啟發式清理，仍可能移除真實弱短音，需試聽確認；原 MIDI 與 clean 版本不變。

本次移除 151 顆疑似雜音，PSG 89927 bytes，voice steals 255。測試檢查指定區段清理、0:23 持續旋律保留與強高音不被刪除；完整 PSG 流驗證通過。詳細移除清單保留在輸出 JSON。

最新預覽在 `llvm/build/music_midi_ensemble_fixed.wav`（全曲）、`music_midi_ensemble_fixed_25s.wav`（前 25 秒）、`music_midi_ensemble_fixed_69s.wav`（1:09 起 16 秒）。均為線性增益 3 的軟體預覽，未接入遊戲／HDV。

2026-09-27。這些是研究和試作，不代表已移植至遊戲。

## 來源

- [原作者 Easy Lemon 曲目頁](https://incompetech.com/music/royalty-free/index.html?Search=Search&isrc=USUAN1200076)：Guitar、Bass、Kit、Celesta、Marimba，82 BPM，2:06。使用者轉錄的 MIDI 為 format 0、一個 channel、program 0（鋼琴）、3175 notes、約 122.77 秒，並沒有恢復原曲多樂器／鼓組分軌。
- [DreamTracker VERA Instruments](https://dreamtracker.bitbybitsynths.com/manual/vera_instruments/) 與 [Envelopes](https://dreamtracker.bitbybitsynths.com/manual/envelopes/)：音量／PWM envelope、波形、聲道與 pitch 控制是 PSG 配器的基本工具；不是單純替換 MIDI 播放器。
- [Furnace VERA instruments](https://github.com/tildearrow/furnace/blob/master/doc/4-instrument/vera.md)：支援 Volume、Arpeggio、Duty、Waveform、Panning、Pitch macros。可作為手工精修配器的工具；沒有把 MIDI 自動轉成原作樂器的保證。
- [VERA 音訊規格](https://github.com/X16Community/x16-docs/blob/master/X16%20Reference%20-%2009%20-%20VERA%20Programmer%27s%20Reference.md)：16 voices、四種波形、log volume、17-bit phase。AppleWin 實際行為另對照本機 VERAAudio.cpp，不混用 YM2151 或 wavetable expansion 的音色能力。

## 舊 converter 的具體問題

`veramusic/tools/mid2psg.mjs` 的先前 piano preset 是針對其他曲目的特殊調整，不能直接當通用忠實 converter：低音會增加數個 voices（包含 +7 semitone 的額外音高）、低於 note 36 自動升八度、bass note-off 以每 frame 0.35 volume index 減少，尾音可拖數秒，力度被壓到高 volume。WAV 預覽还加入 tanh 飽和增益，且 noise 在該預覽 renderer 為零；pulse duty 公式也不同於本機硬體。

## 新試作

`tools/midi_psg_arrange.py`：保留音符音高／原力度／tempo、CC64 sustain、pitch bend；一個來源音符一個 primary voice；不自動移調、不亂加五度、note-off 約 45ms 指數 release。淡出在 20Hz 更新以縮小事件流；起音／關閉即時更新。仍可能遇到 16 voice 上限，報告列出 voice steal 次數，不掩蓋缺音。

- `--style clean`：保留鋼琴式 triangle，重新平衡 bass 和自然音量 envelope，不做原作樂器分離。
- `--style ensemble`：依音域推估 bass／guitar／marimba／celesta，不聲稱找回原作 stems。不同角色使用不同 pluck decay；僅在有空聲道時加 2f／3f、低音量、快速消退的真泛音起音，不搶 primary。這是可試聽的配器改編，仍需人工校訂與使用者確認。

輸出 `generated/music_midi_clean.psg`／`music_midi_ensemble.psg`。原始硬體增益預覽在 `llvm/build/music_midi_*.wav`；`*_listen_25s.wav` 只為方便試聽提升 3 倍線性音量，沒有 compressor／tanh／normalize；不修改 PSG。預覽不是 AppleWin／實機擷取，不能把它当作硬體試聽驗證。

還需解決：原作 kit／雙擊低鼓的分離、分軌／配器精修、較接近原作的音色、音樂與預載 PCM 音效的共同記憶體配置、IRQ 預算與實機試聽。純 PSG 無法聲稱 100% 恢復原作錄音。
