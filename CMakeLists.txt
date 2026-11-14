cmake_minimum_required(VERSION 3.28)

# Default the app binary to the oldest macOS that supports Apple Silicon.
# This must be set before project() to affect the compiler flags. Note that a
# bundle which embeds Homebrew libraries is still limited by their own
# deployment targets, so this only moves the floor for the app itself.
# Override with -DCMAKE_OSX_DEPLOYMENT_TARGET=<version> if needed.
if(APPLE AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version")
endif()

project(freegemas_project)

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

if(APPLE)
	file(GLOB_RECURSE FREEGEMAS_MEDIA_FILES "${PROJECT_SOURCE_DIR}/media/*")
	add_custom_target(freegemas_media ALL
		COMMAND ${CMAKE_COMMAND} -E copy_directory
			${PROJECT_SOURCE_DIR}/media
			${CMAKE_CURRENT_BINARY_DIR}/freegemas.app/Contents/Resources/media
		DEPENDS ${FREEGEMAS_MEDIA_FILES}
	)
	add_dependencies(freegemas freegemas_media)
	set(FREEGEMAS_ICNS "${CMAKE_CURRENT_BINARY_DIR}/AppIcon.icns")
	add_custom_command(
		OUTPUT ${FREEGEMAS_ICNS}
		COMMAND sh ${PROJECT_SOURCE_DIR}/platform/macos/create-icon.sh
			${PROJECT_SOURCE_DIR}/platform/macos/AppIcon.png
			${FREEGEMAS_ICNS}
		DEPENDS
			${PROJECT_SOURCE_DIR}/platform/macos/create-icon.sh
			${PROJECT_SOURCE_DIR}/platform/macos/AppIcon.png
		VERBATIM
	)
	add_custom_target(freegemas_icon DEPENDS ${FREEGEMAS_ICNS})
	add_dependencies(freegemas freegemas_icon)
	set_target_properties(freegemas PROPERTIES
		MACOSX_BUNDLE TRUE
		MACOSX_BUNDLE_BUNDLE_NAME "FreeGemas"
		MACOSX_BUNDLE_ICON_FILE "AppIcon.icns"
		MACOSX_BUNDLE_INFO_PLIST "${PROJECT_SOURCE_DIR}/platform/macos/Info.plist.in"
	)
endif()

set(BUILD_STATIC_DEFAULT OFF)
if(WIN32 OR VITA)
    set(BUILD_STATIC_DEFAULT ON)
endif()
option(BUILD_STATIC "Build a static binary" ${BUILD_STATIC_DEFAULT})

# Find libraries. SDL3 and its satellite libraries are built from the vendored
# submodules, so the executable has no SDL3 runtime dependency of its own.
include(vendor/include_dependencies.cmake)

# Link libraries
if(BUILD_STATIC)
    set(CMAKE_CXX_FLAGS "-static ${CMAKE_CXX_FLAGS}")
endif(BUILD_STATIC)

target_link_libraries(freegemas PRIVATE
	SDL3::SDL3-static
	SDL3_mixer::SDL3_mixer-static
	SDL3_ttf::SDL3_ttf-static
	jsoncpp_static
)

# The vendored targets publish their own include directories, so only the
# project headers need to be added here.
include_directories(
    ${PROJECT_SOURCE_DIR}/include
     ${PROJECT_SOURCE_DIR}/vendor/SDL/include
    ${PROJECT_SOURCE_DIR}/vendor/SDL_mixer/include
    ${PROJECT_SOURCE_DIR}/vendor/SDL_ttf/include
    ${PROJECT_SOURCE_DIR/vendor}/jsoncpp/include
)

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
ELSEIF(APPLE)
	install(TARGETS freegemas BUNDLE DESTINATION .)
	install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/media DESTINATION freegemas.app/Contents/Resources)
	install(FILES ${CMAKE_CURRENT_BINARY_DIR}/AppIcon.icns DESTINATION freegemas.app/Contents/Resources)

	# SDL3, SDL3_mixer, SDL3_ttf and jsoncpp are all built from the vendored
	# submodules as static libraries, so the bundle has no third-party dylibs to
	# collect: only the system frameworks recorded by the linker remain.
	#
	# The bundle still has to be signed. Apple Silicon refuses to map a page
	# whose signature does not match its contents, and every link invalidates
	# whatever signature the linker applied, so seal it here with an ad-hoc
	# identity. There are no nested dylibs to sign first.
	install(CODE "
		execute_process(
			COMMAND codesign --force --sign - \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/freegemas.app\"
			RESULT_VARIABLE _bundle_sign_result
			ERROR_QUIET
		)
		if(NOT _bundle_sign_result EQUAL 0)
			message(WARNING \"codesign failed for the app bundle\")
		endif()
	")
ELSE()
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
