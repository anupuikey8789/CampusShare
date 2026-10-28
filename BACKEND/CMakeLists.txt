cmake_minimum_required(VERSION 3.20)
project(CampusShareBackend VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)
find_package(CURL REQUIRED)

set(CROW_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Crow/include")
set(ASIO_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/asio/include")
if(NOT EXISTS "${CROW_INCLUDE_DIR}/crow.h")
    message(FATAL_ERROR "Crow headers not found at ${CROW_INCLUDE_DIR}. Initialize the BACKEND/Crow submodule.")
endif()
if(NOT EXISTS "${ASIO_INCLUDE_DIR}/asio.hpp")
    message(FATAL_ERROR "Standalone Asio headers not found at ${ASIO_INCLUDE_DIR}. Initialize BACKEND/asio.")
endif()

add_executable(campusshare_backend main.cpp)
target_include_directories(campusshare_backend SYSTEM PRIVATE
    "${CROW_INCLUDE_DIR}"
    "${ASIO_INCLUDE_DIR}"
)
target_compile_definitions(campusshare_backend PRIVATE ASIO_STANDALONE)
target_link_libraries(campusshare_backend PRIVATE CURL::libcurl Threads::Threads)
if(WIN32)
    target_compile_definitions(campusshare_backend PRIVATE _WIN32_WINNT=0x0A00)
    target_link_libraries(campusshare_backend PRIVATE ws2_32 mswsock bcrypt)
endif()

if(MSVC)
    target_compile_options(campusshare_backend PRIVATE /W4 /permissive-)
else()
    target_compile_options(campusshare_backend PRIVATE -Wall -Wextra -Wpedantic)
endif()

install(TARGETS campusshare_backend RUNTIME DESTINATION bin)
