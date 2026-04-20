cmake_minimum_required(VERSION 3.16.3)
project(jpegencodersw)
set(CMAKE_CXX_STANDARD 23)
set(CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "-O3")
# add_compile_definitions(DEBUG)

#shared fixed-point header lives in the HDL BDPI directory
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../hdl/encoder/src/BDPI
)

add_executable(${PROJECT_NAME} tests/main.cpp)
add_executable(encode encode.cpp)

add_executable(encode_bitaccurate encode_bitaccurate.cpp)

add_executable(test_dct tests/test_dct.cpp)