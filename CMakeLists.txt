cmake_minimum_required(VERSION 3.16)
project(pokebrave-server CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug CACHE STRING "" FORCE)
endif()

add_compile_options(-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion)

add_library(pokebrave-battle STATIC
  src/battle/BattleJson.cpp
  src/battle/BattleWire.cpp
)
target_include_directories(pokebrave-battle PUBLIC src)

enable_testing()

add_executable(pokebrave-server-test
  tests/test_main.cpp
  tests/battle/wire_envelope_test.cpp
)
target_link_libraries(pokebrave-server-test PRIVATE pokebrave-battle)
target_include_directories(pokebrave-server-test PRIVATE tests)

add_test(NAME pokebrave-server-test COMMAND pokebrave-server-test)
