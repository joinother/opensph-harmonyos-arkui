cmake_minimum_required(VERSION 3.4.1)
project(opensph_shell)

# OHOS NDK 路径（由 DevEco toolchain 提供）
if(NOT DEFINED OHOS_NDK_HOME AND DEFINED OHOS_SDK_NATIVE)
    set(OHOS_NDK_HOME ${OHOS_SDK_NATIVE})
endif()

# ---------------------------------------------------------------------------
# 1) wx/Qt 桥接（旧界面，保留可回退）
# ---------------------------------------------------------------------------
add_library(opensoh_bridge SHARED opensoh_bridge.cpp)
target_include_directories(opensoh_bridge PRIVATE ${OHOS_NDK_HOME}/sysroot/usr/include)
target_link_libraries(opensoh_bridge ${OHOS_NDK_HOME}/sysroot/usr/lib/aarch64-linux-ohos/libace_napi.z.so)

# ---------------------------------------------------------------------------
# 2) ArkTS 界面桥接（新界面）：只链接 core 静态库，不含 wx/Qt
# ---------------------------------------------------------------------------
set(OPENSPH_SRC "/Users/jiexuanyang/Doubao/chats/2026-08-27/new-chat/opensph-port/OpenSPH")
set(WX_SRC "/Users/jiexuanyang/Doubao/chats/2026-08-27/new-chat/opensph-port/wxWidgets")
add_library(opensph_ark SHARED ark_bridge.cpp
    ${OPENSPH_SRC}/gui/objects/VideoWriter.cpp
)
target_include_directories(opensph_ark PRIVATE
    ${OHOS_NDK_HOME}/sysroot/usr/include
    ${OPENSPH_SRC}
    ${OPENSPH_SRC}/core
    ${OPENSPH_SRC}/gui
    ${WX_SRC}/include
    ${WX_SRC}/build-ohos/lib/wx/include/aarch64-unknown-linux-ohos-qt-unicode-3.3
)
# 渲染热路径在 Debug(-O0) 下会慢 10 倍以上，显式开优化
target_compile_options(opensph_ark PRIVATE -O2 -ffast-math)
target_compile_definitions(opensph_ark PRIVATE __WXQT__ WXUSINGDLL _FILE_OFFSET_BITS=64 SPH_HAVE_OHOS_VIDEO)
target_link_libraries(opensph_ark
    ${OHOS_NDK_HOME}/sysroot/usr/lib/aarch64-linux-ohos/libace_napi.z.so
    ${OPENSPH_SRC}/build-ohos/core/libcore.a
    native_media_venc
    native_media_avmuxer
    native_media_codecbase
    native_media_core
    hilog_ndk.z
)
