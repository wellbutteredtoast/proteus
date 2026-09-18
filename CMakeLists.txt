#
# Proteus Engine CMakeLists.txt
# SPDX-License-Identifier: GPLv3-only
#

cmake_minimum_required(VERSION 3.25)

get_filename_component(srcpath "${CMAKE_SOURCE_DIR}" REALPATH)
get_filename_component(binpath "${CMAKE_BINARY_DIR}" REALPATH)

if("${srcpath}" STREQUAL "${binpath}")
    message(FATAL_ERROR
    "In-tree / in-source builds are not supported. Delete all CMakeCache files and "
    "build in a dedicated directory."
    )
endif()

set(GRAPHICS_BACKEND "OpenGL" CACHE STRING "Graphics backend for Proteus")
set_property(CACHE GRAPHICS_BACKEND PROPERTY STRINGS OpenGL Vulkan Metal DX11)

set(_valid_backends OpenGL Vulkan Metal DX11)
if(NOT GRAPHICS_BACKEND IN_LIST _valid_backends)
    message(FATAL_ERROR "GRAPHICS_BACKEND must be one of: ${_valid_backends}")
endif()

# Off by default, very noisy...
option(PEDANTIC_COMPILING "Enables highest warning levels (/W4 or -Wpedantic)" OFF)

# Disabled by default since debug logs are... verbose, and there's lots of them
option(VERBOSE_LOGGING "Re-enables debug logs in Release builds" OFF)

project(
    proteus
    VERSION 0.0.1
    LANGUAGES C CXX
)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(PROTEUS_INSTALL "Generate install rules for Proteus" ${PROJECT_IS_TOP_LEVEL})

get_property(_is_multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(NOT _is_multi_config AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
        Debug Release RelWithDebInfo MinSizeRel)
endif()

#
# Checking what graphics backend we want, doing required linkage/pack finding
#
set(PROTEUS_BACKEND_OPENGL OFF)
set(PROTEUS_BACKEND_VULKAN OFF)
set(PROTEUS_BACKEND_METAL  OFF)
set(PROTEUS_BACKEND_DX11   OFF)
set(PROTEUS_BACKEND_LIBS   "")
 
if(GRAPHICS_BACKEND STREQUAL "OpenGL")
    find_package(OpenGL REQUIRED)
    set(PROTEUS_BACKEND_OPENGL ON)
    list(APPEND PROTEUS_BACKEND_LIBS OpenGL::GL)
 
elseif(GRAPHICS_BACKEND STREQUAL "Vulkan")
    if(APPLE)
        message(FATAL_ERROR "Cannot use Vulkan on macOS targets! (Try Metal or OpenGL)")
    endif()
 
    find_package(Vulkan REQUIRED)
    set(PROTEUS_BACKEND_VULKAN ON)
    list(APPEND PROTEUS_BACKEND_LIBS Vulkan::Vulkan)
 
    message(FATAL_ERROR "Not implemented.")
 
elseif(GRAPHICS_BACKEND STREQUAL "Metal")
    if(NOT APPLE)
        message(FATAL_ERROR "Cannot use Metal on non macOS targets!")
    endif()
 
    set(PROTEUS_BACKEND_METAL ON)
    list(APPEND PROTEUS_BACKEND_LIBS
        "-framework Metal" "-framework QuartzCore" "-framework Foundation")
 
    enable_language(OBJCXX)

    message(FATAL_ERROR "Not implemented.")
 
elseif(GRAPHICS_BACKEND STREQUAL "DX11")
    if(NOT WIN32)
        message(FATAL_ERROR "Non Windows hosts cannot build with DirectX!")
    endif()
 
    set(PROTEUS_BACKEND_DX11 ON)
    list(APPEND PROTEUS_BACKEND_LIBS d3d11 dxgi d3dcompiler)
 
    message(FATAL_ERROR "Not implemented.")
 
endif()

#
# Start fetching the dependencies we're gonna need
#
include(FetchContent)

FetchContent_Declare(
    glfw
    GIT_REPOSITORY https://github.com/glfw/glfw.git
    GIT_TAG 3.5.1
    GIT_SHALLOW TRUE
    SYSTEM
    FIND_PACKAGE_ARGS 3.5.1 NAMES glfw3

)

set(GLM_BUILD_TESTS OFF)

FetchContent_Declare(
    glm
    GIT_REPOSITORY    https://github.com/g-truc/glm.git
    GIT_TAG           1.0.1
    GIT_SHALLOW       TRUE
    SYSTEM
    FIND_PACKAGE_ARGS
)
 
FetchContent_MakeAvailable(glfw glm)

#
# Once dependencies are good, start collecting sources for Proteus
#
string(TOLOWER "${GRAPHICS_BACKEND}" _backend_dir)
 
file(GLOB_RECURSE PROTEUS_CORE_SOURCES CONFIGURE_DEPENDS
    "${PROJECT_SOURCE_DIR}/src/core/*.c"
    "${PROJECT_SOURCE_DIR}/src/core/*.cpp"
)
 
file(GLOB_RECURSE PROTEUS_BACKEND_SOURCES CONFIGURE_DEPENDS
    "${PROJECT_SOURCE_DIR}/src/backends/${_backend_dir}/*.c"
    "${PROJECT_SOURCE_DIR}/src/backends/${_backend_dir}/*.cpp"
)
 
file(GLOB_RECURSE PROTEUS_PUBLIC_HEADERS CONFIGURE_DEPENDS
    "${PROJECT_SOURCE_DIR}/include/proteus/*.h"
    "${PROJECT_SOURCE_DIR}/include/proteus/*.hpp"
)

#
# Metadata, what compiler was used, the date/time, git info, etc..
#
set(PROTEUS_GENERATED_INCLUDE_DIR "${PROJECT_BINARY_DIR}/generated/include")
 
set(PROTEUS_GIT_HASH   "unknown")
set(PROTEUS_GIT_BRANCH "unknown")
set(PROTEUS_GIT_DIRTY  OFF)
 
find_package(Git QUIET)
if(GIT_FOUND AND EXISTS "${PROJECT_SOURCE_DIR}/.git")
    execute_process(
        COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
        WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
        OUTPUT_VARIABLE _git_hash
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    execute_process(
        COMMAND ${GIT_EXECUTABLE} rev-parse --abbrev-ref HEAD
        WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
        OUTPUT_VARIABLE _git_branch
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    execute_process(
        COMMAND ${GIT_EXECUTABLE} status --porcelain --untracked-files=no
        WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
        OUTPUT_VARIABLE _git_status
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
 
    if(_git_hash)
        set(PROTEUS_GIT_HASH "${_git_hash}")
    endif()
    if(_git_branch)
        set(PROTEUS_GIT_BRANCH "${_git_branch}")
    endif()
    if(_git_status)
        set(PROTEUS_GIT_DIRTY ON)
    endif()
endif()
 
string(TIMESTAMP PROTEUS_BUILD_TIMESTAMP "%Y-%m-%dT%H:%M:%SZ" UTC)
 
configure_file(
    "${PROJECT_SOURCE_DIR}/cmake/build_info.h.in"
    "${PROTEUS_GENERATED_INCLUDE_DIR}/proteus/build_info.h"
    @ONLY
)

#
# Link stuff into the final library, grab the headers and make it look 
# good and proper, like a professional project
#
add_library(proteus)
add_library(proteus::proteus ALIAS proteus)
 
# PROTEUS_EXPORT / PROTEUS_NO_EXPORT macros for symbol visibility (DLLs etc.)
include(GenerateExportHeader)
generate_export_header(proteus
    BASE_NAME        PROTEUS
    EXPORT_FILE_NAME "${PROTEUS_GENERATED_INCLUDE_DIR}/proteus/export.h"
)
if(NOT BUILD_SHARED_LIBS)
    target_compile_definitions(proteus PUBLIC PROTEUS_STATIC_DEFINE)
endif()
 
target_sources(proteus
    PRIVATE
        ${PROTEUS_CORE_SOURCES}
        ${PROTEUS_BACKEND_SOURCES}
    PUBLIC
        FILE_SET HEADERS
        BASE_DIRS
            "${PROJECT_SOURCE_DIR}/include"
            "${PROTEUS_GENERATED_INCLUDE_DIR}"
        FILES
            ${PROTEUS_PUBLIC_HEADERS}
            "${PROTEUS_GENERATED_INCLUDE_DIR}/proteus/build_info.h"
            "${PROTEUS_GENERATED_INCLUDE_DIR}/proteus/export.h"
)
 
# Private headers can live next to the sources in src/
target_include_directories(proteus PRIVATE "${PROJECT_SOURCE_DIR}/src")
 
target_compile_features(proteus PUBLIC cxx_std_20)
 
set_target_properties(proteus PROPERTIES
    CXX_EXTENSIONS            OFF
    C_VISIBILITY_PRESET       hidden
    CXX_VISIBILITY_PRESET     hidden
    VISIBILITY_INLINES_HIDDEN ON
    VERSION                   ${PROJECT_VERSION}
    # Pre-1.0, treat every minor bump as ABI-breaking
    SOVERSION                 ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
)
 
# Debug logs: always on in Debug, and in any config when VERBOSE_LOGGING=ON.
# Use it in code as: #if PROTEUS_ENABLE_DEBUG_LOGS
target_compile_definitions(proteus PRIVATE
    PROTEUS_ENABLE_DEBUG_LOGS=$<OR:$<CONFIG:Debug>,$<BOOL:${VERBOSE_LOGGING}>>
)
 
if(PEDANTIC_COMPILING)
    if(MSVC)
        target_compile_options(proteus PRIVATE /W4 /permissive-)
    else()
        target_compile_options(proteus PRIVATE -Wall -Wextra -Wpedantic)
    endif()
endif()
 
target_link_libraries(proteus
    PUBLIC
        $<BUILD_INTERFACE:glm::glm>
    PRIVATE
        $<BUILD_INTERFACE:glfw>
        ${PROTEUS_BACKEND_LIBS}
)

#
# Install rules + package config, so consumers can do:
#   find_package(Proteus REQUIRED)
#   target_link_libraries(game PRIVATE proteus::proteus)
#
if(PROTEUS_INSTALL)
    include(GNUInstallDirs)
    include(CMakePackageConfigHelpers)
 
    set(PROTEUS_CMAKE_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/cmake/Proteus")
 
    # Destinations default to the GNUInstallDirs locations
    install(TARGETS proteus
        EXPORT ProteusTargets
        FILE_SET HEADERS
    )
 
    install(EXPORT ProteusTargets
        NAMESPACE   proteus::
        DESTINATION "${PROTEUS_CMAKE_INSTALL_DIR}"
    )
 
    configure_package_config_file(
        "${PROJECT_SOURCE_DIR}/cmake/ProteusConfig.cmake.in"
        "${PROJECT_BINARY_DIR}/ProteusConfig.cmake"
        INSTALL_DESTINATION "${PROTEUS_CMAKE_INSTALL_DIR}"
    )
 
    # Pre-1.0: 0.1.x is not compatible with 0.2.x
    write_basic_package_version_file(
        "${PROJECT_BINARY_DIR}/ProteusConfigVersion.cmake"
        COMPATIBILITY SameMinorVersion
    )
 
    install(FILES
        "${PROJECT_BINARY_DIR}/ProteusConfig.cmake"
        "${PROJECT_BINARY_DIR}/ProteusConfigVersion.cmake"
        DESTINATION "${PROTEUS_CMAKE_INSTALL_DIR}"
    )
endif()

message(STATUS "Proteus ${PROJECT_VERSION} | backend: ${GRAPHICS_BACKEND} | "
               "git: ${PROTEUS_GIT_HASH} (${PROTEUS_GIT_BRANCH})")