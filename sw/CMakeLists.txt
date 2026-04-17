cmake_minimum_required(VERSION 3.16.3)
project(jpegencodersw)
set(CMAKE_CXX_STANDARD 23)
set(CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "-O3")
add_compile_definitions(DEBUG)

add_executable(${PROJECT_NAME} main.cpp)
add_executable(encode encode.cpp)
add_executable(huffman huffman.cpp)

add_executable(test_dct test_dct.cpp)