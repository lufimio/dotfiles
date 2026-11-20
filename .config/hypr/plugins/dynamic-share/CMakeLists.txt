cmake_minimum_required(VERSION 3.25)
project(hypr_dynamic_share VERSION 0.3.1 LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED IMPORTED_TARGET hyprland=0.57.2)
pkg_check_modules(LUA REQUIRED IMPORTED_TARGET lua5.5)
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)
pkg_check_modules(PANGO REQUIRED IMPORTED_TARGET pangocairo)

add_library(dynamic_share_policy STATIC src/SourcePolicy.cpp)
set_target_properties(dynamic_share_policy PROPERTIES POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN YES)
target_include_directories(dynamic_share_policy PUBLIC src)
target_compile_options(dynamic_share_policy PRIVATE -Wall -Wextra -Wpedantic)

add_library(dynamic_share_placeholder STATIC src/Placeholder.cpp)
set_target_properties(dynamic_share_placeholder PROPERTIES POSITION_INDEPENDENT_CODE ON CXX_VISIBILITY_PRESET hidden)
target_include_directories(dynamic_share_placeholder PUBLIC src)
target_link_libraries(dynamic_share_placeholder PUBLIC PkgConfig::PANGO)

pkg_get_variable(WAYLAND_PROTOCOLS wayland-protocols pkgdatadir)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
set(XDG_SHELL_XML "${WAYLAND_PROTOCOLS}/stable/xdg-shell/xdg-shell.xml")
add_custom_command(OUTPUT xdg-shell-client-protocol.h
    COMMAND "${WAYLAND_SCANNER}" client-header "${XDG_SHELL_XML}" "${CMAKE_CURRENT_BINARY_DIR}/xdg-shell-client-protocol.h"
    DEPENDS "${XDG_SHELL_XML}")
add_custom_command(OUTPUT xdg-shell-protocol.c
    COMMAND "${WAYLAND_SCANNER}" private-code "${XDG_SHELL_XML}" "${CMAKE_CURRENT_BINARY_DIR}/xdg-shell-protocol.c"
    DEPENDS "${XDG_SHELL_XML}")
add_executable(dynamic_share_anchor src/Anchor.cpp xdg-shell-protocol.c xdg-shell-client-protocol.h)
target_include_directories(dynamic_share_anchor PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(dynamic_share_anchor PRIVATE PkgConfig::WAYLAND_CLIENT)
target_compile_options(dynamic_share_anchor PRIVATE -Wall -Wextra)
set_target_properties(dynamic_share_anchor PROPERTIES OUTPUT_NAME "dynamic-share-anchor")

add_library(dynamic_share MODULE src/Plugin.cpp src/CaptureBridge.cpp src/Selection.cpp src/Indicator.cpp src/IndicatorConfig.cpp)
add_dependencies(dynamic_share dynamic_share_anchor)
target_link_libraries(dynamic_share PRIVATE dynamic_share_policy dynamic_share_placeholder PkgConfig::HYPRLAND PkgConfig::LUA)
target_compile_definitions(dynamic_share PRIVATE DYNAMIC_SHARE_VERSION="${PROJECT_VERSION}-experimental")
target_compile_options(dynamic_share PRIVATE -Wall -Wextra)
if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_compile_options(dynamic_share PRIVATE -fno-gnu-unique)
endif()
# Hyprland's inline manager globals must interpose with the compositor, not
# become private null copies. Keep private implementation state internal.
set_target_properties(dynamic_share PROPERTIES PREFIX "" OUTPUT_NAME "dynamic-share"
    CXX_VISIBILITY_PRESET default VISIBILITY_INLINES_HIDDEN YES)
# Building never loads, installs, or replaces any running component.
