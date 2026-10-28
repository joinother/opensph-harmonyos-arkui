// ArkTS 界面桥接模块（M0）：把 C++ 计算内核的最小信息暴露给 ArkUI。
// 只依赖 core（无 wx / 无 Qt），后续里程碑再叠加节点图、属性、渲染与运行控制。
#include <napi/native_api.h>

#include <cstdio>
#include <algorithm>
#include <cmath>
#include <atomic>
#include <chrono>
#include <thread>
#include <mutex>
#include <memory>
#include <string>
#include <vector>
#include <map>
#include <cstdlib>
#include <cstdio>
#include <algorithm>
#include <cmath>
#include <atomic>
#include <chrono>
#include <thread>
#include <mutex>
#include <memory>

#include "gui/objects/Bitmap.h"
#include "gui/objects/Color.h"
#include "gui/objects/VideoWriter.h"
#include "io/Path.h"
#include "run/Job.h"
#include "run/Config.h"
#include <hilog/log.h>
#include "run/Node.h"
#include "run/IRun.h"
#include "run/VirtualSettings.h"
#include "objects/utility/EnumMap.h"
#include "run/jobs/GeometryJobs.h"
#include "run/jobs/InitialConditionJobs.h"
#include "run/jobs/IoJobs.h"
#include "run/jobs/MaterialJobs.h"
#include "run/jobs/ParticleJobs.h"
#include "run/jobs/SimulationJobs.h"

// 采样缓存：避免每帧重新 evaluate() 节点
static std::map<int, std::vector<float>> g_splatCache;
static std::map<int, bool> g_splatDirty;


using namespace Sph;

// ---------------------------------------------------------------------------
// C++ 侧点云光栅化：Canvas 2D 每帧绘制成本太高（实测 1333 点约 19ms、
// 4000 点会卡死），把 splat 放到 C++ 里做，一帧计算出 RGBA 缓冲交给 ArkTS
// 转成 PixelMap 显示，可支撑数千点 60fps。
// ---------------------------------------------------------------------------
static void splatPoints(const std::vector<float>& pts,
    const float yaw,
    const float pitch,
    const int W,
    const int H,
    std::vector<uint8_t>& out) {
    out.assign(size_t(W) * size_t(H) * 4, 0);
    // 背景
    for (size_t i = 0; i < out.size(); i += 4) {
        out[i] = 16;
        out[i + 1] = 20;
        out[i + 2] = 24;
        out[i + 3] = 255;
    }
    const size_t n = pts.size() / 3;
    if (n == 0) {
        return;
    }
    double minx = 1e300, miny = 1e300, minz = 1e300;
    double maxx = -1e300, maxy = -1e300, maxz = -1e300;
    for (size_t i = 0; i + 2 < pts.size(); i += 3) {
        minx = std::min<double>(minx, pts[i]);
        miny = std::min<double>(miny, pts[i + 1]);
        minz = std::min<double>(minz, pts[i + 2]);
        maxx = std::max<double>(maxx, pts[i]);
        maxy = std::max<double>(maxy, pts[i + 1]);
        maxz = std::max<double>(maxz, pts[i + 2]);
    }
    const double cx = 0.5 * (minx + maxx);
    const double cy = 0.5 * (miny + maxy);
    const double cz = 0.5 * (minz + maxz);
    double radius = 0;
    for (size_t i = 0; i + 2 < pts.size(); i += 3) {
        const double dx = pts[i] - cx, dy = pts[i + 1] - cy, dz = pts[i + 2] - cz;
        radius = std::max(radius, std::sqrt(dx * dx + dy * dy + dz * dz));
    }
    if (radius <= 0) {
        radius = 1;
    }
    const double scale = double(std::min(W, H)) * 0.42 / radius;
    const double ca = std::cos(yaw), sa = std::sin(yaw);
    const double ct = std::cos(pitch), st = std::sin(pitch);
    // 光照方向（视觉上方偏右前）
    const double Lx = 0.42, Ly = -0.52, Lz = 0.74;
    const double Ln = std::sqrt(Lx * Lx + Ly * Ly + Lz * Lz);
    const double lx = Lx / Ln, ly = Ly / Ln, lz = Lz / Ln;

    struct Sample {
        float sx, sy, depth, rr;
    };
    std::vector<Sample> samples(n);
    for (size_t k = 0; k < n; ++k) {
        const double x0 = pts[k * 3] - cx, y0 = pts[k * 3 + 1] - cy, z0 = pts[k * 3 + 2] - cz;
        const double x1 = x0 * ca - y0 * sa;
        const double y1 = x0 * sa + y0 * ca;
        const double y2 = y1 * ct - z0 * st;
        const double z2 = y1 * st + z0 * ct;
        samples[k].sx = float(double(W) * 0.5 + x1 * scale);
        samples[k].sy = float(double(H) * 0.5 - z2 * scale);
        samples[k].depth = float(y2 / radius);
        samples[k].rr = float(std::sqrt(x0 * x0 + y0 * y0 + z0 * z0) / radius);
    }
    std::sort(samples.begin(), samples.end(), [](const Sample& a, const Sample& b) {
        return a.depth < b.depth;
    });

    const float baseR = std::max(1.5f, float(std::min(W, H)) * 0.0042f)
        * std::min(2.4f, std::max(1.0f, std::sqrt(1200.0f / float(n))));
    for (const Sample& sm : samples) {
        // 法线近似：屏幕空间中心指向该点（球/椭球精确）
        double nx = (sm.sx - double(W) * 0.5) / (scale * radius + 1e-6);
        double ny = (sm.sy - double(H) * 0.5) / (scale * radius + 1e-6);
        double nz = sm.depth;
        const double nn = std::sqrt(nx * nx + ny * ny + nz * nz) + 1e-9;
        nx /= nn;
        ny /= nn;
        nz /= nn;
        const double diff = std::max(0.0, nx * lx + ny * ly + nz * lz);
        double hx = lx, hy = ly, hz = lz + 1.0;
        const double hn = std::sqrt(hx * hx + hy * hy + hz * hz);
        const double spec = std::pow(std::max(0.0, (nx * hx + ny * hy + nz * hz) / hn), 16.0);
        const double dn = (sm.depth + 1.0) * 0.5;
        const double lum = std::min(1.0, 0.22 + 0.95 * diff + 0.35 * spec);
        const double t = std::min(1.0, double(sm.rr));
        double mr, mg, mb;
        if (t < 0.35) {
            const double u = t / 0.35;
            mr = 40 + 130 * u; mg = 10 + 30 * u; mb = 105 + 20 * u;
        } else if (t < 0.7) {
            const double u = (t - 0.35) / 0.35;
            mr = 170 + 75 * u; mg = 40 + 90 * u; mb = 125 - 55 * u;
        } else {
            const double u = (t - 0.7) / 0.3;
            mr = 245 + 10 * u; mg = 130 + 110 * u; mb = 70 + 120 * u;
        }
        const double cr = std::min(255.0, mr * lum + 240 * spec);
        const double cg = std::min(255.0, mg * lum + 240 * spec);
        const double cb = std::min(255.0, mb * lum + 230 * spec);
        const double alpha = 0.10 + 0.30 * dn + 0.30 * spec;
        const int ir = std::max(1, int(std::lround(baseR * (0.6f + 0.8f * dn))));
        const int px0 = int(std::lround(sm.sx));
        const int py0 = int(std::lround(sm.sy));
        for (int dy = -ir; dy <= ir; ++dy) {
            const int py = py0 + dy;
            if (py < 0 || py >= H) {
                continue;
            }
            for (int dx = -ir; dx <= ir; ++dx) {
                const int px = px0 + dx;
                if (px < 0 || px >= W) {
                    continue;
                }
                const double d2 = double(dx * dx + dy * dy);
                if (d2 > double(ir * ir)) {
                    continue;
                }
                const double w = (1.0 - std::sqrt(d2) / (ir + 1e-6)) * alpha;
                const size_t o = (size_t(py) * size_t(W) + size_t(px)) * 4;
                out[o] = uint8_t(std::min(255.0, out[o] + cr * w));
                out[o + 1] = uint8_t(std::min(255.0, out[o + 1] + cg * w));
                out[o + 2] = uint8_t(std::min(255.0, out[o + 2] + cb * w));
            }
        }
    }
}

namespace {

/// 输出一个有限浮点；NaN/Inf 一律写 0，避免产生非法 JSON
std::string jsonFloat(const double v) {
    if (!std::isfinite(v)) {
        return "0";
    }
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%.4g", v);
    return std::string(buf);
}

std::string jsonEscape(const String& s) {
    std::string out;
    CharString utf8 = s.toUtf8();
    for (const char* p = utf8.cstr(); p && *p; ++p) {
        const char c = *p;
        switch (c) {
        case '"':
            out += "\\\"";
            break;
        case '\\':
            out += "\\\\";
            break;
        case '\n':
            out += "\\n";
            break;
        default:
            out += c;
        }
    }
    return out;
}

/// Registers the core job families so the catalog is not empty. GUI-only jobs are
/// registered by the wx build; the ArkTS UI will get them through the same path later.
void registerCoreJobs() {
    static SphJob sSph("");
    static CollisionGeometrySetupJob sSetup("");
    static MonolithicBodyIc sIc("");
    static SaveFileJob sIo("");
    static BlockJob sBlock("");
    static MaterialJob sMat("");
    (void)sSph;
    (void)sSetup;
    (void)sIc;
    (void)sIo;
    (void)sBlock;
    (void)sMat;
}

std::string buildCatalogJson() {
    registerCoreJobs();
    std::string json = "[";
    bool first = true;
    for (const AutoPtr<IJobDesc>& desc : enumerateRegisteredJobs()) {
        if (!desc) {
            continue;
        }
        if (!first) {
            json += ",";
        }
        first = false;
        json += "{\"className\":\"" + jsonEscape(desc->className()) + "\"";
        json += ",\"category\":\"" + jsonEscape(desc->category()) + "\"";
        json += ",\"tooltip\":\"" + jsonEscape(desc->tooltip()) + "\"}";
    }
    json += "]";
    return json;
}

napi_value makeString(napi_env env, const std::string& text) {
    napi_value result;
    napi_create_string_utf8(env, text.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// ---------------------------------------------------------------------------
// 节点实例与设置读写（M2）
// ---------------------------------------------------------------------------
std::map<int, SharedPtr<JobNode>>& nodeRegistry() {
    static std::map<int, SharedPtr<JobNode>> registry;
    return registry;
}

int nextNodeHandle = 1;

std::string variantToJson(const IVirtualEntry::Value& value, IVirtualEntry::Type type) {
    switch (type) {
    case IVirtualEntry::Type::BOOL: {
        const bool b = value.get<bool>();
        return b ? "true" : "false";
    }
    case IVirtualEntry::Type::INT: {
        return std::to_string(value.get<int>());
    }
    case IVirtualEntry::Type::FLOAT: {
        char buf[64];
        std::snprintf(buf, sizeof(buf), "%.6g", double(value.get<Float>()));
        return std::string(buf);
    }
    case IVirtualEntry::Type::ENUM: {
        const EnumWrapper w = value.get<EnumWrapper>();
        return std::to_string(w.value);
    }
    case IVirtualEntry::Type::STRING: {
        return "\"" + jsonEscape(value.get<String>()) + "\"";
    }
    case IVirtualEntry::Type::VECTOR: {
        const Vector v = value.get<Vector>();
        char buf[128];
        std::snprintf(buf, sizeof(buf), "[%.6g,%.6g,%.6g]", double(v[0]), double(v[1]), double(v[2]));
        return std::string(buf);
    }
    case IVirtualEntry::Type::INTERVAL: {
        const Interval itv = value.get<Interval>();
        char buf[96];
        std::snprintf(buf, sizeof(buf), "[%.6g,%.6g]", double(itv.lower()), double(itv.upper()));
        return std::string(buf);
    }
    case IVirtualEntry::Type::PATH: {
        return "\"" + jsonEscape(value.get<Path>().string()) + "\"";
    }
    default:
        return "null";
    }
}

std::string typeName(IVirtualEntry::Type type) {
    switch (type) {
    case IVirtualEntry::Type::BOOL:
        return "bool";
    case IVirtualEntry::Type::INT:
        return "int";
    case IVirtualEntry::Type::FLOAT:
        return "float";
    case IVirtualEntry::Type::ENUM:
        return "enum";
    case IVirtualEntry::Type::STRING:
        return "string";
    case IVirtualEntry::Type::PATH:
        return "path";
    case IVirtualEntry::Type::VECTOR:
        return "vector";
    case IVirtualEntry::Type::INTERVAL:
        return "interval";
    default:
        return "other";
    }
}

class SettingsJsonProc : public VirtualSettings::IEntryProc {
private:
    std::vector<std::pair<std::string, std::vector<std::string>>>& categories;

public:
    explicit SettingsJsonProc(std::vector<std::pair<std::string, std::vector<std::string>>>& categories)
        : categories(categories) {}

    virtual void onCategory(const String& name) const override {
        categories.push_back(std::make_pair(jsonEscape(name), std::vector<std::string>()));
    }

    virtual void onEntry(const String& key, IVirtualEntry& entry) const override {
        const IVirtualEntry::Type type = entry.getType();
        if (type == IVirtualEntry::Type::EXTRA || categories.empty()) {
            return;
        }
        std::string e = "{\"key\":\"" + jsonEscape(key) + "\"";
        e += ",\"name\":\"" + jsonEscape(entry.getName()) + "\"";
        e += ",\"type\":\"" + typeName(type) + "\"";
        e += ",\"value\":" + variantToJson(entry.get(), type);
        e += ",\"enabled\":";
        e += entry.enabled() ? "true" : "false";
        const String tip = entry.getTooltip();
        if (tip.size() > 0) {
            e += ",\"tip\":\"" + jsonEscape(tip) + "\"";
        }
        if (type == IVirtualEntry::Type::ENUM) {
            const EnumWrapper w = entry.get().get<EnumWrapper>();
            e += ",\"options\":[";
            bool first = true;
            if (w.index) {
                for (const int id : EnumMap::getAll(w.index)) {
                    const EnumWrapper option(id, w.index);
                    if (!entry.isValid(option)) {
                        continue;
                    }
                    if (!first) {
                        e += ",";
                    }
                    first = false;
                    String label = EnumMap::toString(id, w.index);
                    label.replaceAll("_", " ");
                    e += "{\"value\":" + std::to_string(id);
                    e += ",\"label\":\"" + jsonEscape(label) + "\"}";
                }
            }
            e += "]";
        }
        e += "}";
        categories.back().second.push_back(e);
    }
};

class SetValueProc : public VirtualSettings::IEntryProc {
private:
    const String& targetKey;
    const String& rawValue;
    const String& valueType;
    bool& changed;

public:
    SetValueProc(const String& targetKey, const String& rawValue, const String& valueType, bool& changed)
        : targetKey(targetKey)
        , rawValue(rawValue)
        , valueType(valueType)
        , changed(changed) {}

    virtual void onCategory(const String&) const override {}

    virtual void onEntry(const String& key, IVirtualEntry& entry) const override {
        if (changed || key != targetKey) {
            return;
        }
        // 类型必须先匹配：直接调用 entry.set() 传入错误类型会触发内核断言并杀掉进程。
        const IVirtualEntry::Type entryType = entry.getType();
        const bool typeOk = (valueType == "bool" && entryType == IVirtualEntry::Type::BOOL) ||
                            (valueType == "int" && entryType == IVirtualEntry::Type::INT) ||
                            (valueType == "float" && (entryType == IVirtualEntry::Type::FLOAT ||
                                                         entryType == IVirtualEntry::Type::INT)) ||
                            (valueType == "enum" && entryType == IVirtualEntry::Type::ENUM) ||
                            (valueType == "vector" && entryType == IVirtualEntry::Type::VECTOR) ||
                            (valueType == "interval" && entryType == IVirtualEntry::Type::INTERVAL);
        if (!typeOk) {
            return;
        }
        try {
            if (valueType == "bool") {
                changed = entry.set(IVirtualEntry::Value(rawValue == "true"));
            } else if (valueType == "int") {
                changed = entry.set(IVirtualEntry::Value(std::atoi(rawValue.toUtf8().cstr())));
            } else if (valueType == "float") {
                changed = entry.set(IVirtualEntry::Value(Float(std::atof(rawValue.toUtf8().cstr()))));
            } else if (valueType == "vector") {
                Float xyz[3] = {0.f, 0.f, 0.f};
                const char* text = rawValue.toUtf8().cstr();
                std::sscanf(text, "%f,%f,%f", &xyz[0], &xyz[1], &xyz[2]);
                changed = entry.set(IVirtualEntry::Value(Vector(xyz[0], xyz[1], xyz[2])));
            } else if (valueType == "interval") {
                Float lo = 0.f, hi = 0.f;
                const char* text = rawValue.toUtf8().cstr();
                std::sscanf(text, "%f,%f", &lo, &hi);
                changed = entry.set(IVirtualEntry::Value(Interval(lo, hi)));
            } else if (valueType == "enum") {
                const EnumWrapper current = entry.get().get<EnumWrapper>();
                changed = entry.set(IVirtualEntry::Value(EnumWrapper(std::atoi(rawValue.toUtf8().cstr()), current.index)));
            }
        } catch (const std::exception&) {
            changed = false;
        }
    }
};

/// 预览用回调：不参与统计，也不真正跑模拟（shouldAbortRun 立即返回 true）。
struct PreviewCallbacks : public IRunCallbacks {
    virtual void onSetUp(const Storage&, Statistics&) override {}
    virtual void onTimeStep(const Storage&, Statistics&) override {}
    virtual bool shouldAbortRun() const override {
        return true;
    }
};

std::string previewJson(const int handle, const int maxPoints) {
    const auto it = nodeRegistry().find(handle);
    if (it == nodeRegistry().end()) {
        return "{\"error\":\"节点不存在\"}";
    }
    RawPtr<IJob> job = it->second->getJob();
    if (dynamic_cast<IRunJob*>(job.get())) {
        return "{\"error\":\"模拟节点暂不支持静态预览\"}";
    }

    RunSettings globals;
    PreviewCallbacks callbacks;
    try {
        job.get()->evaluate(globals, callbacks);
    } catch (const std::exception& e) {
        return "{\"error\":\"" + jsonEscape(String::fromUtf8(e.what())) + "\"}";
    }

    std::vector<float> points;
    std::string kind = "none";
    JobContext ctx = job.get()->getResult();

    if (SharedPtr<ParticleData> data = ctx.tryGetValue<ParticleData>()) {
        ArrayView<const Vector> r = data->storage.getValue<Vector>(QuantityId::POSITION);
        kind = "particles";
        const Size total = r.size();
        const Size step = total > Size(maxPoints) ? total / Size(maxPoints) : 1;
        for (Size i = 0; i < total; i += step) {
            points.push_back(float(r[i][0]));
            points.push_back(float(r[i][1]));
            points.push_back(float(r[i][2]));
            if (points.size() >= Size(maxPoints) * 3) {
                break;
            }
        }
    } else if (SharedPtr<IDomain> domain = ctx.tryGetValue<IDomain>()) {
        kind = "domain";
        const Box box = domain->getBoundingBox();
        {
            const Vector lo = box.lower();
            const Vector hi = box.upper();
            // 简单 LCG，保证每次预览结果一致
            unsigned long long state = 88172645463325252ull;
            auto nextRandom = [&state]() -> float {
                state = state * 6364136223846793005ull + 1442695040888963407ull;
                return float((state >> 33) & 0xFFFFFF) / float(0x1000000);
            };
            const int attempts = maxPoints * 12;
            for (int i = 0; i < attempts && int(points.size()) < maxPoints * 3; ++i) {
                const Vector v(lo[0] + (hi[0] - lo[0]) * nextRandom(),
                    lo[1] + (hi[1] - lo[1]) * nextRandom(),
                    lo[2] + (hi[2] - lo[2]) * nextRandom());
                if (domain->contains(v)) {
                    points.push_back(float(v[0]));
                    points.push_back(float(v[1]));
                    points.push_back(float(v[2]));
                }
            }
        }
    }

    // bounds
    float minv[3] = {0.f, 0.f, 0.f};
    float maxv[3] = {0.f, 0.f, 0.f};
    if (!points.empty()) {
        for (int k = 0; k < 3; ++k) {
            minv[k] = points[k];
            maxv[k] = points[k];
        }
        for (size_t i = 0; i + 2 < points.size(); i += 3) {
            for (int k = 0; k < 3; ++k) {
                minv[k] = std::min(minv[k], points[i + k]);
                maxv[k] = std::max(maxv[k], points[i + k]);
            }
        }
    }

    std::string json = "{\"kind\":\"" + kind + "\",\"count\":" + std::to_string(points.size() / 3);
    char buf[256];
    std::snprintf(buf, sizeof(buf), ",\"bounds\":[%.6g,%.6g,%.6g,%.6g,%.6g,%.6g]",
        double(minv[0]), double(minv[1]), double(minv[2]), double(maxv[0]), double(maxv[1]), double(maxv[2]));
    json += buf;
    json += ",\"points\":[";
    for (size_t i = 0; i < points.size(); ++i) {
        if (i > 0) {
            json += ",";
        }
        json += jsonFloat(double(points[i]));
    }
    json += "]}";
    return json;
}

// ---------------------------------------------------------------------------
// 离线视频导出：把节点采样点云按给定角度旋转、光栅化成 RGBA 帧，再编码成 MP4
// ---------------------------------------------------------------------------
std::string extractJsonNumber(const std::string& json, const std::string& key, const std::string& fallback) {
    const std::string pat = "\"" + key + "\"";
    size_t pos = json.find(pat);
    if (pos == std::string::npos) {
        return fallback;
    }
    pos = json.find(':', pos + pat.size());
    if (pos == std::string::npos) {
        return fallback;
    }
    pos++;
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\"')) {
        pos++;
    }
    size_t end = pos;
    while (end < json.size() && json[end] != ',' && json[end] != '}' && json[end] != '\"') {
        end++;
    }
    return json.substr(pos, end - pos);
}

std::string extractJsonString(const std::string& json, const std::string& key, const std::string& fallback) {
    const std::string pat = "\"" + key + "\"";
    size_t pos = json.find(pat);
    if (pos == std::string::npos) {
        return fallback;
    }
    pos = json.find(':', pos + pat.size());
    if (pos == std::string::npos) {
        return fallback;
    }
    pos = json.find('"', pos);
    if (pos == std::string::npos) {
        return fallback;
    }
    pos++;
    const size_t end = json.find('"', pos);
    if (end == std::string::npos) {
        return fallback;
    }
    return json.substr(pos, end - pos);
}

/// 采样节点输出点（与 previewPoints 相同口径），返回扁平坐标
bool sampleNodePoints(const int handle, const int maxPoints, std::vector<float>& points, std::string& error) {
    const auto it = nodeRegistry().find(handle);
    if (it == nodeRegistry().end()) {
        error = "节点不存在";
        return false;
    }
    RawPtr<IJob> job = it->second->getJob();
    if (dynamic_cast<IRunJob*>(job.get())) {
        error = "模拟节点暂不支持离线渲染";
        return false;
    }
    RunSettings globals;
    PreviewCallbacks callbacks;
    try {
        job.get()->evaluate(globals, callbacks);
    } catch (const std::exception& e) {
        error = String::fromUtf8(e.what()).toUtf8().cstr();
        return false;
    }
    JobContext ctx = job.get()->getResult();
    if (SharedPtr<ParticleData> data = ctx.tryGetValue<ParticleData>()) {
        ArrayView<const Vector> r = data->storage.getValue<Vector>(QuantityId::POSITION);
        const Size total = r.size();
        if (total == 0) {
            error = "节点没有输出粒子（检查输入是否连接）";
            return false;
        }
        const Size step = total > Size(maxPoints) ? total / Size(maxPoints) : 1;
        for (Size i = 0; i < total; i += step) {
            points.push_back(float(r[i][0]));
            points.push_back(float(r[i][1]));
            points.push_back(float(r[i][2]));
            if (points.size() >= Size(maxPoints) * 3) {
                break;
            }
        }
        return true;
    }
    if (SharedPtr<IDomain> domain = ctx.tryGetValue<IDomain>()) {
        const Box box = domain->getBoundingBox();
        const Vector lo = box.lower();
        const Vector hi = box.upper();
        unsigned long long state = 88172645463325252ull;
        auto nextRandom = [&state]() -> float {
            state = state * 6364136223846793005ull + 1442695040888963407ull;
            return float((state >> 33) & 0xFFFFFF) / float(0x1000000);
        };
        const int attempts = maxPoints * 12;
        for (int i = 0; i < attempts && int(points.size()) < maxPoints * 3; ++i) {
            const Vector v(lo[0] + (hi[0] - lo[0]) * nextRandom(),
                lo[1] + (hi[1] - lo[1]) * nextRandom(),
                lo[2] + (hi[2] - lo[2]) * nextRandom());
            if (domain->contains(v)) {
                points.push_back(float(v[0]));
                points.push_back(float(v[1]));
                points.push_back(float(v[2]));
            }
        }
        return !points.empty();
    }
    error = "节点没有可渲染的输出";
    return false;
}

struct VideoExportState {
    std::atomic<int> rendered{0};
    int total = 0;
    bool running = false;
    bool done = false;
    bool ok = false;
    std::string error;
    std::string path;
    std::mutex mutex;
};

VideoExportState& exportState() {
    static VideoExportState state;
    return state;
}

/// 实际执行导出的工作函数；options 为 JSON 文本，progress 每帧回调一次。
std::string runCloudExport(const int handle, const std::string& options, VideoExportState* state) {
    const int width = std::atoi(extractJsonNumber(options, "width", "1280").c_str());
    const int height = std::atoi(extractJsonNumber(options, "height", "720").c_str());
    const int fps = std::atoi(extractJsonNumber(options, "fps", "30").c_str());
    const int bitrate = std::atoi(extractJsonNumber(options, "bitrate", "8000000").c_str());
    const int frames = std::atoi(extractJsonNumber(options, "frames", "120").c_str());
    const int maxPoints = std::atoi(extractJsonNumber(options, "points", "8000").c_str());
    const std::string path = extractJsonString(options, "path", "");
    if (path.empty()) {
        return "{\"ok\":false,\"error\":\"缺少输出路径\"}";
    }

    std::vector<float> pts;
    std::string error;
    if (!sampleNodePoints(handle, maxPoints, pts, error)) {
        return "{\"ok\":false,\"error\":\"" + jsonEscape(String::fromUtf8(error.c_str())) + "\"}";
    }

    float lo[3] = {pts[0], pts[1], pts[2]};
    float hi[3] = {pts[0], pts[1], pts[2]};
    for (size_t i = 0; i + 2 < pts.size(); i += 3) {
        for (int k = 0; k < 3; ++k) {
            lo[k] = std::min(lo[k], pts[i + k]);
            hi[k] = std::max(hi[k], pts[i + k]);
        }
    }
    const float cx = (lo[0] + hi[0]) * 0.5f;
    const float cy = (lo[1] + hi[1]) * 0.5f;
    const float cz = (lo[2] + hi[2]) * 0.5f;
    float radius = 0.f;
    for (size_t i = 0; i + 2 < pts.size(); i += 3) {
        const float dx = pts[i] - cx, dy = pts[i + 1] - cy, dz = pts[i + 2] - cz;
        radius = std::max(radius, std::sqrt(dx * dx + dy * dy + dz * dz));
    }
    if (radius <= 0.f) {
        radius = 1.f;
    }

    // quality: 1=快速（1x），2=标准（1x，更多采样），3=高（2x 超采样）
    int aaFactor = 1;
    {
        const size_t qpos = options.find("\"quality\"");
        if (qpos != std::string::npos) {
            const size_t colon = options.find(':', qpos);
            if (colon != std::string::npos) {
                const int q = std::atoi(options.c_str() + colon + 1);
                aaFactor = (q >= 3) ? 2 : 1;
            }
        }
    }
    VideoParams params;
    params.width = width;
    params.height = height;
    params.fps = fps;
    params.bitrate = bitrate;
    VideoWriter writer;
    String openError;
    if (!writer.open(Path(String::fromUtf8(path.c_str())), params, openError)) {
        return "{\"ok\":false,\"error\":\"" + jsonEscape(openError) + "\"}";
    }

    // 与预览共用同一套 C++ 光栅化；quality=1 直出，quality=2 用 2x 超采样后降采样
    const int aa = std::max(1, std::min(2, aaFactor));
    const int rw = width * aa;
    const int rh = height * aa;
    Bitmap<Rgba> frame(Pixel(width, height));
    std::vector<uint8_t> hbuf;
    for (int f = 0; f < frames; ++f) {
        const double angle = 2.0 * 3.14159265358979 * double(f) / double(frames);
        splatPoints(pts, float(angle), 0.5f, rw, rh, hbuf);
        if (aa == 1) {
            for (int y = 0; y < height; ++y) {
                for (int x = 0; x < width; ++x) {
                    const size_t o = (size_t(y) * size_t(width) + size_t(x)) * 4;
                    frame[Pixel(x, y)] = Rgba(float(hbuf[o]) / 255.f,
                        float(hbuf[o + 1]) / 255.f,
                        float(hbuf[o + 2]) / 255.f,
                        1.f);
                }
            }
        } else {
            for (int y = 0; y < height; ++y) {
                for (int x = 0; x < width; ++x) {
                    int ar = 0, ag = 0, ab = 0;
                    for (int sy2 = 0; sy2 < 2; ++sy2) {
                        for (int sx2 = 0; sx2 < 2; ++sx2) {
                            const size_t o = ((size_t(y) * 2 + size_t(sy2)) * size_t(rw)
                                + (size_t(x) * 2 + size_t(sx2))) * 4;
                            ar += hbuf[o];
                            ag += hbuf[o + 1];
                            ab += hbuf[o + 2];
                        }
                    }
                    frame[Pixel(x, y)] = Rgba(float(ar) / 1020.f, float(ag) / 1020.f, float(ab) / 1020.f, 1.f);
                }
            }
        }
        String frameError;
        if (!writer.pushFrame(frame, frameError)) {
            String closeError;
            writer.close(closeError);
            return "{\"ok\":false,\"error\":\"编码失败：" + jsonEscape(frameError) + "\"}";
        }
        if (state) {
            state->rendered.store(f + 1);
        }
    }
    String closeError;
    const bool closed = writer.close(closeError);
    std::string json = "{\"ok\":";
    json += closed ? "true" : "false";
    json += ",\"frames\":" + std::to_string(writer.frameCount());
    json += ",\"bytes\":" + std::to_string(writer.bytesWritten());
    if (!closed) {
        json += ",\"error\":\"" + jsonEscape(closeError) + "\"";
    }
    json += "}";
    return json;
}

napi_value startExportVideo(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = -1;
    napi_get_value_int32(env, argv[0], &handle);
    char optBuf[1024] = {0};
    size_t len = 0;
    if (argc > 1) {
        napi_get_value_string_utf8(env, argv[1], optBuf, sizeof(optBuf), &len);
    }
    const std::string options(optBuf);

    VideoExportState& state = exportState();
    {
        std::lock_guard<std::mutex> lock(state.mutex);
        if (state.running) {
            return makeString(env, "{\"ok\":false,\"error\":\"已有导出任务在运行\"}");
        }
        state.running = true;
        state.done = false;
        state.ok = false;
        state.error.clear();
        state.path = extractJsonString(options, "path", "");
        state.total = std::atoi(extractJsonNumber(options, "frames", "120").c_str());
        state.rendered.store(0);
    }
    std::thread worker([handle, options]() {
        VideoExportState& st = exportState();
        const std::string result = runCloudExport(handle, options, &st);
        std::lock_guard<std::mutex> lock(st.mutex);
        st.ok = result.find("\"ok\":true") != std::string::npos;
        st.error = st.ok ? "" : extractJsonString(result, "error", "未知错误");
        st.done = true;
        st.running = false;
    });
    worker.detach();
    g_splatDirty[handle] = true;
    g_splatCache[handle].clear();
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

// ---------------------------------------------------------------------------
// A 路：录制预览画布。ArkTS 每帧把 RGBA 像素推上来，这里直接喂给编码器。
// ---------------------------------------------------------------------------
struct RecorderState {
    std::unique_ptr<VideoWriter> writer;
    bool active = false;
    int width = 0;
    int height = 0;
    int frames = 0;
    std::string path;
    std::string error;
    std::mutex mutex;
};

RecorderState& recorderState() {
    static RecorderState state;
    return state;
}

napi_value startRecording(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    char optBuf[1024] = {0};
    size_t len = 0;
    if (argc > 0) {
        napi_get_value_string_utf8(env, argv[0], optBuf, sizeof(optBuf), &len);
    }
    const std::string options(optBuf);
    const int width = std::atoi(extractJsonNumber(options, "width", "960").c_str());
    const int height = std::atoi(extractJsonNumber(options, "height", "720").c_str());
    const int fps = std::atoi(extractJsonNumber(options, "fps", "15").c_str());
    const int bitrate = std::atoi(extractJsonNumber(options, "bitrate", "6000000").c_str());
    const std::string path = extractJsonString(options, "path", "");

    RecorderState& st = recorderState();
    std::lock_guard<std::mutex> lock(st.mutex);
    if (st.active) {
        return makeString(env, "{\"ok\":false,\"error\":\"录制已在进行中\"}");
    }
    if (path.empty()) {
        return makeString(env, "{\"ok\":false,\"error\":\"缺少输出路径\"}");
    }
    st.writer.reset(new VideoWriter());
    VideoParams params;
    params.width = width;
    params.height = height;
    params.fps = fps;
    params.bitrate = bitrate;
    String openError;
    if (!st.writer->open(Path(String::fromUtf8(path.c_str())), params, openError)) {
        st.writer.reset();
        return makeString(env, "{\"ok\":false,\"error\":\"" + jsonEscape(openError) + "\"}");
    }
    st.active = true;
    st.width = width;
    st.height = height;
    st.frames = 0;
    st.path = path;
    st.error.clear();
    return makeString(env, "{\"ok\":true,\"width\":" + std::to_string(width) + ",\"height\":" + std::to_string(height) + "}");
}

// 录制用的点云缓存：录制开始时采样一次，之后每帧只做旋转+光栅化
struct CloudCache {
    std::vector<float> pts;
    float center[3] = {0, 0, 0};
    float radius = 1.f;
};
CloudCache g_recordingCloud;

napi_value startCloudRecording(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = -1;
    napi_get_value_int32(env, argv[0], &handle);
    char optBuf[1024] = {0};
    size_t len = 0;
    if (argc > 1) {
        napi_get_value_string_utf8(env, argv[1], optBuf, sizeof(optBuf), &len);
    }
    const std::string options(optBuf);
    const int width = std::atoi(extractJsonNumber(options, "width", "960").c_str());
    const int height = std::atoi(extractJsonNumber(options, "height", "720").c_str());
    const int fps = std::atoi(extractJsonNumber(options, "fps", "15").c_str());
    const int bitrate = std::atoi(extractJsonNumber(options, "bitrate", "6000000").c_str());
    const int maxPoints = std::atoi(extractJsonNumber(options, "points", "8000").c_str());
    const std::string path = extractJsonString(options, "path", "");

    RecorderState& st = recorderState();
    std::lock_guard<std::mutex> lock(st.mutex);
    if (st.active) {
        return makeString(env, "{\"ok\":false,\"error\":\"录制已在进行中\"}");
    }
    if (path.empty()) {
        return makeString(env, "{\"ok\":false,\"error\":\"缺少输出路径\"}");
    }

    g_recordingCloud.pts.clear();
    std::string sampleError;
    if (!sampleNodePoints(handle, maxPoints, g_recordingCloud.pts, sampleError)) {
        return makeString(env, "{\"ok\":false,\"error\":\"" + jsonEscape(String::fromUtf8(sampleError.c_str())) + "\"}");
    }
    std::vector<float>& pts = g_recordingCloud.pts;
    float lo[3] = {pts[0], pts[1], pts[2]};
    float hi[3] = {pts[0], pts[1], pts[2]};
    for (size_t i = 0; i + 2 < pts.size(); i += 3) {
        for (int k = 0; k < 3; ++k) {
            lo[k] = std::min(lo[k], pts[i + k]);
            hi[k] = std::max(hi[k], pts[i + k]);
        }
    }
    for (int k = 0; k < 3; ++k) {
        g_recordingCloud.center[k] = (lo[k] + hi[k]) * 0.5f;
    }
    float radius = 0.f;
    for (size_t i = 0; i + 2 < pts.size(); i += 3) {
        const float dx = pts[i] - g_recordingCloud.center[0];
        const float dy = pts[i + 1] - g_recordingCloud.center[1];
        const float dz = pts[i + 2] - g_recordingCloud.center[2];
        radius = std::max(radius, std::sqrt(dx * dx + dy * dy + dz * dz));
    }
    g_recordingCloud.radius = radius > 0.f ? radius : 1.f;

    st.writer.reset(new VideoWriter());
    VideoParams params;
    params.width = width;
    params.height = height;
    params.fps = fps;
    params.bitrate = bitrate;
    String openError;
    if (!st.writer->open(Path(String::fromUtf8(path.c_str())), params, openError)) {
        st.writer.reset();
        return makeString(env, "{\"ok\":false,\"error\":\"" + jsonEscape(openError) + "\"}");
    }
    st.active = true;
    st.width = width;
    st.height = height;
    st.frames = 0;
    st.path = path;
    st.error.clear();
    return makeString(env, "{\"ok\":true,\"width\":" + std::to_string(width) + ",\"height\":" + std::to_string(height) +
                               ",\"points\":" + std::to_string(g_recordingCloud.pts.size() / 3) + "}");
}

napi_value recordCloudFrame(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    double yaw = 0.7;
    double pitch = 0.45;
    napi_get_value_double(env, argv[0], &yaw);
    if (argc > 1) {
        napi_get_value_double(env, argv[1], &pitch);
    }

    RecorderState& st = recorderState();
    std::lock_guard<std::mutex> lock(st.mutex);
    if (!st.active || !st.writer) {
        return makeString(env, "{\"ok\":false,\"error\":\"录制未开始\"}");
    }
    const std::vector<float>& pts = g_recordingCloud.pts;
    if (pts.empty()) {
        return makeString(env, "{\"ok\":false,\"error\":\"没有可渲染的点\"}");
    }
    const int width = st.width;
    const int height = st.height;
    const float cx = g_recordingCloud.center[0];
    const float cy = g_recordingCloud.center[1];
    const float cz = g_recordingCloud.center[2];
    const float radius = g_recordingCloud.radius;
    const float scale = float(std::min(width, height)) * 0.42f / radius;
    const float ca = std::cos(float(yaw)), sa = std::sin(float(yaw));
    const float ct = std::cos(float(pitch)), stt = std::sin(float(pitch));

    // 用与预览相同的 C++ 光栅化（深度排序 + 圆盘 splat + 色图 + 光照），
    // 让导出视频的画质与界面预览一致，而不是旧的 2x2 方块。
    Bitmap<Rgba> frame(Pixel(width, height));
    {
        std::vector<uint8_t> rgba;
        splatPoints(pts, float(yaw), float(pitch), width, height, rgba);
        const size_t bytes = size_t(width) * size_t(height) * 4;
        if (rgba.size() == bytes) {
            for (int y = 0; y < height; ++y) {
                for (int x = 0; x < width; ++x) {
                    const size_t o = (size_t(y) * size_t(width) + size_t(x)) * 4;
                    frame[Pixel(x, y)] = Rgba(float(rgba[o]) / 255.f,
                        float(rgba[o + 1]) / 255.f,
                        float(rgba[o + 2]) / 255.f,
                        1.f);
                }
            }
        } else {
            frame.fill(Rgba(0.06f, 0.08f, 0.10f, 1.f));
        }
    }
    String frameError;
    if (!st.writer->pushFrame(frame, frameError)) {
        st.active = false;
        return makeString(env, "{\"ok\":false,\"error\":\"" + jsonEscape(frameError) + "\"}");
    }
    st.frames++;
    return makeString(env, "{\"ok\":true,\"frames\":" + std::to_string(st.frames) + "}");
}

napi_value pushVideoFrame(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    void* data = nullptr;
    size_t bytes = 0;
    napi_value arrayBuffer = argv[0];
    if (napi_get_arraybuffer_info(env, arrayBuffer, &data, &bytes) != napi_ok || data == nullptr) {
        return makeString(env, "{\"ok\":false,\"error\":\"无效的帧数据\"}");
    }

    RecorderState& st = recorderState();
    std::lock_guard<std::mutex> lock(st.mutex);
    if (!st.active || !st.writer) {
        return makeString(env, "{\"ok\":false,\"error\":\"录制未开始\"}");
    }
    const size_t needed = size_t(st.width) * size_t(st.height) * 4;
    if (bytes < needed) {
        st.error = "帧数据尺寸不符";
        return makeString(env, "{\"ok\":false,\"error\":\"帧数据尺寸不符\"}");
    }
    Bitmap<Rgba> frame(Pixel(st.width, st.height));
    const unsigned char* src = static_cast<const unsigned char*>(data);
    for (int y = 0; y < st.height; ++y) {
        for (int x = 0; x < st.width; ++x) {
            const size_t idx = (size_t(y) * size_t(st.width) + size_t(x)) * 4;
            frame[Pixel(x, y)] = Rgba(src[idx] / 255.f, src[idx + 1] / 255.f, src[idx + 2] / 255.f, src[idx + 3] / 255.f);
        }
    }
    String frameError;
    if (!st.writer->pushFrame(frame, frameError)) {
        st.error = frameError.toUtf8().cstr();
        st.active = false;
        st.writer.reset();
        return makeString(env, "{\"ok\":false,\"error\":\"" + jsonEscape(frameError) + "\"}");
    }
    st.frames++;
    return makeString(env, "{\"ok\":true,\"frames\":" + std::to_string(st.frames) + "}");
}

napi_value stopRecording(napi_env env, napi_callback_info) {
    RecorderState& st = recorderState();
    std::lock_guard<std::mutex> lock(st.mutex);
    if (!st.writer) {
        return makeString(env, "{\"ok\":false,\"error\":\"没有进行中的录制\",\"frames\":" + std::to_string(st.frames) + "}");
    }
    String closeError;
    const bool closed = st.writer->close(closeError);
    std::string json = "{\"ok\":";
    json += closed ? "true" : "false";
    json += ",\"frames\":" + std::to_string(st.frames);
    json += ",\"bytes\":" + std::to_string(st.writer->bytesWritten());
    if (!closed) {
        json += ",\"error\":\"" + jsonEscape(closeError) + "\"";
    }
    json += "}";
    st.active = false;
    st.writer.reset();
    st.frames = 0;
    return makeString(env, json);
}

napi_value exportStatus(napi_env env, napi_callback_info) {
    VideoExportState& state = exportState();
    std::lock_guard<std::mutex> lock(state.mutex);
    std::string json = "{\"running\":";
    json += state.running ? "true" : "false";
    json += ",\"done\":";
    json += state.done ? "true" : "false";
    json += ",\"ok\":";
    json += state.ok ? "true" : "false";
    json += ",\"rendered\":" + std::to_string(state.rendered.load());
    json += ",\"total\":" + std::to_string(state.total);
    if (!state.error.empty()) {
        json += ",\"error\":\"" + jsonEscape(String::fromUtf8(state.error.c_str())) + "\"";
    }
    if (!state.path.empty()) {
        json += ",\"path\":\"" + jsonEscape(String::fromUtf8(state.path.c_str())) + "\"";
    }
    json += "}";
    return makeString(env, json);
}

napi_value exportCloudVideo(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = -1;
    napi_get_value_int32(env, argv[0], &handle);
    char optBuf[1024] = {0};
    size_t len = 0;
    if (argc > 1) {
        napi_get_value_string_utf8(env, argv[1], optBuf, sizeof(optBuf), &len);
    }
    return makeString(env, runCloudExport(handle, std::string(optBuf), nullptr));
}

napi_value previewPoints(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = -1;
    int32_t maxPoints = 4000;
    napi_get_value_int32(env, argv[0], &handle);
    if (argc > 1) {
        napi_get_value_int32(env, argv[1], &maxPoints);
    }
    return makeString(env, previewJson(handle, maxPoints));
}


napi_value renderSplat(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value argv[5];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = -1;
    double yaw = 0.7;
    double pitch = 0.45;
    int32_t W = 900;
    int32_t H = 900;
    napi_get_value_int32(env, argv[0], &handle);
    if (argc > 1) { napi_get_value_double(env, argv[1], &yaw); }
    if (argc > 2) { napi_get_value_double(env, argv[2], &pitch); }
    if (argc > 3) { napi_get_value_int32(env, argv[3], &W); }
    if (argc > 4) { napi_get_value_int32(env, argv[4], &H); }
    W = std::max(16, std::min(W, 1600));
    H = std::max(16, std::min(H, 1600));

    if (nodeRegistry().find(handle) == nodeRegistry().end()) {
        return nullptr;
    }
    std::vector<float>& cached = g_splatCache[handle];
    if (cached.empty() || g_splatDirty[handle]) {
        std::string sampleError;
        std::vector<float> fresh;
        if (sampleNodePoints(handle, 40000, fresh, sampleError)) {
            cached = fresh;
        } else {
            cached.clear();
        }
        g_splatDirty[handle] = false;
    }
    const std::vector<float> pts = cached;
    std::vector<uint8_t> rgba;
    splatPoints(pts, float(yaw), float(pitch), W, H, rgba);
    void* data = nullptr;
    napi_value ab = nullptr;
    if (napi_create_arraybuffer(env, rgba.size(), &data, &ab) != napi_ok || data == nullptr) {
        return nullptr;
    }
    std::memcpy(data, rgba.data(), rgba.size());
    return ab;
}

napi_value version(napi_env env, napi_callback_info) {
    return makeString(env, "OpenSPH ark bridge 0.1 (core-only)");
}

napi_value jobCatalog(napi_env env, napi_callback_info) {
    return makeString(env, buildCatalogJson());
}


napi_value createNode(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    char className[256] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, argv[0], className, sizeof(className), &len);

    registerCoreJobs();
    for (const AutoPtr<IJobDesc>& desc : enumerateRegisteredJobs()) {
        if (!desc) {
            continue;
        }
        if (desc->className() == String::fromUtf8(className)) {
            AutoPtr<IJob> job = desc->create(NOTHING);
            if (!job) {
                break;
            }
            SharedPtr<JobNode> node = makeShared<JobNode>(std::move(job));
            const int handle = nextNodeHandle++;
            nodeRegistry().insert(std::make_pair(handle, node));
            napi_value result;
            napi_create_int32(env, handle, &result);
            return result;
        }
    }
    napi_value result;
    napi_create_int32(env, -1, &result);
    return result;
}

napi_value nodeSettings(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = -1;
    napi_get_value_int32(env, argv[0], &handle);

    std::vector<std::pair<std::string, std::vector<std::string>>> categories;
    const auto it = nodeRegistry().find(handle);
    if (it != nodeRegistry().end()) {
        VirtualSettings settings = it->second->getSettings();
        SettingsJsonProc proc(categories);
        settings.enumerate(proc);
    }

    std::string json = "[";
    bool firstCat = true;
    for (const auto& cat : categories) {
        if (!firstCat) {
            json += ",";
        }
        firstCat = false;
        json += "{\"category\":\"" + cat.first + "\",\"entries\":[";
        bool firstEntry = true;
        for (const std::string& e : cat.second) {
            if (!firstEntry) {
                json += ",";
            }
            firstEntry = false;
            json += e;
        }
        json += "]}";
    }
    json += "]";
    return makeString(env, json);
}

napi_value setNodeSetting(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = -1;
    char key[128] = {0};
    char value[256] = {0};
    char valueType[32] = {0};
    size_t len = 0;
    napi_get_value_int32(env, argv[0], &handle);
    napi_get_value_string_utf8(env, argv[1], key, sizeof(key), &len);
    napi_get_value_string_utf8(env, argv[2], value, sizeof(value), &len);
    napi_get_value_string_utf8(env, argv[3], valueType, sizeof(valueType), &len);

    bool changed = false;
    const auto it = nodeRegistry().find(handle);
    if (it != nodeRegistry().end()) {
        VirtualSettings settings = it->second->getSettings();
        SetValueProc proc(String::fromUtf8(key), String::fromUtf8(value), String::fromUtf8(valueType), changed);
        settings.enumerate(proc);
    }
    napi_value result;
    napi_get_boolean(env, changed, &result);
    return result;
}

class SaveSessionProc : public VirtualSettings::IEntryProc {
private:
    ConfigNode& node;

public:
    explicit SaveSessionProc(ConfigNode& node)
        : node(node) {}

    virtual void onCategory(const String&) const override {}

    virtual void onEntry(const String& key, IVirtualEntry& entry) const override {
        const IVirtualEntry::Type type = entry.getType();
        if (type == IVirtualEntry::Type::EXTRA) {
            return;
        }
        const String typeKey = key + String::fromUtf8(" __type");
        node.set(typeKey, String::fromUtf8(typeName(type).c_str()));
        if (type == IVirtualEntry::Type::BOOL) {
            node.set(key, entry.get().get<bool>() ? String::fromUtf8("true") : String::fromUtf8("false"));
        } else if (type == IVirtualEntry::Type::INT) {
            node.set(key, String::fromUtf8(std::to_string(entry.get().get<int>()).c_str()));
        } else if (type == IVirtualEntry::Type::FLOAT) {
            char buf[64];
            std::snprintf(buf, sizeof(buf), "%.8g", double(entry.get().get<Float>()));
            node.set(key, String::fromUtf8(buf));
        } else if (type == IVirtualEntry::Type::ENUM) {
            node.set(key, String::fromUtf8(std::to_string(entry.get().get<EnumWrapper>().value).c_str()));
        } else if (type == IVirtualEntry::Type::STRING) {
            node.set(key, entry.get().get<String>());
        } else if (type == IVirtualEntry::Type::VECTOR) {
            const Vector v = entry.get().get<Vector>();
            char buf[96];
            std::snprintf(buf, sizeof(buf), "%.8g %.8g %.8g", double(v[0]), double(v[1]), double(v[2]));
            node.set(key, String::fromUtf8(buf));
        } else if (type == IVirtualEntry::Type::INTERVAL) {
            const Interval itv = entry.get().get<Interval>();
            char buf[64];
            std::snprintf(buf, sizeof(buf), "%.8g %.8g", double(itv.lower()), double(itv.upper()));
            node.set(key, String::fromUtf8(buf));
        }
    }
};

class ApplySessionProc : public VirtualSettings::IEntryProc {
private:
    ConfigNode& node;

public:
    explicit ApplySessionProc(ConfigNode& node)
        : node(node) {}

    virtual void onCategory(const String&) const override {}

    virtual void onEntry(const String& key, IVirtualEntry& entry) const override {
        if (!node.tryGet<String>(key)) {
            return;
        }
        const String typeKey = key + String::fromUtf8(" __type");
        String type = String::fromUtf8("other");
        if (Optional<String> t = node.tryGet<String>(typeKey)) {
            type = t.value();
        }
        try {
            if (type == String::fromUtf8("bool")) {
                entry.set(IVirtualEntry::Value(node.get<String>(key) == String::fromUtf8("true")));
            } else if (type == String::fromUtf8("int")) {
                entry.set(IVirtualEntry::Value(std::atoi(node.get<String>(key).toUtf8().cstr())));
            } else if (type == String::fromUtf8("float")) {
                entry.set(IVirtualEntry::Value(Float(std::atof(node.get<String>(key).toUtf8().cstr()))));
            } else if (type == String::fromUtf8("enum")) {
                const EnumWrapper current = entry.get().get<EnumWrapper>();
                entry.set(IVirtualEntry::Value(
                    EnumWrapper(std::atoi(node.get<String>(key).toUtf8().cstr()), current.index)));
            } else if (type == String::fromUtf8("string")) {
                entry.set(IVirtualEntry::Value(node.get<String>(key)));
            } else if (type == String::fromUtf8("vector")) {
                Float xyz[3] = {0, 0, 0};
                std::sscanf(node.get<String>(key).toUtf8().cstr(), "%f %f %f", &xyz[0], &xyz[1], &xyz[2]);
                entry.set(IVirtualEntry::Value(Vector(xyz[0], xyz[1], xyz[2])));
            } else if (type == String::fromUtf8("interval")) {
                Float lo = 0, hi = 0;
                std::sscanf(node.get<String>(key).toUtf8().cstr(), "%f %f", &lo, &hi);
                entry.set(IVirtualEntry::Value(Interval(lo, hi)));
            }
        } catch (const std::exception&) {
            // 类型不匹配就跳过，不让单个项影响整体加载
        }
    }
};

napi_value saveSession(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    char pathBuf[512] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, argv[0], pathBuf, sizeof(pathBuf), &len);
    if (len == 0) {
        return makeString(env, "{\"ok\":false,\"error\":\"缺少路径\"}");
    }
    try {
        OH_LOG_Print(LOG_APP, LOG_INFO, 0x0100, "OpenSPHSess", "save start registry=%{public}zu", nodeRegistry().size());
        Config config;
        SharedPtr<ConfigNode> nodesNode = config.addNode(String::fromUtf8("nodes"));
        std::map<int, String> names;
        int idx = 0;
        for (const auto& entry : nodeRegistry()) {
            SharedPtr<JobNode> node = entry.second;
            std::string nameUtf8 = "node" + std::to_string(idx);
            const String name = String::fromUtf8(nameUtf8.c_str());
            names[entry.first] = name;
            SharedPtr<ConfigNode> cn = nodesNode->addChild(name);
            cn->set(String::fromUtf8("class_name"), node->className());
            cn->set(String::fromUtf8("instance_name"), node->instanceName());
            VirtualSettings settings = node->getSettings();
            SaveSessionProc proc(*cn);
            settings.enumerate(proc);
            ++idx;
        }
        OH_LOG_Print(LOG_APP, LOG_INFO, 0x0100, "OpenSPHSess", "save nodes done idx=%{public}d", idx);
        // connections
        SharedPtr<ConfigNode> conns = config.addNode(String::fromUtf8("connections"));
        int ci = 0;
        for (const auto& entry : nodeRegistry()) {
            SharedPtr<JobNode> dependent = entry.second;
            const Size slotCnt = dependent->getSlotCnt();
            for (Size si = 0; si < slotCnt; ++si) {
                const SlotData slot = dependent->getSlot(si);
                if (!slot.provider) {
                    continue;
                }
                // find provider handle
                int providerHandle = -1;
                for (const auto& p : nodeRegistry()) {
                    if (p.second == slot.provider) {
                        providerHandle = p.first;
                        break;
                    }
                }
                if (providerHandle < 0) {
                    continue;
                }
                std::string cn2 = "conn" + std::to_string(ci);
                SharedPtr<ConfigNode> c = conns->addChild(String::fromUtf8(cn2.c_str()));
                c->set(String::fromUtf8("from"), names[providerHandle]);
                c->set(String::fromUtf8("to"), names[entry.first]);
                c->set(String::fromUtf8("slot"), slot.name);
                ++ci;
            }
        }
        OH_LOG_Print(LOG_APP, LOG_INFO, 0x0100, "OpenSPHSess", "save conns done ci=%{public}d", ci);
        config.save(Path(String::fromUtf8(pathBuf)));
        OH_LOG_Print(LOG_APP, LOG_INFO, 0x0100, "OpenSPHSess", "save written");
        return makeString(env, "{\"ok\":true,\"nodes\":" + std::to_string(idx) + ",\"connections\":" + std::to_string(ci) + "}");
    } catch (const std::exception& e) {
        return makeString(env, "{\"ok\":false,\"error\":\"" + jsonEscape(String::fromUtf8(e.what())) + "\"}");
    }
}

napi_value loadSession(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    char pathBuf[512] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, argv[0], pathBuf, sizeof(pathBuf), &len);
    if (len == 0) {
        return makeString(env, "{\"ok\":false,\"error\":\"缺少路径\"}");
    }
    try {
        Config config;
        config.load(Path(String::fromUtf8(pathBuf)));
        nodeRegistry().clear();
        FlatMap<String, SharedPtr<JobNode>> created;
        FlatMap<String, int> handles;
        std::string nodesJson = "[";
        bool firstNode = true;
        registerCoreJobs();
        SharedPtr<ConfigNode> nodesNode = config.getNode(String::fromUtf8("nodes"));
        int count = 0;
        nodesNode->enumerateChildren([&created, &handles, &nodesJson, &firstNode, &count](String name, ConfigNode& input) {
            Optional<String> classNameOpt = input.tryGet<String>(String::fromUtf8("class_name"));
            if (!classNameOpt) {
                return;
            }
            const String className = classNameOpt.value();
            RawPtr<IJobDesc> desc = getJobDesc(className);
            if (!desc) {
                return;
            }
            AutoPtr<IJob> job = desc->create(NOTHING);
            SharedPtr<JobNode> node = makeShared<JobNode>(std::move(job));
            VirtualSettings settings = node->getSettings();
            ApplySessionProc proc(input);
            settings.enumerate(proc);
            created.insert(name, node);
            const int handle = nextNodeHandle++;
            handles.insert(name, handle);
            nodeRegistry().insert(std::make_pair(handle, node));
            if (!firstNode) {
                nodesJson += ",";
            }
            firstNode = false;
            nodesJson += "{\"handle\":" + std::to_string(handle);
            nodesJson += ",\"className\":\"" + jsonEscape(node->className()) + "\"";
            nodesJson += ",\"instanceName\":\"" + jsonEscape(node->instanceName()) + "\"}";
            count++;
        });

        // connections
        int connCount = 0;
        std::string linksJson = "[";
        bool firstLink = true;
        if (SharedPtr<ConfigNode> conns = config.tryGetNode(String::fromUtf8("connections"))) {
            conns->enumerateChildren([&created, &handles, &linksJson, &firstLink, &connCount](String, ConfigNode& c) {
                Optional<String> fromOpt = c.tryGet<String>(String::fromUtf8("from"));
                Optional<String> toOpt = c.tryGet<String>(String::fromUtf8("to"));
                Optional<String> slotOpt = c.tryGet<String>(String::fromUtf8("slot"));
                if (!fromOpt || !toOpt || !slotOpt) {
                    return;
                }
                SharedPtr<JobNode> fromNode = created[fromOpt.value()];
                SharedPtr<JobNode> toNode = created[toOpt.value()];
                if (!fromNode || !toNode) {
                    return;
                }
                try {
                    fromNode->connect(toNode, slotOpt.value());
                } catch (const std::exception&) {
                    return;
                }
                connCount++;
                if (!firstLink) {
                    linksJson += ",";
                }
                firstLink = false;
                linksJson += "{\"from\":" + std::to_string(handles[fromOpt.value()]);
                linksJson += ",\"to\":" + std::to_string(handles[toOpt.value()]) + "}";
            });
        }
        nodesJson += "]";
        linksJson += "]";
        OH_LOG_Print(LOG_APP, LOG_INFO, 0x0100, "OpenSPHSess", "load: nodes=%{public}d conns=%{public}d", count, connCount);
        return makeString(env, "{\"ok\":true,\"nodes\":" + std::to_string(count) +
                               ",\"connections\":" + std::to_string(connCount) +
                               ",\"nodeList\":" + nodesJson + ",\"linkList\":" + linksJson + "}");
    } catch (const std::exception& e) {
        return makeString(env, "{\"ok\":false,\"error\":\"" + jsonEscape(String::fromUtf8(e.what())) + "\"}");
    }
}

napi_value nodeSlots(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = -1;
    napi_get_value_int32(env, argv[0], &handle);
    std::string json = "[";
    const auto it = nodeRegistry().find(handle);
    if (it != nodeRegistry().end()) {
        SharedPtr<JobNode> node = it->second;
        const Size cnt = node->getSlotCnt();
        for (Size i = 0; i < cnt; ++i) {
            const SlotData slot = node->getSlot(i);
            if (i > 0) {
                json += ",";
            }
            json += "{\"name\":\"" + jsonEscape(slot.name) + "\"";
            json += ",\"used\":";
            json += slot.used ? "true" : "false";
            json += ",\"connected\":";
            json += slot.provider != nullptr ? "true" : "false";
            if (slot.provider) {
                json += ",\"provider\":\"" + jsonEscape(slot.provider->instanceName()) + "\"";
            }
            json += "}";
        }
    }
    json += "]";
    return makeString(env, json);
}

napi_value connectNodes(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t fromHandle = -1;
    int32_t toHandle = -1;
    char slotBuf[128] = {0};
    size_t len = 0;
    napi_get_value_int32(env, argv[0], &fromHandle);
    napi_get_value_int32(env, argv[1], &toHandle);
    napi_get_value_string_utf8(env, argv[2], slotBuf, sizeof(slotBuf), &len);

    const auto fromIt = nodeRegistry().find(fromHandle);
    const auto toIt = nodeRegistry().find(toHandle);
    if (fromIt == nodeRegistry().end() || toIt == nodeRegistry().end()) {
        return makeString(env, "{\"ok\":false,\"error\":\"节点不存在\"}");
    }
    try {
        fromIt->second->connect(toIt->second, String::fromUtf8(slotBuf));
        return makeString(env, "{\"ok\":true}");
    } catch (const std::exception& e) {
        return makeString(env, "{\"ok\":false,\"error\":\"" + jsonEscape(String::fromUtf8(e.what())) + "\"}");
    }
}

// ---------------------------------------------------------------------------
// 模拟运行控制：开始 / 暂停 / 停止 / 进度
// ---------------------------------------------------------------------------
/// 把点云按给定视角光栅化成 RGBA 帧（模拟录制与点云录制共用）
void rasterizeCloud(const std::vector<float>& pts, const float yaw, const float pitch,
    const int width, const int height, Bitmap<Rgba>& frame) {
    frame.fill(Rgba(0.06f, 0.08f, 0.10f, 1.f));
    if (pts.size() < 3) {
        return;
    }
    float lo[3] = {pts[0], pts[1], pts[2]};
    float hi[3] = {pts[0], pts[1], pts[2]};
    for (size_t i = 0; i + 2 < pts.size(); i += 3) {
        for (int k = 0; k < 3; ++k) {
            lo[k] = std::min(lo[k], pts[i + k]);
            hi[k] = std::max(hi[k], pts[i + k]);
        }
    }
    const float cx = (lo[0] + hi[0]) * 0.5f;
    const float cy = (lo[1] + hi[1]) * 0.5f;
    const float cz = (lo[2] + hi[2]) * 0.5f;
    float radius = 0.f;
    for (size_t i = 0; i + 2 < pts.size(); i += 3) {
        const float dx = pts[i] - cx, dy = pts[i + 1] - cy, dz = pts[i + 2] - cz;
        radius = std::max(radius, std::sqrt(dx * dx + dy * dy + dz * dz));
    }
    if (radius <= 0.f) {
        radius = 1.f;
    }
    const float scale = float(std::min(width, height)) * 0.42f / radius;
    const float ca = std::cos(yaw), sa = std::sin(yaw);
    const float ct = std::cos(pitch), st = std::sin(pitch);
    for (size_t i = 0; i + 2 < pts.size(); i += 3) {
        const float x0 = pts[i] - cx, y0 = pts[i + 1] - cy, z0 = pts[i + 2] - cz;
        const float x1 = x0 * ca - y0 * sa;
        const float y1 = x0 * sa + y0 * ca;
        const float y2 = y1 * ct - z0 * st;
        const float z2 = y1 * st + z0 * ct;
        const int sx = int(float(width) * 0.5f + x1 * scale);
        const int sy = int(float(height) * 0.5f - z2 * scale);
        const float depth = std::min(1.f, std::max(0.f, (y2 / radius + 1.f) * 0.5f));
        const Rgba color(0.35f + 0.45f * depth, 0.55f + 0.35f * depth, 1.f, 1.f);
        for (int dy = 0; dy < 2; ++dy) {
            for (int dx = 0; dx < 2; ++dx) {
                const int px = sx + dx;
                const int py = sy + dy;
                if (px >= 0 && px < width && py >= 0 && py < height) {
                    frame[Pixel(px, py)] = color;
                }
            }
        }
    }
}

/// 从 storage 抽样粒子坐标（扁平 xyz），最多 cap 个点
void sampleStorage(const Storage& storage, const Size cap, std::vector<float>& out) {
    out.clear();
    ArrayView<const Vector> r = storage.getValue<Vector>(QuantityId::POSITION);
    const Size total = r.size();
    if (total == 0) {
        return;
    }
    const Size step = total > cap ? total / cap : 1;
    for (Size i = 0; i < total && out.size() < cap * 3; i += step) {
        out.push_back(float(r[i][0]));
        out.push_back(float(r[i][1]));
        out.push_back(float(r[i][2]));
    }
}

struct SimState {
    std::atomic<bool> running{false};
    std::atomic<bool> pauseRequested{false};
    std::atomic<bool> abortRequested{false};
    bool done = false;
    bool ok = false;
    double time = 0;
    long long steps = 0;
    size_t particles = 0;
    std::string error;
    std::mutex mutex;
    // 模拟录制
    std::unique_ptr<VideoWriter> simWriter;
    int recWidth = 0;
    int recHeight = 0;
    int recEvery = 5;
    long long recFrames = 0;
    std::string recPath;
    std::atomic<bool> recActive{false};
    // 运行中快照（供实时预览）
    std::vector<float> snapshot;
    long long snapshotStep = -1;
};

SimState& simState() {
    static SimState state;
    return state;
}

class SimCallbacks : public IJobCallbacks {
private:
    SimState& state;

public:
    explicit SimCallbacks(SimState& state)
        : state(state) {}

    virtual void onStart(const IJob&) override {}

    virtual void onEnd(const Storage&, const Statistics&) override {}

    virtual void onSetUp(const Storage& storage, Statistics& stats) override {
        std::lock_guard<std::mutex> lock(state.mutex);
        state.particles = storage.getParticleCnt();
        if (stats.has(StatisticsId::RUN_TIME)) {
            state.time = double(stats.get<Float>(StatisticsId::RUN_TIME));
        }
    }

    virtual void onTimeStep(const Storage& storage, Statistics& stats) override {
        {
            std::lock_guard<std::mutex> lock(state.mutex);
            state.steps += 1;
            state.particles = storage.getParticleCnt();
            if (stats.has(StatisticsId::RUN_TIME)) {
                state.time = double(stats.get<Float>(StatisticsId::RUN_TIME));
            }
        }
        while (state.pauseRequested.load() && !state.abortRequested.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }

        // 实时预览快照：每 3 步刷新一次。
        // 注意：onTimeStep 也会被非粒子作业（IC、几何、材料）调用，那里没有 POSITION，
        // 直接取会抛 Invalid storage access 并中断整个运行，所以必须先判粒子数并吞掉异常。
        if (state.steps % 3 == 0 && storage.getParticleCnt() > 0) {
            try {
                std::vector<float> pts;
                sampleStorage(storage, 4000, pts);
                std::lock_guard<std::mutex> lock(state.mutex);
                state.snapshot.swap(pts);
                state.snapshotStep = state.steps;
            } catch (const std::exception&) {
                // 该作业没有粒子量，跳过这一帧
            }
        }

        // 模拟录制：每 recEvery 步抓一次当前粒子快照，光栅化后送编码器
        if (state.recActive.load() && storage.getParticleCnt() > 0) {
            const long long step = state.steps;
            if (step % state.recEvery == 0) {
              try {
                ArrayView<const Vector> r = storage.getValue<Vector>(QuantityId::POSITION);
                std::vector<float> pts;
                const Size total = r.size();
                const Size cap = 6000;
                const Size stepIdx = total > cap ? total / cap : 1;
                for (Size i = 0; i < total && pts.size() < cap * 3; i += stepIdx) {
                    pts.push_back(float(r[i][0]));
                    pts.push_back(float(r[i][1]));
                    pts.push_back(float(r[i][2]));
                }
                Bitmap<Rgba> frame(Pixel(state.recWidth, state.recHeight));
                const float angle = float(step) * 0.02f;
                rasterizeCloud(pts, angle, 0.5f, state.recWidth, state.recHeight, frame);
                std::lock_guard<std::mutex> lock(state.mutex);
                if (state.simWriter) {
                    String err;
                    if (state.simWriter->pushFrame(frame, err)) {
                        state.recFrames++;
                    }
                }
              } catch (const std::exception&) {
                // 忽略无粒子量的作业
              }
            }
        }
    }

    virtual bool shouldAbortRun() const override {
        return state.abortRequested.load();
    }

};

napi_value runSimulation(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = -1;
    napi_get_value_int32(env, argv[0], &handle);
    double endTime = 0;
    if (argc > 1) {
        napi_get_value_double(env, argv[1], &endTime);
    }
    const auto it = nodeRegistry().find(handle);
    if (it == nodeRegistry().end()) {
        return makeString(env, "{\"ok\":false,\"error\":\"节点不存在\"}");
    }
    SharedPtr<JobNode> node = it->second;
    if (!dynamic_cast<IRunJob*>(node->getJob().get())) {
        return makeString(env, "{\"ok\":false,\"error\":\"该节点不是模拟作业\"}");
    }
    // 运行前检查必需输入，避免内核里因缺输入走到断言而崩溃
    std::string missing;
    const Size slotCnt = node->getSlotCnt();
    for (Size i = 0; i < slotCnt; ++i) {
        const SlotData slot = node->getSlot(i);
        if (slot.used && !slot.provider) {
            if (!missing.empty()) {
                missing += "、";
            }
            missing += slot.name.toUtf8().cstr();
        }
    }
    if (!missing.empty()) {
        return makeString(env, "{\"ok\":false,\"error\":\"缺少输入：" + jsonEscape(String::fromUtf8(missing.c_str())) + "\"}");
    }
    SimState& st = simState();
    {
        std::lock_guard<std::mutex> lock(st.mutex);
        if (st.running.load()) {
            return makeString(env, "{\"ok\":false,\"error\":\"模拟已在运行\"}");
        }
        st.running.store(true);
        st.pauseRequested.store(false);
        st.abortRequested.store(false);
        st.done = false;
        st.ok = false;
        st.time = 0;
        st.steps = 0;
        st.particles = 0;
        st.error.clear();
    }
    std::thread worker([node, endTime]() {
        SimState& st = simState();
        SimCallbacks callbacks(st);
        try {
            // 与 wx/CLI 一致：先克隆整棵节点树，再通过 IRunJob::getRun() 取 IRun 运行，
            // 不要在活节点上直接跑（运行期会改写节点内部缓存）。
            SharedPtr<JobNode> clone = cloneHierarchy(*node, String(""));
            RawPtr<IRunJob> runJob = dynamic_cast<IRunJob*>(clone->getJob().get());
            if (!runJob) {
                throw Exception("节点不是可运行的模拟作业");
            }
            // 与 CLI 一致：在克隆出的节点树上直接 run，节点内部会完成 IC 求值与 setUp
            RunSettings globals = EMPTY_SETTINGS;
            globals.set(RunSettingsId::RUN_THREAD_CNT, 0);
            globals.set(RunSettingsId::RUN_THREAD_GRANULARITY, 1000);
            globals.set(RunSettingsId::RUN_RNG, RngEnum::UNIFORM);
            globals.set(RunSettingsId::RUN_RNG_SEED, 1234);
            if (endTime > 0) {
                globals.set(RunSettingsId::RUN_END_TIME, Float(endTime));
            }
            clone->run(globals, callbacks);
            std::lock_guard<std::mutex> lock(st.mutex);
            st.ok = true;
            st.done = true;
        } catch (const std::exception& e) {
            std::lock_guard<std::mutex> lock(st.mutex);
            st.ok = false;
            st.error = String::fromUtf8(e.what()).toUtf8().cstr();
            st.done = true;
        }
        st.running.store(false);
    });
    worker.detach();
    return makeString(env, "{\"ok\":true}");
}

napi_value simSnapshot(napi_env env, napi_callback_info) {
    SimState& st = simState();
    std::string json = "{\"count\":0,\"step\":0,\"points\":[";
    {
        std::lock_guard<std::mutex> lock(st.mutex);
        const std::vector<float>& pts = st.snapshot;
        json += "";
        for (size_t i = 0; i < pts.size(); ++i) {
            if (i > 0) {
                json += ",";
            }
            json += jsonFloat(double(pts[i]));
        }
        json += "]";
        json = "{\"count\":" + std::to_string(pts.size() / 3) +
               ",\"step\":" + std::to_string(st.snapshotStep) + ",\"points\":" + json.substr(json.find('[')) + "}";
    }
    return makeString(env, json);
}

napi_value startSimRecording(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    char optBuf[1024] = {0};
    size_t len = 0;
    if (argc > 0) {
        napi_get_value_string_utf8(env, argv[0], optBuf, sizeof(optBuf), &len);
    }
    const std::string options(optBuf);
    const int width = std::atoi(extractJsonNumber(options, "width", "1280").c_str());
    const int height = std::atoi(extractJsonNumber(options, "height", "720").c_str());
    const int fps = std::atoi(extractJsonNumber(options, "fps", "15").c_str());
    const int bitrate = std::atoi(extractJsonNumber(options, "bitrate", "6000000").c_str());
    const int every = std::atoi(extractJsonNumber(options, "every", "5").c_str());
    const std::string path = extractJsonString(options, "path", "");
    if (path.empty()) {
        return makeString(env, "{\"ok\":false,\"error\":\"缺少输出路径\"}");
    }

    SimState& st = simState();
    std::lock_guard<std::mutex> lock(st.mutex);
    if (st.recActive.load()) {
        return makeString(env, "{\"ok\":false,\"error\":\"录制已在进行中\"}");
    }
    if (!st.running.load()) {
        return makeString(env, "{\"ok\":false,\"error\":\"没有正在运行的模拟\"}");
    }
    st.simWriter.reset(new VideoWriter());
    VideoParams params;
    params.width = width;
    params.height = height;
    params.fps = fps;
    params.bitrate = bitrate;
    String openError;
    if (!st.simWriter->open(Path(String::fromUtf8(path.c_str())), params, openError)) {
        st.simWriter.reset();
        return makeString(env, "{\"ok\":false,\"error\":\"" + jsonEscape(openError) + "\"}");
    }
    st.recWidth = width;
    st.recHeight = height;
    st.recEvery = every > 0 ? every : 5;
    st.recFrames = 0;
    st.recPath = path;
    st.recActive.store(true);
    return makeString(env, "{\"ok\":true,\"width\":" + std::to_string(width) + ",\"height\":" + std::to_string(height) + "}");
}

napi_value stopSimRecording(napi_env env, napi_callback_info) {
    SimState& st = simState();
    st.recActive.store(false);
    std::lock_guard<std::mutex> lock(st.mutex);
    if (!st.simWriter) {
        return makeString(env, "{\"ok\":false,\"error\":\"没有进行中的录制\",\"frames\":" + std::to_string(st.recFrames) + "}");
    }
    String closeError;
    const bool closed = st.simWriter->close(closeError);
    std::string json = "{\"ok\":";
    json += closed ? "true" : "false";
    json += ",\"frames\":" + std::to_string(st.recFrames);
    json += ",\"bytes\":" + std::to_string(st.simWriter->bytesWritten());
    if (!closed) {
        json += ",\"error\":\"" + jsonEscape(closeError) + "\"";
    }
    json += "}";
    st.simWriter.reset();
    st.recFrames = 0;
    return makeString(env, json);
}

napi_value simulationStatus(napi_env env, napi_callback_info) {
    SimState& st = simState();
    std::lock_guard<std::mutex> lock(st.mutex);
    char buf[512];
    std::snprintf(buf, sizeof(buf),
        "{\"running\":%s,\"paused\":%s,\"done\":%s,\"ok\":%s,\"time\":%.6g,\"steps\":%lld,\"particles\":%zu",
        st.running.load() ? "true" : "false",
        st.pauseRequested.load() ? "true" : "false",
        st.done ? "true" : "false",
        st.ok ? "true" : "false",
        st.time,
        st.steps,
        st.particles);
    std::string json(buf);
    json += ",\"recording\":";
    json += st.recActive.load() ? "true" : "false";
    json += ",\"recFrames\":" + std::to_string(st.recFrames);
    if (!st.error.empty()) {
        json += ",\"error\":\"" + jsonEscape(String::fromUtf8(st.error.c_str())) + "\"";
    }
    json += "}";
    return makeString(env, json);
}

napi_value setSimulationPaused(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    bool paused = false;
    napi_get_value_bool(env, argv[0], &paused);
    simState().pauseRequested.store(paused);
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

napi_value stopSimulation(napi_env env, napi_callback_info) {
    simState().abortRequested.store(true);
    simState().pauseRequested.store(false);
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

napi_value releaseNode(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = -1;
    napi_get_value_int32(env, argv[0], &handle);
    nodeRegistry().erase(handle);
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"version", nullptr, version, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"jobCatalog", nullptr, jobCatalog, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createNode", nullptr, createNode, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nodeSettings", nullptr, nodeSettings, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setNodeSetting", nullptr, setNodeSetting, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releaseNode", nullptr, releaseNode, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"previewPoints", nullptr, previewPoints, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderSplat", nullptr, renderSplat, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"exportCloudVideo", nullptr, exportCloudVideo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startExportVideo", nullptr, startExportVideo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"exportStatus", nullptr, exportStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startRecording", nullptr, startRecording, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pushVideoFrame", nullptr, pushVideoFrame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startCloudRecording", nullptr, startCloudRecording, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"recordCloudFrame", nullptr, recordCloudFrame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"saveSession", nullptr, saveSession, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadSession", nullptr, loadSession, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nodeSlots", nullptr, nodeSlots, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"connectNodes", nullptr, connectNodes, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"runSimulation", nullptr, runSimulation, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"simulationStatus", nullptr, simulationStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSimulationPaused", nullptr, setSimulationPaused, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopSimulation", nullptr, stopSimulation, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startSimRecording", nullptr, startSimRecording, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"simSnapshot", nullptr, simSnapshot, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopSimRecording", nullptr, stopSimRecording, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopRecording", nullptr, stopRecording, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module arkModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "opensph_ark",
    .nm_priv = ((void*)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterArkModule(void) {
    napi_module_register(&arkModule);
}
