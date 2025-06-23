cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)


# === SDL3 动态库配置 ===
set(SDL3_DLL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../lib")

# 根据架构选择对应 DLL
if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64" OR CMAKE_VS_PLATFORM_NAME STREQUAL "ARM64")
    set(SDL3_DLL_SOURCE_PATH "${SDL3_DLL_DIR}/arm64/SDL3.dll")
    message(STATUS "Building for ARM64 architecture")
elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(SDL3_DLL_SOURCE_PATH "${SDL3_DLL_DIR}/x64/SDL3.dll")
    message(STATUS "Building for x64 architecture")
else()
    set(SDL3_DLL_SOURCE_PATH "${SDL3_DLL_DIR}/x86/SDL3.dll")
    message(STATUS "Building for x86 architecture")
endif()

# 添加构建后复制指令
add_custom_command(
        TARGET ${BINARY_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
        "${SDL3_DLL_SOURCE_PATH}"
        "$<TARGET_FILE_DIR:${BINARY_NAME}>/SDL3.dll"
        COMMENT "Copying SDL3.dll for ${CMAKE_SYSTEM_PROCESSOR}"
)


# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
