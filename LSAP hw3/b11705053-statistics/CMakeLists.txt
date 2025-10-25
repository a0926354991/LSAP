cmake_minimum_required(VERSION 3.13)
project(b11705053-statistics CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(b11705053-statistics
  src/main.cpp
  src/linreg.cpp
)

target_include_directories(b11705053-statistics PRIVATE include)
