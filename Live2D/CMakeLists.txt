cmake_minimum_required(VERSION 3.16)

project(CharShizuku)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(SDK_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../ThirdParty/CubismSdkForNative-5-r.5)
set(CORE_PATH ${SDK_ROOT_PATH}/Core)
set(FRAMEWORK_PATH ${SDK_ROOT_PATH}/Framework)
set(COMMON_SRC_PATH ${SDK_ROOT_PATH}/Samples/Common)
set(STB_PATH ${SDK_ROOT_PATH}/Samples/OpenGL/thirdParty/stb)
set(SAMPLE_SRC_PATH ${SDK_ROOT_PATH}/Samples/OpenGL/Demo/proj.mac.cmake/src)
set(SAMPLE_SHADER_PATH ${SDK_ROOT_PATH}/Samples/OpenGL/Shaders/Standard)
set(FRAMEWORK_SHADER_PATH ${FRAMEWORK_PATH}/src/Rendering/OpenGL/Shaders/Standard)
set(SHIZUKU_RUNTIME_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../Assets/shizuku/runtime)

set(GLEW_INCLUDE_DIR /opt/homebrew/opt/glew/include)
set(GLEW_LIBRARY /opt/homebrew/opt/glew/lib/libGLEW.a)
set(GLFW_INCLUDE_DIR /opt/homebrew/opt/glfw/include)
set(GLFW_LIBRARY /opt/homebrew/opt/glfw/lib/libglfw.3.dylib)

find_package(OpenGL REQUIRED)

add_library(Live2DCubismCore STATIC IMPORTED)
execute_process(COMMAND uname -m COMMAND tr -d "\n" OUTPUT_VARIABLE ARCHITECTURE)
set_target_properties(Live2DCubismCore PROPERTIES
  IMPORTED_LOCATION ${CORE_PATH}/lib/macos/${ARCHITECTURE}/libLive2DCubismCore.a
  INTERFACE_INCLUDE_DIRECTORIES ${CORE_PATH}/include
)

set(FRAMEWORK_SOURCE OpenGL)
add_subdirectory(${FRAMEWORK_PATH} ${CMAKE_CURRENT_BINARY_DIR}/Framework)
target_compile_definitions(Framework PUBLIC CSM_TARGET_MAC_GL)
target_include_directories(Framework PUBLIC ${GLEW_INCLUDE_DIR})
target_link_libraries(Framework Live2DCubismCore ${GLEW_LIBRARY})

add_executable(CharShizuku
  ${COMMON_SRC_PATH}/CubismSampleViewMatrix_Common.cpp
  ${COMMON_SRC_PATH}/LAppAllocator_Common.cpp
  ${COMMON_SRC_PATH}/LAppModel_Common.cpp
  ${COMMON_SRC_PATH}/LAppSprite_Common.cpp
  ${COMMON_SRC_PATH}/LAppTextureManager_Common.cpp
  ${COMMON_SRC_PATH}/LAppView_Common.cpp
  ${COMMON_SRC_PATH}/LAppWavFileHandler_Common.cpp
  ${COMMON_SRC_PATH}/MouseActionManager_Common.cpp
  ${COMMON_SRC_PATH}/TouchManager_Common.cpp
  ${SAMPLE_SRC_PATH}/LAppDefine.cpp
  ${SAMPLE_SRC_PATH}/LAppPal.cpp
  ${SAMPLE_SRC_PATH}/LAppTextureManager.cpp
  ${SAMPLE_SRC_PATH}/CubismUserModelExtend.cpp
  ${SAMPLE_SRC_PATH}/MouseActionManager.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/src/ShizukuMain.cpp
)

target_include_directories(CharShizuku PRIVATE
  ${STB_PATH}
  ${GLEW_INCLUDE_DIR}
  ${GLFW_INCLUDE_DIR}
  ${COMMON_SRC_PATH}
  ${SAMPLE_SRC_PATH}
)

target_compile_definitions(CharShizuku PRIVATE CSM_MINIMUM_DEMO)

target_link_libraries(CharShizuku
  Framework
  ${GLFW_LIBRARY}
  ${GLEW_LIBRARY}
  ${OPENGL_LIBRARIES}
  "-framework Cocoa"
  "-framework IOKit"
  "-framework CoreVideo"
)

add_custom_command(
  TARGET CharShizuku
  POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_FILE_DIR:CharShizuku>/Resources/shizuku
  COMMAND ${CMAKE_COMMAND} -E copy_directory ${SHIZUKU_RUNTIME_PATH} $<TARGET_FILE_DIR:CharShizuku>/Resources/shizuku
  COMMAND ${CMAKE_COMMAND} -E copy_directory ${SAMPLE_SHADER_PATH} $<TARGET_FILE_DIR:CharShizuku>/SampleShaders
  COMMAND ${CMAKE_COMMAND} -E copy_directory ${FRAMEWORK_SHADER_PATH} $<TARGET_FILE_DIR:CharShizuku>/FrameworkShaders
)
