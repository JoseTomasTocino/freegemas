project(freegemas_project)
cmake_minimum_required(VERSION 2.6)

include(FindPkgConfig)

pkg_search_module(SDL2 REQUIRED sdl2)
pkg_search_module(SDL2IMAGE REQUIRED SDL2_image>=2.0.0)
pkg_search_module(SDL2TTF REQUIRED SDL2_ttf>=2.0.0)
pkg_search_module(SDL2MIXER REQUIRED SDL2_mixer>=2.0.0)

# Append custom gettext path to CMAKE_PREFIX_PATH - only necessary on OS X.
if (CMAKE_HOST_APPLE)
    find_program(HOMEBREW_PROG brew)
    if (EXISTS ${HOMEBREW_PROG})
        execute_process(COMMAND ${HOMEBREW_PROG} --prefix gettext
            OUTPUT_STRIP_TRAILING_WHITESPACE
            OUTPUT_VARIABLE HOMEBREW_GETTEXT_PREFIX)
        list(APPEND CMAKE_PREFIX_PATH "${HOMEBREW_GETTEXT_PREFIX}")
    endif()

    find_path(LIBINTL_INCLUDE_DIRS
        NAMES libintl.h
        PATH_SUFFIXES gettext
    )

    find_library(LIBINTL_LIBRARIES
        NAMES intl libintl.a
    )
endif()



if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -pedantic -std=c++11 -O")
endif()

file(GLOB SOURCE_FILES
    ${PROJECT_SOURCE_DIR}/src/*.cpp
)

# MESSAGE(STATUS "SOURCE FILES: " ${SOURCE_FILES})

add_executable (freegemas
    ${SOURCE_FILES}
)
if (VITA)
	# DOLCESDK defines
	if(NOT DEFINED CMAKE_TOOLCHAIN_FILE)
		if(DEFINED ENV{DOLCESDK})
			set(CMAKE_TOOLCHAIN_FILE "$ENV{DOLCESDK}/share/dolce.toolchain.cmake" CACHE PATH "toolchain file")
		    else()
			message(FATAL_ERROR "Please define DOLCESDK to point to your SDK path!")
		    endif()
	endif()

	include("$ENV{DOLCESDK}/share/dolce.cmake" REQUIRED)

	# Project start
	set(VITA_APPNAME Freegemas)
	set(VITA_TITLEID "FGEM00001")
	set(VITA_VERSION "00.01")

	# Optional. You can specify more param.sfo flags this way.
	set(VITA_MKSFOEX_FLAGS "${VITA_MKSFOEX_FLAGS} -d PARENTAL_LEVEL=1")

	set(VITA_INCLUDE_DIR "$ENV{DOLCESDK}/arm-dolce-eabi/include/")
	set(SDL2_INCLUDE_DIR "$ENV{DOLCESDK}/arm-dolce-eabi/include/SDL2")
	set(PNG_INCLUDE_DIR "$ENV{DOLCESDK}/arm-dolce-eabi/include/libpng16")
	set(FLAC_INCLUDE_DIR "$ENV{DOLCESDK}/arm-dolce-eabi/include/FLAC")

	include_directories(${PROJECT_SOURCE_DIR}/include
		    ${VITA_INCLUDE_DIR}
		    ${SDL2_INCLUDE_DIR}
		    ${PNG_INCLUDE_DIR}
		    ${FLAC_INCLUDE_DIR}
	)

	target_link_libraries(freegemas
		SDL2_image
		SDL2_ttf
		SDL2_mixer
		SDL2
		jsoncpp
		stdc++
		pthread
		png16
		freetype
		vorbisfile
		vorbis
		ogg
		jpeg
		z
		m
		mikmod
		mpg123
		FLAC
		pib
		SceAppUtil_stub
		SceAudio_stub
		SceCommonDialog_stub
		SceCtrl_stub
		SceDisplay_stub
		SceDisplayUser_stub
		SceGxm_stub
		SceHid_stub
		SceSysmodule_stub
		SceTouch_stub
		SceMotion_stub
	)
	dolce_create_self(freegemas.self freegemas)

	dolce_create_vpk(freegemas.vpk ${VITA_TITLEID} freegemas.self
		    VERSION ${VITA_VERSION}
		    NAME ${VITA_APPNAME}
		    FILE platform/vita/sce_sys sce_sys
		    FILE media media
	)
ELSE()
include_directories(
    ${PROJECT_SOURCE_DIR}/include

    ${SDL2_INCLUDE_DIRS}
    ${SDL2IMAGE_INCLUDE_DIRS}
    ${SDL2TTF_INCLUDE_DIRS}
    ${SDL2MIXER_INCLUDE_DIRS}
    ${LIBINTL_INCLUDE_DIRS}
)

target_link_libraries(freegemas
  ${SDL2_LIBRARIES}
  ${SDL2IMAGE_LIBRARIES}
  ${SDL2TTF_LIBRARIES}
  ${SDL2MIXER_LIBRARIES}
  ${LIBINTL_LIBRARIES}
)

add_custom_target(
  link_media_folder
  COMMAND ln -nfs ${PROJECT_SOURCE_DIR}/media ${PROJECT_BINARY_DIR}/media
)

add_dependencies(
  freegemas
  link_media_folder
)
ENDIF()
