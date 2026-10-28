#include "napi/native_api.h"
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <cstdarg>
#include <string>
#include <pthread.h>
#include <dlfcn.h>
#include <unistd.h>

// OpenSPH NAPI Bridge - 通过 dlopen 在 Ability 进程中启动 OpenSPH
// 路径 B: wxWidgets (Qt backend) + Qt-OH 双层桥接
// opensph 是 PIE 可执行文件，可被 dlopen 加载并调用其 main()

// 简单文件日志（写入应用私有目录，便于调试）
static void logFile(const char* fmt, ...) {
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    FILE* f = fopen("/data/storage/el2/base/files/opensph_debug.log", "a");
    if (f) {
        fprintf(f, "%s\n", buf);
        fclose(f);
    }
    fprintf(stderr, "[OpenSPH] %s\n", buf);
}

static void* g_opensphHandle = nullptr;
static pthread_t g_opensphThread = 0;
static bool g_running = false;

static std::string getNativeLibDir() {
    // 优先使用环境变量
    const char* libDir = getenv("NATIVE_LIB_DIR");
    if (libDir) return std::string(libDir);

    // 通过 dladdr 定位自身库路径，从而找到同目录下的其他库
    Dl_info dlInfo;
    if (dladdr((void*)getNativeLibDir, &dlInfo) && dlInfo.dli_fname) {
        std::string path(dlInfo.dli_fname);
        size_t pos = path.rfind('/');
        if (pos != std::string::npos) {
            return path.substr(0, pos);
        }
    }

    // 兜底：鸿蒙应用原生库目录
    return std::string("/data/storage/el2/base/haps/entry/libs/arm64");
}

static void setupEnvironment() {
    std::string libDir = getNativeLibDir();

    // Qt-OH 环境变量 - 必须在加载 Qt 之前设置
    setenv("QT_QPA_PLATFORM", "ohos", 1);
    setenv("QT_PLUGIN_PATH", (libDir + "/plugins").c_str(), 1);
    // 注意：不使用 QT_QPA_FORCE_NATIVE_POPUPS。Qt-OH 对原生 popup 窗口支持不稳定，
    // 强制后反而导致菜单栏下拉无响应、右键菜单时好时坏。改用 Qt 默认自绘 popup 机制。

    // i18n: OpenSPH.mo catalog is copied to the app sandbox files dir by
    // EntryAbility (rawfile -> filesDir) before this bridge starts OpenSPH.
    setenv("OSPH_LANG_DIR", "/data/storage/el2/base/haps/entry/files", 1);
    setenv("OSPH_LANG", "zh_CN", 1);

    // 库搜索路径
    std::string ldPath = libDir;
    const char* existing = getenv("LD_LIBRARY_PATH");
    if (existing) {
        ldPath += ":";
        ldPath += existing;
    }
    setenv("LD_LIBRARY_PATH", ldPath.c_str(), 1);
}

// 线程函数 - 在独立线程中运行 OpenSPH main
static void* opensphThreadFunc(void* arg) {
    (void)arg;
    if (!g_opensphHandle) return nullptr;

    // 获取 main 函数地址
    int (*mainFunc)(int, char**) = (int (*)(int, char**))dlsym(g_opensphHandle, "main");
    if (!mainFunc) {
        return nullptr;
    }

    // 构造 argv
    static char arg0[] = "opensph";
    static char* argv[] = { arg0, nullptr };

    // 调用 main - 进入 wxWidgets 事件循环
    int result = mainFunc(1, argv);
    g_running = false;
    return (void*)(intptr_t)result;
}

// 启动 OpenSPH - 通过 dlopen 在当前进程中加载并运行
// 返回：0=成功, 正数=已在运行, 负数=失败(返回错误描述字符串)
static napi_value startOpenSPH(napi_env env, napi_callback_info info) {
    napi_value result;

    if (g_running) {
        napi_create_int32(env, 1, &result); // 已在运行
        return result;
    }

    setupEnvironment();

    std::string libDir = getNativeLibDir();
    logFile("libDir=%s", libDir.c_str());

    // 按依赖顺序预加载所有本地库（RTLD_GLOBAL 使符号全局可见）
    // 依赖树：系统库 < Qt6 基础库 < Qt6 GUI < wxWidgets
    const char* loadOrder[] = {
        // 基础第三方库
        "libicudata.so", "libicuuc.so", "libicui18n.so",
        "libz.so.1", "libstdc++.so.6", "libgcc_s.so.1",
        "libpng16.so", "libfreetype.so", "libfontconfig.so",
        "libexpat.so.1", "libbz2.so.1",
        "libbrotlidec.so.1", "libbrotlicommon.so.1",
        // Qt6 基础
        "libQt6Core.so", "libQt6Gui.so", "libQt6Widgets.so",
        "libQt6OpenGL.so", "libQt6OpenGLWidgets.so", "libQt6PrintSupport.so",
        "libQt6Test.so",
        // stub 库
        "libsvgstub.so", "libace_napi.z.so",
        // wxWidgets
        "libwx_baseu-3.3.so.2", "libwx_qtu_core-3.3.so.2",
        "libwx_qtu_aui-3.3.so.2", "libwx_qtu_propgrid-3.3.so.2",
        nullptr
    };

    std::string errorDetail;
    for (int i = 0; loadOrder[i]; i++) {
        std::string path = libDir + "/" + loadOrder[i];
        void* h = dlopen(path.c_str(), RTLD_NOW | RTLD_GLOBAL);
        if (!h) {
            const char* err = dlerror();
            logFile("preload %s: %s", loadOrder[i], err ? err : "unknown error");
            errorDetail += std::string(loadOrder[i]) + ": " + (err ? err : "?") + "; ";
        }
    }

    std::string binaryPath = libDir + "/libopensph.so";

    // dlopen 加载 opensph (PIE 可执行文件可作为共享库加载)
    g_opensphHandle = dlopen(binaryPath.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (!g_opensphHandle) {
        // 尝试不带 lib 前缀的名称
        binaryPath = libDir + "/opensph";
        g_opensphHandle = dlopen(binaryPath.c_str(), RTLD_NOW | RTLD_GLOBAL);
    }

    if (!g_opensphHandle) {
        const char* err = dlerror();
        logFile("dlopen failed: %s", err ? err : "unknown error");
        std::string fullMsg = std::string("dlopen failed: ") + (err ? err : "?") + std::string(" | preload: ") + errorDetail;
        napi_create_string_utf8(env, fullMsg.c_str(), NAPI_AUTO_LENGTH, &result); // 返回错误描述
        return result;
    }
    logFile("dlopen OK: %s", binaryPath.c_str());

    // 在新线程中运行 main（避免阻塞 UI 线程）
    g_running = true;
    int rc = pthread_create(&g_opensphThread, nullptr, opensphThreadFunc, nullptr);
    if (rc != 0) {
        g_running = false;
        napi_create_int32(env, -2, &result); // 线程创建失败
        return result;
    }

    pthread_detach(g_opensphThread);
    napi_create_int32(env, 0, &result);
    return result;
}

// 获取 OpenSPH 版本信息
static napi_value getVersion(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_string_utf8(env, "OpenSPH 0.4.1-ohos (wxQT + Qt-OH)", NAPI_AUTO_LENGTH, &result);
    return result;
}

// 获取构建信息
static napi_value getBuildInfo(napi_env env, napi_callback_info cb_info) {
    (void)cb_info;
    std::string buildInfo = "Architecture: ARM64 (aarch64)\n"
                        "wxWidgets: 3.3.2 (Qt backend)\n"
                        "Qt: 6.12.0 (Qt-OH)\n"
                        "Renderer: Software rasterizer\n"
                        "Platform: HarmonyOS NEXT\n"
                        "Launch: dlopen in Ability process";
    napi_value result;
    napi_create_string_utf8(env, buildInfo.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// 检查运行状态
static napi_value isRunning(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_get_boolean(env, g_running, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "startOpenSPH", nullptr, startOpenSPH, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getVersion", nullptr, getVersion, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getBuildInfo", nullptr, getBuildInfo, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "isRunning", nullptr, isRunning, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "opensoh_bridge",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterModule(void) {
    napi_module_register(&demoModule);
}
