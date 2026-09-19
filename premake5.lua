-- Proteus Engine Premake5 file
-- SPDX-License-Identifier: MPL-2.0
--

require("ninja")
require("os")

local ROOT          = _MAIN_SCRIPT_DIR
local DEPS          = ROOT .. "/Dependencies"
local BUILD_DIR     = ROOT .. "/Build"
local GLFW_SRC      = DEPS .. "/glfw"
local GLFW_BUILD    = BUILD_DIR .. "/glfw"
local IMGUI_SRC     = DEPS .. "/imgui"
 

--[[
#1 -> This is where GLFW gets built, despite using premake we shell out to
      CMake here, we may also do this for other deps down the line but idk.
]]
local function glfw_lib_path()
    if os.target() == "windows" then
        return GLFW_BUILD .. "/src/Release/glfw3.lib"
    else
        return GLFW_BUILD .. "/src/libglfw3.a"
    end
end
 
local function build_glfw()
    if os.isfile(glfw_lib_path()) then
        print("[premake] glfw already built, skipping")
        return
    end
 
    print("[premake] configuring + building glfw via cmake...")
    os.mkdir(GLFW_BUILD)
 
    local configure = string.format(
        'cmake -S "%s" -B "%s" -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF -DCMAKE_BUILD_TYPE=Release',
        GLFW_SRC, GLFW_BUILD
    )
    local build = string.format('cmake --build "%s" --config Release', GLFW_BUILD)
 
    if os.execute(configure) ~= true then
        error("glfw cmake configure failed — check that cmake is on PATH")
    end
    if os.execute(build) ~= true then
        error("glfw cmake build failed")
    end
end
 
build_glfw()

workspace "Proteus"
    configurations { "Debug", "Release" }
    startproject "Proteus"
 
    filter "configurations:Debug"
        symbols "On"
        defines { "PROTEUS_DEBUG" }
 
    filter "configurations:Release"
        optimize "On"
        defines { "PROTEUS_RELEASE" }
 
    filter {}
 
project "ImGui"
    kind "StaticLib"
    language "C++"
    cppdialect "C++17"
    targetdir (BUILD_DIR .. "/bin/%{cfg.buildcfg}/%{prj.name}")
    objdir    (BUILD_DIR .. "/obj/%{cfg.buildcfg}/%{prj.name}")
 
    files {
        IMGUI_SRC .. "/*.cpp",
        IMGUI_SRC .. "/*.h",
        IMGUI_SRC .. "/backends/imgui_impl_glfw.cpp",
        IMGUI_SRC .. "/backends/imgui_impl_glfw.h",
        IMGUI_SRC .. "/backends/imgui_impl_opengl3.cpp",
        IMGUI_SRC .. "/backends/imgui_impl_opengl3.h",
    }
 
    includedirs {
        IMGUI_SRC,
        IMGUI_SRC .. "/backends",
        GLFW_SRC .. "/include",
    }
 
-- glob-collected from Engine/Source + Engine/Include
project "Proteus"
    kind "ConsoleApp"
    language "C++"
    cppdialect "C++20"
    targetdir (BUILD_DIR .. "/bin/%{cfg.buildcfg}/%{prj.name}")
    objdir    (BUILD_DIR .. "/obj/%{cfg.buildcfg}/%{prj.name}")
 
    files {
        "Engine/Source/**.cpp",
        "Engine/Source/**.c",
        "Engine/Include/**.h",
        "Engine/Include/**.hpp",
    }
 
    includedirs {
        "Engine/Include",
        IMGUI_SRC,
        IMGUI_SRC .. "/backends",
        GLFW_SRC .. "/include",
    }
 
    libdirs {
        GLFW_BUILD .. "/src",
    }
 
    links { "ImGui" }
 
    filter "system:macosx"
        links {
            "glfw3",
            "Cocoa.framework",
            "IOKit.framework",
            "CoreVideo.framework",
            "OpenGL.framework",
        }
 
    filter "system:linux"
        links { "glfw3", "GL", "X11", "pthread", "dl" }
 
    filter "system:windows"
        links { "glfw3", "opengl32" }
 
    filter {}
