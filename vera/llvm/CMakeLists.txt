cmake_minimum_required(VERSION 3.20)
project(FreegemasIIvera LANGUAGES NONE)

set(LLVM_MOS_SDK "$ENV{LLVM_MOS_SDK}" CACHE PATH "llvm-mos SDK root (contains bin/)")
if(NOT LLVM_MOS_SDK)
  message(FATAL_ERROR "Set LLVM_MOS_SDK or pass -DLLVM_MOS_SDK=<llvm-mos-sdk>/install")
endif()
set(VERA_PRODOS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../assets/prodos-system" CACHE PATH "Directory containing PRODOS#FF0000 and CLOCK.SYSTEM#FF0000")
find_program(MOS_CLANG NAMES mos-apple2e-clang.bat mos-apple2e-clang HINTS "${LLVM_MOS_SDK}/bin" NO_DEFAULT_PATH REQUIRED)
find_program(CADIUS_EXECUTABLE NAMES cadius cadius.exe REQUIRED)

set(SRC "${CMAKE_CURRENT_SOURCE_DIR}/src")
set(MENU_MOUSE "${SRC}/menu_mouse.c" "${SRC}/mouse.S" "${SRC}/mli.s")
set(LOADING_HEADER "${CMAKE_CURRENT_BINARY_DIR}/loading_data.h")
add_custom_command(OUTPUT "${LOADING_HEADER}"
  COMMAND python "${CMAKE_CURRENT_SOURCE_DIR}/tools/build_loading.py" "${LOADING_HEADER}"
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/build_loading.py" "${CMAKE_CURRENT_SOURCE_DIR}/../tools/build_sound.mjs"
    "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_scene.rle" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_endless.rle"
    "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_gems_32.idx"
    "${CMAKE_CURRENT_SOURCE_DIR}/../generated/select.pcm" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/fall.pcm"
    "${CMAKE_CURRENT_SOURCE_DIR}/../generated/match1.pcm" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/match2.pcm"
    "${CMAKE_CURRENT_SOURCE_DIR}/../generated/match3.pcm" VERBATIM)
set(OUT "${CMAKE_BINARY_DIR}/freegemas.bin")
set(OUT4 "${CMAKE_BINARY_DIR}/freegemas4.bin")
set(TITLE "${CMAKE_BINARY_DIR}/title.bin")
set(TITLE4 "${CMAKE_BINARY_DIR}/title4.bin")
set(SYSTEM "${CMAKE_BINARY_DIR}/freegemas.sys")
set(HOWTO "${CMAKE_BINARY_DIR}/howto.bin")
set(HOWTO4 "${CMAKE_BINARY_DIR}/howto4.bin")
set(OPTION "${CMAKE_BINARY_DIR}/option.bin")
set(OPTION4 "${CMAKE_BINARY_DIR}/option4.bin")
set(GEN "${CMAKE_CURRENT_BINARY_DIR}/gem_tiles.h")
set(PALETTE_GEN "${CMAKE_CURRENT_BINARY_DIR}/game_palette.h")
set(TITLE_PALETTE_GEN "${CMAKE_CURRENT_BINARY_DIR}/title_palette.h")
set(SELECTOR_GEN "${CMAKE_CURRENT_BINARY_DIR}/selector.h")
set(SCENE_GEN "${CMAKE_CURRENT_BINARY_DIR}/scene_rle.h")
set(TITLE_SCENE_GEN "${CMAKE_CURRENT_BINARY_DIR}/title_rle.h")
set(GEMS_GEN "${CMAKE_CURRENT_BINARY_DIR}/gem_sprites.h")
set(SPRITES_GEN "${CMAKE_CURRENT_BINARY_DIR}/sprite_patterns.h")
set(TITLE_GEMS_GEN "${CMAKE_CURRENT_BINARY_DIR}/title_gems.h")
set(EFFECTS_DIGITS_GEN "${CMAKE_CURRENT_BINARY_DIR}/effects_digits.h")
set(MOUSE_GEN "${CMAKE_CURRENT_BINARY_DIR}/mouse_hand.h")
add_custom_command(OUTPUT "${MOUSE_GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/../tools/build_mouse.mjs"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/mouse_hand_16.bin" "${MOUSE_GEN}" mouse_hand
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/../tools/build_mouse.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../../media/handCursor.png" "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" VERBATIM)
add_custom_command(OUTPUT "${EFFECTS_DIGITS_GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/effects_digits_16.idx" "${EFFECTS_DIGITS_GEN}" effects_digits
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/effects_digits_16.idx" VERBATIM)
add_custom_command(OUTPUT "${GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_tiles.idx" "${GEN}" gem_tiles
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_tiles.idx" VERBATIM)
add_custom_command(OUTPUT "${PALETTE_GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_palette.bin" "${PALETTE_GEN}" game_palette
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_palette.bin" VERBATIM)
add_custom_command(OUTPUT "${TITLE_PALETTE_GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/title_palette.bin" "${TITLE_PALETTE_GEN}" title_palette
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/title_palette.bin" VERBATIM)
add_custom_command(OUTPUT "${SELECTOR_GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_selector_32.idx" "${SELECTOR_GEN}" gem_selector
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_selector_32.idx" VERBATIM)
add_custom_command(OUTPUT "${SCENE_GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_scene.rle" "${SCENE_GEN}" game_scene_rle
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_scene.rle" VERBATIM)
add_custom_command(OUTPUT "${TITLE_SCENE_GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/title_scene.rle" "${TITLE_SCENE_GEN}" title_scene_rle
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/title_scene.rle" VERBATIM)
add_custom_command(OUTPUT "${GEMS_GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_gems_24.idx" "${GEMS_GEN}" gem_sprites
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_gems_24.idx" VERBATIM)
add_custom_command(OUTPUT "${SPRITES_GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_gems_32.idx" "${SPRITES_GEN}" sprite_patterns
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/game_gems_32.idx" VERBATIM)
add_custom_command(OUTPUT "${TITLE_GEMS_GEN}"
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/title_gems_32.idx" "${TITLE_GEMS_GEN}" title_gems
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/bin2c.mjs" "${CMAKE_CURRENT_SOURCE_DIR}/../generated/title_gems_32.idx" VERBATIM)
add_custom_command(OUTPUT "${OUT}"
  COMMAND "${MOS_CLANG}" -Oz -mcpu=mos65c02 -T "${SRC}/link3000.ld" -mlto-zp=157 -DVERA_BASE=0xC200
          -I "${CMAKE_CURRENT_BINARY_DIR}" -o "${OUT}" "${SRC}/main.c" "${SRC}/board.c" "${SRC}/effects.c" "${SRC}/sound.c" "${SRC}/pcm_feed.S" "${SRC}/music.c" "${SRC}/psg_music.c" "${SRC}/music_aux.S" "${SRC}/mouse.S" "${SRC}/mli.s"
  DEPENDS "${GEN}" "${PALETTE_GEN}" "${SELECTOR_GEN}" "${GEMS_GEN}" "${SPRITES_GEN}" "${SRC}/main.c" "${SRC}/mouse.S" "${SRC}/mouse.h" "${SRC}/board.c" "${SRC}/mli.s" "${SRC}/board.h" "${SRC}/frame_pump.h" "${SRC}/apple2e.h" "${SRC}/link3000.ld"
  VERBATIM)
add_custom_command(OUTPUT "${OUT4}"
  COMMAND "${MOS_CLANG}" -Oz -mcpu=mos65c02 -T "${SRC}/link3000.ld" -mlto-zp=157 -DVERA_BASE=0xC400
          -I "${CMAKE_CURRENT_BINARY_DIR}" -o "${OUT4}" "${SRC}/main.c" "${SRC}/board.c" "${SRC}/effects.c" "${SRC}/sound.c" "${SRC}/pcm_feed.S" "${SRC}/music.c" "${SRC}/psg_music.c" "${SRC}/music_aux.S" "${SRC}/mouse.S" "${SRC}/mli.s"
  DEPENDS "${GEN}" "${PALETTE_GEN}" "${SELECTOR_GEN}" "${GEMS_GEN}" "${SPRITES_GEN}" "${SRC}/main.c" "${SRC}/mouse.S" "${SRC}/mouse.h" "${SRC}/board.c" "${SRC}/mli.s" "${SRC}/board.h" "${SRC}/frame_pump.h" "${SRC}/apple2e.h" "${SRC}/link3000.ld"
  VERBATIM)
add_custom_command(OUTPUT "${TITLE}"
  COMMAND "${MOS_CLANG}" -Oz -mcpu=mos65c02 -T "${SRC}/link3000.ld" -mlto-zp=157 -DVERA_BASE=0xC200
          -I "${CMAKE_CURRENT_BINARY_DIR}" -o "${TITLE}" "${SRC}/title.c" ${MENU_MOUSE}
  DEPENDS "${TITLE_PALETTE_GEN}" "${TITLE_GEMS_GEN}" "${SRC}/title.c" "${SRC}/apple2e.h" "${SRC}/link3000.ld" VERBATIM)
add_custom_command(OUTPUT "${TITLE4}"
  COMMAND "${MOS_CLANG}" -Oz -mcpu=mos65c02 -T "${SRC}/link3000.ld" -mlto-zp=157 -DVERA_BASE=0xC400
          -I "${CMAKE_CURRENT_BINARY_DIR}" -o "${TITLE4}" "${SRC}/title.c" ${MENU_MOUSE}
  DEPENDS "${TITLE_PALETTE_GEN}" "${TITLE_GEMS_GEN}" "${SRC}/title.c" "${SRC}/apple2e.h" "${SRC}/link3000.ld" VERBATIM)
add_custom_command(OUTPUT "${SYSTEM}"
  COMMAND "${MOS_CLANG}" -Oz -mcpu=mos65c02 -T "${SRC}/link2000.ld" -o "${SYSTEM}" "${SRC}/loader.c" "${SRC}/loader.s" "${SRC}/mli.s"
  DEPENDS "${SRC}/loader.c" "${SRC}/loader.s" "${SRC}/mli.s" "${SRC}/link2000.ld" VERBATIM)
add_custom_command(OUTPUT "${HOWTO}" COMMAND "${MOS_CLANG}" -Oz -mcpu=mos65c02 -T "${SRC}/link3000.ld" -DVERA_BASE=0xC200 -I "${CMAKE_CURRENT_BINARY_DIR}" -o "${HOWTO}" "${SRC}/menu_screen.c" ${MENU_MOUSE} DEPENDS "${TITLE_PALETTE_GEN}" "${SRC}/menu_screen.c" VERBATIM)
add_custom_command(OUTPUT "${HOWTO4}" COMMAND "${MOS_CLANG}" -Oz -mcpu=mos65c02 -T "${SRC}/link3000.ld" -DVERA_BASE=0xC400 -I "${CMAKE_CURRENT_BINARY_DIR}" -o "${HOWTO4}" "${SRC}/menu_screen.c" ${MENU_MOUSE} DEPENDS "${TITLE_PALETTE_GEN}" "${SRC}/menu_screen.c" VERBATIM)
add_custom_command(OUTPUT "${OPTION}" COMMAND "${MOS_CLANG}" -Oz -mcpu=mos65c02 -T "${SRC}/link3000.ld" -DVERA_BASE=0xC200 -DOPTIONS_SCREEN -I "${CMAKE_CURRENT_BINARY_DIR}" -o "${OPTION}" "${SRC}/menu_screen.c" ${MENU_MOUSE} DEPENDS "${TITLE_PALETTE_GEN}" "${SRC}/menu_screen.c" VERBATIM)
add_custom_command(OUTPUT "${OPTION4}" COMMAND "${MOS_CLANG}" -Oz -mcpu=mos65c02 -T "${SRC}/link3000.ld" -DVERA_BASE=0xC400 -DOPTIONS_SCREEN -I "${CMAKE_CURRENT_BINARY_DIR}" -o "${OPTION4}" "${SRC}/menu_screen.c" ${MENU_MOUSE} DEPENDS "${TITLE_PALETTE_GEN}" "${SRC}/menu_screen.c" VERBATIM)
foreach(IMAGE IN ITEMS "${OUT}" "${OUT4}")
  add_custom_command(OUTPUT "${IMAGE}" APPEND DEPENDS "${MOUSE_GEN}")
  add_custom_command(OUTPUT "${IMAGE}" APPEND DEPENDS "${LOADING_HEADER}" "${SRC}/loading.h")
  add_custom_command(OUTPUT "${IMAGE}" APPEND DEPENDS "${SRC}/effects.c" "${SRC}/effects.h" "${EFFECTS_DIGITS_GEN}" "${SRC}/sound.c" "${SRC}/sound.h" "${SRC}/pcm_feed.S" "${SRC}/music.c" "${SRC}/music.h" "${SRC}/psg_music.c" "${SRC}/music_aux.S")
endforeach()
foreach(IMAGE IN ITEMS "${TITLE}" "${TITLE4}" "${HOWTO}" "${HOWTO4}" "${OPTION}" "${OPTION4}")
  add_custom_command(OUTPUT "${IMAGE}" APPEND DEPENDS ${MENU_MOUSE} "${SRC}/menu_mouse.h" "${SRC}/mouse.h" "${MOUSE_GEN}")
endforeach()
foreach(IMAGE IN ITEMS "${OUT}" "${OUT4}" "${TITLE}" "${TITLE4}")
  add_custom_command(OUTPUT "${IMAGE}" APPEND DEPENDS "${SRC}/random_seed.h")
endforeach()
foreach(IMAGE IN ITEMS "${OUT}" "${OUT4}" "${SYSTEM}" "${HOWTO}" "${HOWTO4}" "${OPTION}" "${OPTION4}")
  add_custom_command(OUTPUT "${IMAGE}" APPEND DEPENDS "${SRC}/hiscore.h" "${SRC}/apple2e.h")
endforeach()
add_custom_target(freegemas ALL DEPENDS "${OUT}" "${OUT4}" "${TITLE}" "${TITLE4}" "${HOWTO}" "${HOWTO4}" "${OPTION}" "${OPTION4}" "${SYSTEM}")
foreach(INTRO_SLOT IN ITEMS 2 4)
  if(INTRO_SLOT EQUAL 2)
    set(INTRO_NAME intro)
    set(INTRO_BASE 0xC200)
  else()
    set(INTRO_NAME intro4)
    set(INTRO_BASE 0xC400)
  endif()
  add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/${INTRO_NAME}.bin"
    COMMAND "${MOS_CLANG}" -Oz -mcpu=mos65c02 -T "${SRC}/link3000.ld" -DVERA_BASE=${INTRO_BASE}
      -o "${CMAKE_BINARY_DIR}/${INTRO_NAME}.bin" "${SRC}/intro.c"
    DEPENDS "${SRC}/intro.c" "${SRC}/apple2e.h" "${SRC}/fm_probe.h" "${SRC}/random_seed.h" "${SRC}/link3000.ld" VERBATIM)
  add_custom_target(${INTRO_NAME} DEPENDS "${CMAKE_BINARY_DIR}/${INTRO_NAME}.bin")
  add_dependencies(freegemas ${INTRO_NAME})
endforeach()
add_custom_target(disk
  COMMAND node "${CMAKE_CURRENT_SOURCE_DIR}/../tools/build_sound.mjs"
  COMMAND python "${CMAKE_CURRENT_SOURCE_DIR}/../tools/build_music_pcm.py"
  COMMAND python "${CMAKE_CURRENT_SOURCE_DIR}/tools/build_hdv.py" --cadius "${CADIUS_EXECUTABLE}" --prodos-dir "${VERA_PRODOS_DIR}"
  DEPENDS freegemas "${CMAKE_CURRENT_SOURCE_DIR}/tools/build_hdv.py" "${CADIUS_EXECUTABLE}"
    "${VERA_PRODOS_DIR}/PRODOS#FF0000"
    "${VERA_PRODOS_DIR}/CLOCK.SYSTEM#FF0000"
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/..")
