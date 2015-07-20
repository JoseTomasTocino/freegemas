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

include_directories(
    ${PROJECT_SOURCE_DIR}/include

    ${SDL2_INCLUDE_DIRS}
    ${SDL2IMAGE_INCLUDE_DIRS}
    ${SDL2TTF_INCLUDE_DIRS}
    ${SDL2MIXER_INCLUDE_DIRS}
    ${LIBINTL_INCLUDE_DIRS}
)

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
