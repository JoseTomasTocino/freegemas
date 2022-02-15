project(freegemas_project)
cmake_minimum_required(VERSION 3.0)

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

if(WIN32)
	add_executable (freegemas WIN32
		${SOURCE_FILES}
		${CMAKE_CURRENT_SOURCE_DIR}/platform/windows/appicon.rc
	)
else()
	add_executable (freegemas
		${SOURCE_FILES}
	)
endif()

if (VITA)
	# VITASDK defines
	if(NOT DEFINED CMAKE_TOOLCHAIN_FILE)
		if(DEFINED ENV{VITASDK})
			set(CMAKE_TOOLCHAIN_FILE "$ENV{VITASDK}/share/vita.toolchain.cmake" CACHE PATH "toolchain file")
		    else()
			message(FATAL_ERROR "Please define VITASDK to point to your SDK path!")
		    endif()
	endif()

	include("$ENV{VITASDK}/share/vita.cmake" REQUIRED)

	# Project start
	set(VITA_APPNAME Freegemas)
	set(VITA_TITLEID "FGEM00001")
	set(VITA_VERSION "01.00")

	# Optional. You can specify more param.sfo flags this way.
	set(VITA_MKSFOEX_FLAGS "${VITA_MKSFOEX_FLAGS} -d PARENTAL_LEVEL=1")

	set(VITA_INCLUDE_DIR "$ENV{VITASDK}/arm-vita-eabi/include/")
	set(SDL2_INCLUDE_DIR "$ENV{VITASDK}/arm-vita-eabi/include/SDL2")
	set(WEBP_INCLUDE_DIR "$ENV{VITASDK}/arm-vita-eabi/include/webp")
	set(PNG_INCLUDE_DIR "$ENV{VITASDK}/arm-vita-eabi/include/libpng16")
	set(FLAC_INCLUDE_DIR "$ENV{VITASDK}/arm-vita-eabi/include/FLAC")
	set(JSON_INCLUDE_DIR "$ENV{VITASDK}/arm-vita-eabi/include/jsoncpp")

	include_directories(${PROJECT_SOURCE_DIR}/include
			${VITA_INCLUDE_DIR}
			${SDL2_INCLUDE_DIR}
			${WEBP_INCLUDE_DIR}
			${PNG_INCLUDE_DIR}
			${FLAC_INCLUDE_DIR}
			${JSON_INCLUDE_DIR}
	)

	target_link_libraries(freegemas
		SDL2_image
		SDL2_ttf
		SDL2_mixer
		SDL2
		jsoncpp
		stdc++
		webp
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
		SceAppUtil_stub
		SceAudio_stub
		SceCommonDialog_stub
		SceCtrl_stub
		SceDisplay_stub
		SceGxm_stub
		SceHid_stub
		SceSysmodule_stub
		SceTouch_stub
		SceMotion_stub
	)
	vita_create_self(freegemas.self freegemas)

	vita_create_vpk(freegemas.vpk ${VITA_TITLEID} freegemas.self
		    VERSION ${VITA_VERSION}
		    NAME ${VITA_APPNAME}
		    FILE platform/vita/sce_sys sce_sys
		    FILE media media
	)
ELSEIF(WIN32)
	option(BUILD_STATIC "Build a static binary (Windows only)" OFF)

	find_package(SDL2 CONFIG REQUIRED)
	find_package(sdl2-image CONFIG REQUIRED)
	find_package(sdl2-ttf CONFIG REQUIRED)
	find_package(sdl2-mixer CONFIG REQUIRED)
	find_package(jsoncpp CONFIG REQUIRED)

	target_link_libraries(freegemas PRIVATE
		SDL2::SDL2
		SDL2::SDL2main
		SDL2::SDL2_image
		SDL2::SDL2_ttf
		SDL2::SDL2_mixer
		jsoncpp_object
		JsonCpp::JsonCpp
	)

	target_include_directories(freegemas PRIVATE
		${PROJECT_SOURCE_DIR}/include

		${SDL2_INCLUDE_DIRS}
		${SDL2_IMAGE_INCLUDE_DIRS}
		${SDL2_TTF_INCLUDE_DIRS}
		${SDL2_MIXER_INCLUDE_DIRS}
		${JSONCPP_INCLUDE_DIRS}
	)

	if(BUILD_STATIC)
		if(MSVC)
			set(CompilerFlags
				CMAKE_CXX_FLAGS
				CMAKE_CXX_FLAGS_DEBUG
				CMAKE_CXX_FLAGS_RELEASE
				CMAKE_CXX_FLAGS_MINSIZEREL
				CMAKE_CXX_FLAGS_RELWITHDEBINFO
			)
			foreach(CompilerFlag ${CompilerFlags})
				string(REPLACE "/MD" "/MT" ${CompilerFlag} "${${CompilerFlag}}")
				set(${CompilerFlag} "${${CompilerFlag}}" CACHE STRING "msvc compiler flags" FORCE)
				message("MSVC flags: ${CompilerFlag}:${${CompilerFlag}}")
			endforeach()
		endif()

		target_link_libraries(freegemas PRIVATE
			SDL2::SDL2-static
			jsoncpp_static
			vorbis
			ogg
			Shlwapi
		)
	endif()
ELSE()
	find_package(PkgConfig REQUIRED)

	pkg_search_module(SDL2 REQUIRED sdl2)
	pkg_search_module(SDL2IMAGE REQUIRED SDL2_image>=2.0.0)
	pkg_search_module(SDL2TTF REQUIRED SDL2_ttf>=2.0.0)
	pkg_search_module(SDL2MIXER REQUIRED SDL2_mixer>=2.0.0)
	pkg_search_module(JSONCPP REQUIRED jsoncpp)

	include_directories(
		${PROJECT_SOURCE_DIR}/include

		${SDL2_INCLUDE_DIRS}
		${SDL2IMAGE_INCLUDE_DIRS}
		${SDL2TTF_INCLUDE_DIRS}
		${SDL2MIXER_INCLUDE_DIRS}
		${LIBINTL_INCLUDE_DIRS}
		${JSONCPP_INCLUDE_DIRS}
	)

	target_link_libraries(freegemas
	${SDL2_LIBRARIES}
	${SDL2IMAGE_LIBRARIES}
	${SDL2TTF_LIBRARIES}
	${SDL2MIXER_LIBRARIES}
	${LIBINTL_LIBRARIES}
	${JSONCPP_LIBRARIES}
	)

	add_custom_target(
		link_media_folder
		COMMAND ln -nfs ${PROJECT_SOURCE_DIR}/media ${PROJECT_BINARY_DIR}/media
	)

	add_dependencies(
		freegemas
		link_media_folder
	)

	install(TARGETS freegemas DESTINATION bin)
	install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/media DESTINATION share/freegemas)
	install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/platform/unix/freegemas.desktop DESTINATION share/applications)
	install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/platform/unix/icons/64x64/freegemas.png DESTINATION share/icons/hicolor/64x64/apps)
	install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/README.md DESTINATION share/doc/freegemas)
ENDIF()
