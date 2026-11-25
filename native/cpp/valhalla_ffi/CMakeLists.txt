cmake_minimum_required(VERSION 3.22)
project(karta_valhalla_ffi LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Valhalla QUIET)

add_library(karta_valhalla_ffi SHARED
    src/karta_valhalla_ffi.cpp
)

target_include_directories(karta_valhalla_ffi
    PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
)

if(Valhalla_FOUND)
    target_compile_definitions(karta_valhalla_ffi PRIVATE KARTA_HAS_LIBVALHALLA=1)
    target_link_libraries(karta_valhalla_ffi PRIVATE Valhalla::valhalla)
endif()
