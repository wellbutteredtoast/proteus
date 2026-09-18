#
# Proteus Engine CMakeLists.txt
# SPDX-License-Identifier: GPLv3-only
#

cmake_minimum_required(VERSION 3.38)

get_filename_component(srcpath "${CMAKE_SOURCE_DIR}" REALPATH)
get_filename_component(binpath "${CMAKE_BINARY_DIR}" REALPATH)

if("${srcpath}" STREQUAL "${binpath}")
    message(FATAL_ERROR
    "In-tree / in-source builds are not supported. Delete all CMakeCache files and "
    "build in a dedicated directory."
    )
endif()