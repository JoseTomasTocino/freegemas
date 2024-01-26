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

set(BUILD_STATIC_DEFAULT OFF)
if(WIN32 OR VITA OR PSP)
    set(BUILD_STATIC_DEFAULT ON)
endif()
option(BUILD_STATIC "Build a static binary" ${BUILD_STATIC_DEFAULT})

# Find libraries
include(FindPkgConfig)
pkg_search_module(SDL2 REQUIRED sdl2)
pkg_search_module(SDL2_IMAGE REQUIRED SDL2_image)
pkg_search_module(SDL2_MIXER REQUIRED SDL2_mixer)
pkg_search_module(SDL2_TTF REQUIRED SDL2_ttf)
pkg_search_module(JSONCPP REQUIRED jsoncpp)

# Link libraries
if(BUILD_STATIC)
    set(CMAKE_CXX_FLAGS "-static ${CMAKE_CXX_FLAGS}")
    target_link_libraries(freegemas PRIVATE
        ${SDL2_STATIC_LIBRARIES}
        ${SDL2_IMAGE_STATIC_LIBRARIES}
        ${SDL2_MIXER_STATIC_LIBRARIES}
        ${SDL2_TTF_STATIC_LIBRARIES}
        ${JSONCPP_STATIC_LIBRARIES}
    )
else()
    target_link_libraries(freegemas PRIVATE
        ${SDL2_LIBRARIES}
        ${SDL2_IMAGE_LIBRARIES}
        ${SDL2_MIXER_LIBRARIES}
        ${SDL2_TTF_LIBRARIES}
        ${JSONCPP_LIBRARIES}
    )
endif()

include_directories(
    ${PROJECT_SOURCE_DIR}/include
    ${SDL2_INCLUDE_DIRS}
    ${SDL2_IMAGE_INCLUDE_DIRS}
    ${SDL2_MIXER_INCLUDE_DIRS}
    ${SDL2_TTF_INCLUDE_DIRS}
    ${JSONCPP_INCLUDE_DIRS}
)

if(NOT VITA)
	add_custom_target(
		link_media_folder
		COMMAND ln -nfs ${PROJECT_SOURCE_DIR}/media ${PROJECT_BINARY_DIR}/media
	)

	add_dependencies(
		freegemas
		link_media_folder
	)
endif()

if (VITA)
	include("$ENV{VITASDK}/share/vita.cmake" REQUIRED)

	# Project start
	set(VITA_APPNAME Freegemas)
	set(VITA_TITLEID "FGEM00001")
	set(VITA_VERSION "22.02")

	# Optional. You can specify more param.sfo flags this way.
	set(VITA_MKSFOEX_FLAGS "${VITA_MKSFOEX_FLAGS} -d PARENTAL_LEVEL=1")

	vita_create_self(freegemas.self freegemas)

	vita_create_vpk(freegemas.vpk ${VITA_TITLEID} freegemas.self
		    VERSION ${VITA_VERSION}
		    NAME ${VITA_APPNAME}
		    FILE platform/vita/sce_sys sce_sys
		    FILE media media
	)
ELSEIF(WIN32)
	# Nothing to do
ELSE()
	install(TARGETS freegemas DESTINATION bin)
	install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/media DESTINATION share/freegemas)
	install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/platform/unix/freegemas.desktop DESTINATION share/applications)
	install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/platform/unix/icons/64x64/freegemas.png DESTINATION share/icons/hicolor/64x64/apps)
	install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/README.md DESTINATION share/doc/freegemas)
ENDIF()
