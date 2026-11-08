cmake_minimum_required(VERSION 3.5)
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

	# Homebrew's dylibs reference their own transitive dependencies through
	# @rpath (e.g. "@rpath/libwebp.7.dylib"), so BundleUtilities has to be told
	# where to look for them. Without these directories the @rpath entries stay
	# unresolved and fixup_bundle fails calling otool on the literal "@rpath/..."
	# string instead of a real file.
	set(FREEGEMAS_BUNDLE_LIBRARY_DIRS
		${SDL2_LIBRARY_DIRS}
		${SDL2_IMAGE_LIBRARY_DIRS}
		${SDL2_MIXER_LIBRARY_DIRS}
		${SDL2_TTF_LIBRARY_DIRS}
		${JSONCPP_LIBRARY_DIRS}
	)
	list(REMOVE_DUPLICATES FREEGEMAS_BUNDLE_LIBRARY_DIRS)

	install(CODE "
		include(BundleUtilities)

		# A dylib records the exact file name of its dependencies in its install
		# name, e.g. /opt/homebrew/opt/flac/lib/libFLAC.12.dylib. dyld has no
		# notion of compatibility versions for that lookup, so a minor-version
		# bump of a transitive Homebrew dependency (flac 1.4 -> 1.5, jpeg-xl
		# 0.10 -> 0.11) leaves the reference dangling even though the ABI is
		# compatible. Rather than hard-failing on a missing file, fall back to
		# the best installed sibling sharing the same base name. BundleUtilities
		# then copies it into Contents/Frameworks under the referenced name and
		# rewrites the load commands, so the bundle stays self-contained.
		macro(gp_resolve_item_override _ctx _item _exepath _dirs _resolved_item _resolved)
			if(NOT \${_resolved})
				string(REGEX REPLACE \"^@(rpath|loader_path|executable_path)/\" \"\" _item_path \"\${_item}\")
				get_filename_component(_item_name \"\${_item_path}\" NAME)
				string(REGEX REPLACE \"[.][0-9]+([.][0-9]+)*[.]dylib$\" \"\" _stem \"\${_item_name}\")

				set(_search_dirs \${_dirs})
				if(IS_ABSOLUTE \"\${_item_path}\")
					get_filename_component(_item_dir \"\${_item_path}\" DIRECTORY)
					list(INSERT _search_dirs 0 \"\${_item_dir}\")
				endif()

				set(_candidates \"\")
				foreach(_dir \${_search_dirs})
					file(GLOB _found \"\${_dir}/\${_stem}.*.dylib\")
					list(APPEND _candidates \${_found})
				endforeach()
				if(NOT _candidates)
					foreach(_dir \${_search_dirs})
						file(GLOB _found \"\${_dir}/\${_stem}*.dylib\")
						list(APPEND _candidates \${_found})
					endforeach()
				endif()

				if(_candidates)
					list(SORT _candidates)
					list(REVERSE _candidates)
					list(GET _candidates 0 _best)
					message(STATUS \"note: '\${_item}' not found; using '\${_best}' instead (compatible minor version)\")
					set(\${_resolved_item} \"\${_best}\")
					set(\${_resolved} 1)
				endif()
			endif()
		endmacro()

		set(freegemas_bundle_library_dirs ${FREEGEMAS_BUNDLE_LIBRARY_DIRS})
		fixup_bundle(\"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/freegemas.app\" \"\" \"\${freegemas_bundle_library_dirs}\")
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
