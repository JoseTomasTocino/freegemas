project(freegemas_project)
cmake_minimum_required(VERSION 2.6)

INCLUDE(FindPkgConfig)

PKG_SEARCH_MODULE(SDL2 REQUIRED sdl2)
PKG_SEARCH_MODULE(SDL2IMAGE REQUIRED SDL2_image>=2.0.0)
PKG_SEARCH_MODULE(SDL2TTF REQUIRED SDL2_ttf>=2.0.0)
PKG_SEARCH_MODULE(SDL2MIXER REQUIRED SDL2_mixer>=2.0.0)

include_directories(
    ${PROJECT_SOURCE_DIR}/include

    ${SDL2_INCLUDE_DIRS}
    ${SDL2IMAGE_INCLUDE_DIRS}
    ${SDL2TTF_INCLUDE_DIRS}
    ${SDL2MIXER_INCLUDE_DIRS}
)

if(CMAKE_COMPILER_IS_GNUCXX)
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
)

add_custom_target(
  link_media_folder
  COMMAND ln -s ${PROJECT_SOURCE_DIR}/media ${PROJECT_BINARY_DIR}/media
)

add_dependencies(
  freegemas
  link_media_folder
)