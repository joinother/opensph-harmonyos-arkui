// ArkUI 主界面（M1.5）：菜单栏 + 节点库 + 节点图（添加/拖拽/端口连线/删除）+ 属性占位。
// 动效：入场淡入上移、左栏折叠、选中过渡、节点淡入、拖拽跟手、连线实时跟随。
import ark from 'libopensph_ark.so';
import { AppNotice, NoticeLevel, NoticeService } from '../common/NotificationCenter';
import { CATEGORY_LABELS, ENUM_LABELS, ENUM_LABELS_EXTRA, SETTING_LABELS, SETTING_LABELS_EXTRA } from '../common/I18nZh';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import display from '@ohos.display';
import { WindowHolder } from '../common/WindowHolder';
import preferences from '@ohos.data.preferences';
import sysSettings from '@ohos.settings';
import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import picker from '@ohos.file.picker';
import { SystemNotifier } from '../common/SystemNotifier';

interface JobEntry {
  className: string;
  category: string;
  tooltip: string;
}

interface CategoryGroup {
  name: string;
  items: JobEntry[];
}

interface SettingOption {
  value: number;
  label: string;
}

interface SettingEntry {
  key: string;
  name: string;
  type: string;
  value: number | string | boolean | number[] | null;
  enabled: boolean;
  tip: string;
  options: SettingOption[];
}

interface SettingCategory {
  category: string;
  entries: SettingEntry[];
}

interface GraphLink {
  id: number;
  from: number;
  to: number;
}

@Observed
class GraphNode {
  id: number;
  handle: number;
  className: string;
  title: string;
  category: string;
  x: number;
  y: number;

  constructor(id: number, handle: number, className: string, title: string, category: string, x: number, y: number) {
    this.id = id;
    this.handle = handle;
    this.className = className;
    this.title = title;
    this.category = category;
    this.x = x;
    this.y = y;
  }
}

const CARD_W: number = 168;
const CARD_H: number = 58;
const PORT_R: number = 6;

const CATEGORY_LABEL: Map<string, string> = new Map<string, string>([
  ['material', '材料'],
  ['materials', '材料'],
  ['particle operators', '粒子算子'],
  ['particles operators', '粒子算子'],
  ['geometry', '几何'],
  ['initial conditions', '初始条件'],
  ['particles', '粒子算子'],
  ['simulations', '模拟'],
  ['io', '输入输出'],
  ['rendering', '渲染']
]);

const NODE_LABEL: Map<string, string> = new Map<string, string>([
  ['SPH run', 'SPH 模拟'],
  ['SPH stabilization', 'SPH 稳定化'],
  ['N-body run', '多体引力模拟'],
  ['Position based run', '位置约束模拟'],
  ['sphere', '球体'],
  ['block', '方块'],
  ['ellipsoid', '椭球'],
  ['cylinder', '圆柱'],
  ['toroid', '圆环'],
  ['Maclaurin spheroid', '麦克劳林椭球'],
  ['half space', '半空间'],
  ['Gaussian sphere', '高斯球'],
  ['triangle mesh', '三角网格'],
  ['particle geometry', '粒子几何'],
  ['spheres geometry', '球串几何'],
  ['invert geometry', '反转几何'],
  ['transform geometry', '变换几何'],
  ['boolean', '布尔运算'],
  ['load file', '读取文件'],
  ['load sequence', '读取序列'],
  ['save file', '保存文件'],
  ['save mesh', '导出网格'],
  ['create monolithic body', '生成整体天体'],
  ['create differentiated body', '生成分层天体'],
  ['create single particle', '生成单粒子'],
  ['create impactor', '生成撞击体'],
  ['set equilibrium energy', '设置平衡内能'],
  ['set equilibrium density', '设置平衡密度'],
  ['set Keplerian velocity', '设置开普勒速度'],
  ['modify quantity', '修改物理量'],
  ['Perlin noise', '柏林噪声'],
  ['N-body ICs', '多体初态'],
  ['polytrope ICs', '多方初态'],
  ['isothermal sphere ICs', '等温球初态'],
  ['galaxy ICs', '星系初态'],
  ['material', '材料'],
  ['basalt', '玄武岩'],
  ['ice', '冰'],
  ['olivine', '橄榄石'],
  ['iron', '铁'],
  ['hydrogen gas', '氢气'],
  ['optimize timestepping', '优化时间步长'],
  ['join', '合并'],
  ['orbit', '轨道'],
  ['multi join', '多重合并'],
  ['transform', '变换'],
  ['scatter', '散布'],
  ['center', '居中'],
  ['change material', '更换材料'],
  ['collision setup', '碰撞设置'],
  ['smoothed-to-solid handoff', '平滑固化交接'],
  ['merge overlapping particles', '合并重叠粒子'],
  ['extract component', '提取成分'],
  ['remove particles', '移除粒子'],
  ['merge components', '合并成分'],
  ['extract particles in domain', '提取域内粒子'],
  ['emplace components', '布置成分'],
  ['subsampler', '重采样'],
  ['compare', '比较']
]);

// 设置项中文名（M2 首批，未覆盖的回退英文原名）
const SETTING_LABEL: Map<string, string> = new Map<string, string>([
  ['Dimensions', '维度'],
  ['Type', '类型'],
  ['Radius', '半径'],
  ['Center', '中心'],
  ['Center value', '中心取值'],
  ['Center [km]', '中心 [km]'],
  ['Speed', '速度'],
  ['Velocity', '速度'],
  ['Density', '密度'],
  ['Density [kg/m^3]', '密度 [kg/m³]'],
  ['Mass', '质量'],
  ['Angle', '角度'],
  ['Size', '尺寸'],
  ['Scale', '缩放'],
  ['Factor', '系数'],
  ['Enabled', '启用'],
  ['Enable', '启用'],
  ['File name', '文件名'],
  ['File', '文件'],
  ['File mask', '文件掩码'],
  ['Directory', '目录'],
  ['Material', '材料'],
  ['Name', '名称'],
  ['Algorithm', '算法'],
  ['Resolution', '分辨率'],
  ['Iterations', '迭代次数'],
  ['Distribution', '分布'],
  ['Fraction', '比例'],
  ['Height [km]', '高度 [km]'],
  ['Width [km]', '宽度 [km]'],
  ['Length [km]', '长度 [km]'],
  ['Radius [km]', '半径 [km]'],
  ['Radius', '半径'],
  ['Name of the created body', '生成天体名称'],
  ['Body name', '天体名称'],
  ['Profile', '剖面'],
  ['Density profile', '密度剖面'],
  ['Particle count', '粒子数'],
  ['Divisions', '分割数'],
  ['Temperature', '温度'],
  ['Rotation period [h]', '自转周期 [h]'],
  ['Differentiation', '分层程度'],
  ['Core density', '核心密度'],
  ['Core radius fraction', '核心半径比例'],
  ['Grid dimensions', '网格尺寸'],
  ['Grid start [km]', '网格起点 [km]'],
  ['Grid end [km]', '网格终点 [km]'],
  ['Isotropic', '各向同性'],
  ['Rotation', '旋转'],
  ['Axis', '轴'],
  ['Seed', '随机种子'],
  ['Quantity', '物理量'],
  ['Surface gravity', '表面重力'],
  ['Include attractors', '包含吸引子'],
  ['Enable soft-body', '启用软体'],
  ['Component index', '分量索引']
]);

const CATEGORY_SETTING_LABEL: Map<string, string> = new Map<string, string>([
  ['Generic', '通用'],
  ['generic', '通用'],
  ['geometry', '几何'],
  ['particles', '粒子'],
  ['output', '输出'],
  ['input', '输入'],
  ['material', '材料'],
  ['simulation', '模拟'],
  ['solver', '求解器'],
  ['timestepping', '时间步进'],
  ['forces', '作用力'],
  ['initial conditions', '初始条件'],
  ['numerical', '数值'],
  ['distribution', '分布'],
  ['camera', '相机'],
  ['materials', '材料'],
  ['particle operators', '粒子算子'],
  ['simulations', '模拟'],
  ['rendering', '渲染'],
  ['presets', '预设'],
  ['initial conditions', '初始条件'],
  ['io', '输入输出'],
  ['geometry', '几何'],
  ['Geometry', '几何'],
  ['Particles', '粒子'],
  ['Output', '输出'],
  ['Input', '输入'],
  ['Material', '材料'],
  ['Simulation', '模拟'],
  ['Solver', '求解器'],
  ['Timestepping', '时间步进'],
  ['Forces', '作用力'],
  ['Collision handling', '碰撞处理'],
  ['Artificial viscosity', '人工粘性'],
  ['Statistics', '统计'],
  ['Initial conditions', '初始条件'],
  ['Numerical', '数值'],
  ['Distribution', '分布'],
  ['Camera', '相机'],
  ['Templates', '模板']
]);

// 动效总开关：减少动效时所有时长归零（系统级开关未在官方文档中暴露，先用应用内偏好）
let MOTION_SCALE: number = 1;

function durMs(ms: number): number {
  return MOTION_SCALE === 0 ? 0 : ms;
}

const DUR_FAST: number = 120;
const DUR_BASE: number = 180;
const DUR_SLOW: number = 220;

@Extend(Text)
function zoomBtn() {
  .fontSize(13)
  .fontColor('#3c4149')
  .width(26)
  .height(24)
  .textAlign(TextAlign.Center)
  .borderRadius(6)
  .stateStyles({
    normal: { .backgroundColor(Color.Transparent) },
    hovered: { .backgroundColor('#f2f4f7') },
    pressed: { .backgroundColor('#e6effd') }
  })
}

@Extend(Text)
function menuStyle() {
  .fontSize(14)
  .fontColor('#1f2328')
  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  .borderRadius(6)
  .stateStyles({
    normal: { .backgroundColor(Color.Transparent) },
    pressed: { .backgroundColor('#e6effd') },
    hovered: { .backgroundColor('#f2f4f7') }
  })
}

@Entry
@Component
struct ArkMain {
  @State private groups: CategoryGroup[] = [];
  @State private bridgeVersion: string = '';
  @State private selectedNode: number = -1;
  @State private collapsed: boolean = false;
  @State private appeared: boolean = false;
  @State private nodes: GraphNode[] = [];
  @State private links: GraphLink[] = [];
  @State private nextId: number = 1;
  @State @Watch('onLinkVersionChanged') private linkVersion: number = 0;
  @State @Watch('onPreviewVersionChanged') private pvTick: number = 0;
  @State private linkFrom: number = -1;
  @State private settings: SettingCategory[] = [];
  @State private pendingValue: string = '';
  private pendingByKey: Map<string, string> = new Map<string, string>();
  private pendingTimers: Map<string, number> = new Map<string, number>();
  @State private toasts: AppNotice[] = [];
  @State private history: AppNotice[] = [];
  @State private unread: number = 0;
  @State private showHistory: boolean = false;
  @State private reduceMotion: boolean = false;
  @State private openMenu: string = '';
  @State private hoverTop: string = '';
  @State private hoverCtx: number = -1;
  @State private hoverPanel: string = '';
  @State private leftW: number = 230;
  @State private rightW: number = 320;
  @State private rightCollapsed: boolean = false;
  @State private paneListH: number = 520;
  private previewDragging: boolean = false;
  private rotateSkip: number = 0;
  @State private previewPix: image.PixelMap | null = null;
  private previewPixBusy: boolean = false;
  private lastPixKey: string = '';
  private previewPixW: number = 0;
  private previewPixH: number = 0;
  private dragTick: number = 0;
  private perfCount: number = 0;
  @State private dragSide: number = 0;
  @State private hoverDivider: number = 0;
  @State private hoverCollapse: boolean = false;
  private lastDragX: number = 0;
  @State private menuFocus: string = '';
  private menuCloseTimer: number = -1;
  private menuHoverKeep: boolean = false;
  @State private autoRotate: boolean = false;
  @State private ctxNode: number = -1;
  @State private ctxWX: number = 0;
  @State private ctxWY: number = 0;
  @State private panX: number = 0;
  @State private panY: number = 0;
  @State private zoom: number = 1;
  private lastPanX: number = 0;
  private lastPanY: number = 0;
  private rotateTimer: number = -1;
  @State private canvasTab: number = 0;
  @State private previewVersion: number = 0;
  @State private previewKind: string = '';
  @State private previewCount: number = 0;
  @State private previewError: string = '';
  @State private previewLoading: boolean = false;
  @State private exportVisible: boolean = false;
  @State private exportMode: number = 0;      // 0 = 离线渲染(B)，1 = 录制预览(A)
  @State private recording: boolean = false;
  @State private simRunning: boolean = false;
  @State private simPaused: boolean = false;
  @State private simTime: number = 0;
  @State private simSteps: number = 0;
  @State private simParticles: number = 0;
  @State private simRecording: boolean = false;
  @State private simRecFrames: number = 0;
  private simRecPath: string = '';
  private simTimer: number = -1;
  @State private recordedFrames: number = 0;
  private recordTimer: number = -1;
  private recordPath: string = '';
  private recordWarned: boolean = false;
  @State private exportOrientation: number = 0;
  @State private exportResolution: number = 1;
  @State private exportFps: number = 30;
  @State private exportBitrate: number = 8;
  @State private exportFrames: number = 120;
  @State private exportQuality: number = 2;
  @State private exportPreset: number = 1;
  @State private exportName: string = 'opensph-export';
  @State private exportRunning: boolean = false;
  @State private exportProgress: number = 0;
  @State private exportStatusText: string = '';
  private exportStartMs: number = 0;
  @State private exportEtaText: string = '';
  private exportTimer: number = -1;

  @State private yaw: number = 0.7;
  @State private pitch: number = 0.45;
  private previewPts: number[] = [];
  private previewBounds: number[] = [0, 0, 0, 0, 0, 0];
  private previewCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private noticeService: NoticeService = NoticeService.get();
  @State private settingsNode: number = -1;
  @State private linkX: number = 0;
  @State private linkY: number = 0;
  private linkCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  onLinkVersionChanged(): void {
    this.drawLinks();
  }

  onPreviewVersionChanged(): void {
    this.drawPreview();
  }

  private loadPreview(): void {
    const node: GraphNode | undefined = this.nodeById(this.selectedNode);
    if (!node || node.handle < 0) {
      this.previewError = '请选择一个节点';
      this.previewPts = [];
      this.previewCount = 0;
      this.previewKind = '';
      this.pvTick += 1;
      return;
    }
    this.previewLoading = true;
    this.previewError = '';
    // 让加载态先渲染一帧
    setTimeout(() => {
      try {
        const raw: string = String(ark.previewPoints(node.handle, 4000));
        interface PreviewData {
          kind?: string;
          count?: number;
          bounds?: number[];
          points?: number[];
          error?: string;
        }
        const data: PreviewData = JSON.parse(raw) as PreviewData;
        if (data.error !== undefined) {
          this.previewError = String(data.error);
          this.previewPts = [];
          this.previewCount = 0;
          this.previewKind = '';
        } else {
          this.previewPts = data.points ?? [];
          this.previewBounds = data.bounds ?? [0, 0, 0, 0, 0, 0];
          this.previewCount = data.count ?? 0;
          this.previewKind = data.kind ?? '';
        }
      } catch (e) {
        this.previewError = '预览失败：' + String(e);
        this.previewPts = [];
      }
      this.previewLoading = false;
      this.refreshPixel(this.yaw, this.pitch, true);
      this.pvTick += 1;
    }, 30);
  }

  private drawPreview(): void {
    const ctx: CanvasRenderingContext2D = this.previewCtx;
    const W: number = ctx.width;
    const H: number = ctx.height;
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = '#101418';
    ctx.fillRect(0, 0, W, H);
    if (this.previewPts.length < 3) {
      return;
    }
    // 直接用点集算包围盒：实时快照不会更新 previewBounds（那是静态预览留下的）
    let b: number[] = this.previewBounds;
    {
      let minx: number = Number.POSITIVE_INFINITY, miny: number = Number.POSITIVE_INFINITY, minz: number = Number.POSITIVE_INFINITY;
      let maxx: number = Number.NEGATIVE_INFINITY, maxy: number = Number.NEGATIVE_INFINITY, maxz: number = Number.NEGATIVE_INFINITY;
      for (let i = 0; i + 2 < this.previewPts.length; i += 3) {
        const x: number = this.previewPts[i], y: number = this.previewPts[i + 1], z: number = this.previewPts[i + 2];
        if (x < minx) { minx = x; }
        if (y < miny) { miny = y; }
        if (z < minz) { minz = z; }
        if (x > maxx) { maxx = x; }
        if (y > maxy) { maxy = y; }
        if (z > maxz) { maxz = z; }
      }
      if (Number.isFinite(minx) && Number.isFinite(maxx)) {
        b = [minx, miny, minz, maxx, maxy, maxz];
      }
    }
    const cx: number = (b[0] + b[3]) * 0.5;
    const cy: number = (b[1] + b[4]) * 0.5;
    const cz: number = (b[2] + b[5]) * 0.5;
    let radius: number = 0;
    for (let i = 0; i + 2 < this.previewPts.length; i += 3) {
      const dx: number = this.previewPts[i] - cx;
      const dy: number = this.previewPts[i + 1] - cy;
      const dz: number = this.previewPts[i + 2] - cz;
      const d: number = Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (d > radius) {
        radius = d;
      }
    }
    if (radius <= 0) {
      radius = 1;
    }
    const scale: number = Math.min(W, H) * 0.42 / radius;
    const cyaw: number = Math.cos(this.yaw);
    const syaw: number = Math.sin(this.yaw);
    const cpitch: number = Math.cos(this.pitch);
    const spitch: number = Math.sin(this.pitch);
    // 先把所有点投影并按深度排序（远→近），再用半径随深度变化的柔和圆点叠加，
    // 累加出的中心更亮、边缘更暗，观感接近体渲染，而不是一片硬方块。
    const n: number = Math.floor(this.previewPts.length / 3);
    const sxArr: number[] = new Array<number>(n);
    const syArr: number[] = new Array<number>(n);
    const dzArr: number[] = new Array<number>(n);
    const order: number[] = new Array<number>(n);
    for (let k = 0; k < n; k++) {
      const i: number = k * 3;
      const x0: number = this.previewPts[i] - cx;
      const y0: number = this.previewPts[i + 1] - cy;
      const z0: number = this.previewPts[i + 2] - cz;
      const x1: number = x0 * cyaw - y0 * syaw;
      const y1: number = x0 * syaw + y0 * cyaw;
      const y2: number = y1 * cpitch - z0 * spitch;
      const z2: number = y1 * spitch + z0 * cpitch;
      sxArr[k] = W * 0.5 + x1 * scale;
      syArr[k] = H * 0.5 - z2 * scale;
      dzArr[k] = y2 / radius;      // -1 远 ... +1 近
      order[k] = k;
    }
    order.sort((a: number, b: number): number => dzArr[a] - dzArr[b]);
    // 光照：用「点相对几何中心的方向」作近似法线（球/椭球精确，其他形状为近似），
    // 叠加 Lambert 漫反射 + Blinn-Phong 高光，得到有体积感的明暗过渡。
    // 点少时用更大的点径，避免小天线体渲染成稀疏点阵；点多时收紧保持细节
    const densityScale: number = Math.min(2.4, Math.max(1, Math.sqrt(1200 / Math.max(1, n))));
    const baseR: number = Math.max(1.8, Math.min(W, H) * 0.0042) * densityScale;
    const lx: number = 0.42;
    const ly: number = 0.52;
    const lz: number = 0.74;
    const ln: number = Math.sqrt(lx * lx + ly * ly + lz * lz);
    const Lx: number = lx / ln;
    const Ly: number = ly / ln;
    const Lz: number = lz / ln;
    // 性能关键：Canvas 2D 上每次 beginPath/arc/fill 都是独立绘制调用，
    // 逐点绘制 4000 个点会把主线程堵死（实测拖动直接卡死）。
    // 这里按颜色量化成若干桶，每个桶只做一次 fill，绘制调用从 N 降到约 10。
    const BUCKETS: number = 10;
    const bucketX: number[][] = [];
    const bucketY: number[][] = [];
    const bucketR: number[][] = [];
    for (let b = 0; b < BUCKETS; b++) {
      bucketX.push([]);
      bucketY.push([]);
      bucketR.push([]);
    }
    const bucketColor: string[] = [];
    // 点数在任何交互状态下都保持一致（拖动时也不降载）：
    // 之前按拖动降采样会让画面突然变稀疏，观感像故障，已废弃。
    const stride: number = 1;
    for (let oi = 0; oi < n; oi += stride) {
      const k: number = order[oi];
      const i: number = k * 3;
      const px: number = this.previewPts[i] - cx;
      const py: number = this.previewPts[i + 1] - cy;
      const pz: number = this.previewPts[i + 2] - cz;
      const nx: number = px * cyaw - py * syaw;
      const ny: number = px * syaw + py * cyaw;
      const nz: number = ny * cpitch - pz * spitch;
      const nn: number = Math.max(1e-6, Math.sqrt(nx * nx + ny * ny + nz * nz));
      const ux: number = nx / nn;
      const uy: number = ny / nn;
      const uz: number = nz / nn;
      const diff: number = Math.max(0, ux * Lx + uy * Ly + uz * Lz);
      const hx: number = Lx;
      const hy: number = Ly;
      const hz: number = Lz + 1;
      const hn: number = Math.sqrt(hx * hx + hy * hy + hz * hz);
      const spec: number = Math.pow(Math.max(0, (ux * hx + uy * hy + uz * hz) / hn), 16);
      const dn: number = (dzArr[k] + 1) * 0.5;
      const lum: number = Math.min(1, 0.22 + 0.95 * diff + 0.35 * spec);
      const rr: number = Math.min(1, Math.sqrt(px * px + py * py + pz * pz) / radius);
      let mr: number = 0;
      let mg: number = 0;
      let mb: number = 0;
      if (rr < 0.35) {
        const t: number = rr / 0.35;
        mr = 40 + 130 * t;
        mg = 10 + 30 * t;
        mb = 105 + 20 * t;
      } else if (rr < 0.7) {
        const t: number = (rr - 0.35) / 0.35;
        mr = 170 + 75 * t;
        mg = 40 + 90 * t;
        mb = 125 - 55 * t;
      } else {
        const t: number = (rr - 0.7) / 0.3;
        mr = 245 + 10 * t;
        mg = 130 + 110 * t;
        mb = 70 + 120 * t;
      }
      // 颜色按亮度量化到 10 档
      const q: number = Math.min(BUCKETS - 1, Math.max(0, Math.floor(lum * (BUCKETS - 1))));
      const cr: number = Math.min(255, Math.floor(mr * lum + 240 * spec));
      const cg: number = Math.min(255, Math.floor(mg * lum + 240 * spec));
      const cbl: number = Math.min(255, Math.floor(mb * lum + 230 * spec));
      bucketColor[q] = `rgba(${cr},${cg},${cbl},${Math.min(1, 0.20 + 0.34 * dn).toFixed(3)})`;
      bucketX[q].push(sxArr[k]);
      bucketY[q].push(syArr[k]);
      bucketR[q].push(baseR * (0.6 + 0.8 * dn));
    }
    for (let b = 0; b < BUCKETS; b++) {
      const xs: number[] = bucketX[b];
      if (xs.length === 0) {
        continue;
      }
      ctx.beginPath();
      ctx.fillStyle = bucketColor[b] ?? 'rgba(150,180,255,0.3)';
      for (let t = 0; t < xs.length; t++) {
        ctx.moveTo(xs[t] + bucketR[b][t], bucketY[b][t]);
        ctx.arc(xs[t], bucketY[b][t], bucketR[b][t], 0, Math.PI * 2);
      }
      ctx.fill();
    }
  }

  private async refreshPixel(yaw: number, pitch: number, force: boolean): Promise<void> {
    const handle: number = this.selectedNode >= 0 && this.nodeById(this.selectedNode) !== undefined
      ? this.nodeById(this.selectedNode)!.handle : -1;
    if (handle < 0) {
      return;
    }
    const key: string = `${handle}:${yaw.toFixed(3)}:${pitch.toFixed(3)}`;
    if (!force && key === this.lastPixKey) {
      return;
    }
    if (this.previewPixBusy) {
      return;
    }
    this.previewPixBusy = true;
    this.lastPixKey = key;
    const t0: number = Date.now();
    try {
      const W: number = 1000;
      const H: number = 1000;
      const tCpp: number = Date.now();
      const buf: ArrayBuffer = ark.renderSplat(handle, yaw, pitch, W, H) as ArrayBuffer;
      const dtCpp: number = Date.now() - tCpp;
      if (buf === undefined || buf === null || buf.byteLength !== W * H * 4) {
        this.previewPixBusy = false;
        return;
      }
      const opts: image.InitializationOptions = {
        size: { width: W, height: H },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true
      };
      const tPm: number = Date.now();
      let pm: image.PixelMap | null = this.previewPix;
      if (pm === null || this.previewPixW !== W || this.previewPixH !== H) {
        pm = await image.createPixelMap(buf, opts);
        this.previewPixW = W;
        this.previewPixH = H;
      } else {
        await pm.writeBufferToPixels(buf);
      }
      const dtPm: number = Date.now() - tPm;
      this.previewPix = pm;
      hilog.info(0x0000, 'OpenSPHPerf', `cpp=${dtCpp}ms pixelmap=${dtPm}ms total=${Date.now() - t0}ms`);
    } catch (e) {
      const err = e as Error;
      hilog.error(0x0000, 'OpenSPHPerf', `renderSplat failed: ${err.message ?? String(e)}`);
    }
    this.previewPixBusy = false;
  }

  private drawLinks(): void {
    const W: number = this.linkCtx.width;
    const H: number = this.linkCtx.height;
    this.linkCtx.clearRect(0, 0, W, H);
    this.linkCtx.lineWidth = 2;
    this.linkCtx.strokeStyle = '#8ab4f8';
    for (const l of this.links) {
      const from: GraphNode | undefined = this.nodeById(l.from);
      const to: GraphNode | undefined = this.nodeById(l.to);
      if (!from || !to) {
        continue;
      }
      this.strokeBezier(this.linkCtx,
        from.x + CARD_W,
        from.y + CARD_H / 2,
        to.x,
        to.y + CARD_H / 2,
        false);
    }
    if (this.linkFrom >= 0) {
      const from: GraphNode | undefined = this.nodeById(this.linkFrom);
      if (from) {
        this.linkCtx.strokeStyle = '#0b57d0';
        this.linkCtx.setLineDash([6, 4]);
        this.strokeBezier(this.linkCtx, from.x + CARD_W, from.y + CARD_H / 2, this.linkX, this.linkY, true);
        this.linkCtx.setLineDash([]);
      }
    }
  }

  private distanceToSegment(px: number, py: number, x1: number, y1: number, x2: number, y2: number): number {
    const dx: number = x2 - x1;
    const dy: number = y2 - y1;
    const len2: number = dx * dx + dy * dy;
    if (len2 < 1) {
      return Math.sqrt((px - x1) * (px - x1) + (py - y1) * (py - y1));
    }
    let t: number = ((px - x1) * dx + (py - y1) * dy) / len2;
    t = Math.max(0, Math.min(1, t));
    const cx: number = x1 + t * dx;
    const cy: number = y1 + t * dy;
    return Math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  private strokeBezier(ctx: CanvasRenderingContext2D, x1: number, y1: number, x2: number, y2: number, temp: boolean): void {
    const dx: number = Math.max(40, Math.abs(x2 - x1) * 0.5);
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.bezierCurveTo(x1 + dx, y1, x2 - dx, y2, x2, y2);
    ctx.stroke();
  }

  private async loadMotionPref(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref: preferences.Preferences = await preferences.getPreferences(ctx, 'opensph_ui');
      this.reduceMotion = (await pref.get('reduceMotion', false)) as boolean;
      MOTION_SCALE = this.reduceMotion ? 0 : 1;
    } catch (e) {
      hilog.warn(0x0000, 'ArkMain', 'loadMotionPref failed');
    }
  }

  private async savePaneWidths(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref: preferences.Preferences = await preferences.getPreferences(ctx, 'opensph_ui');
      await pref.put('leftW', this.leftW);
      await pref.put('rightW', this.rightW);
      await pref.flush();
    } catch (e) {
      hilog.warn(0x0000, 'ArkMain', 'savePaneWidths failed');
    }
  }

  private async loadPaneWidths(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref: preferences.Preferences = await preferences.getPreferences(ctx, 'opensph_ui');
      const l: preferences.ValueType = await pref.get('leftW', 230);
      const r: preferences.ValueType = await pref.get('rightW', 320);
      this.leftW = Number(l);
      this.rightW = Number(r);
    } catch (e) {
      hilog.warn(0x0000, 'ArkMain', 'loadPaneWidths failed');
    }
  }

  private async saveMotionPref(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref: preferences.Preferences = await preferences.getPreferences(ctx, 'opensph_ui');
      await pref.put('reduceMotion', this.reduceMotion);
      await pref.flush();
    } catch (e) {
      hilog.warn(0x0000, 'ArkMain', 'saveMotionPref failed');
    }
  }

  private async openPreviewWindow(): Promise<void> {
    try {
      const stage: window.WindowStage | null = WindowHolder.stage;
      if (stage === null) {
        this.noticeService.warn('无法弹出预览', 'WindowStage 未就绪');
        return;
      }
      if (WindowHolder.sub !== null) {
        await WindowHolder.sub.show();
        this.noticeService.info('预览窗口已存在', '已切到前台');
        return;
      }
      const sel: GraphNode | undefined = this.selectedNode >= 0 ? this.nodeById(this.selectedNode) : undefined;
      WindowHolder.previewHandle = sel !== undefined ? sel.handle : -1;
      const sub: window.Window = await stage.createSubWindow('opensphPreview');
      WindowHolder.sub = sub;
      await sub.setUIContent('pages/PreviewWindow');
      await sub.resize(760, 520);
      await sub.show();
      hilog.info(0x0000, 'OpenSPHWin', 'sub window created 760x520');
      this.noticeService.success('已弹出预览窗口', '760 × 520');
    } catch (e) {
      const err = e as Error;
      hilog.error(0x0000, 'OpenSPHWin', `createSubWindow failed: ${err.message ?? String(e)}`);
      this.noticeService.error('弹出预览失败', err.message ?? String(e));
    }
  }

  private runPaneSelfTest(): void {
    hilog.info(0x0000, 'OpenSPHPane', `start leftW=${this.leftW} rightW=${this.rightW} leftCollapsed=${this.collapsed} rightCollapsed=${this.rightCollapsed}`);
    setTimeout(() => {
      this.leftW = 310;
      this.collapsed = false;
      hilog.info(0x0000, 'OpenSPHPane', `wide-left leftW=${this.leftW}`);
    }, 1200);
    setTimeout(() => {
      this.rightW = 380;
      this.rightCollapsed = false;
      hilog.info(0x0000, 'OpenSPHPane', `wide-right rightW=${this.rightW}`);
    }, 3200);
    setTimeout(() => {
      this.leftW = 230;
      this.rightW = 320;
      this.savePaneWidths();
      hilog.info(0x0000, 'OpenSPHPane', `reset leftW=${this.leftW} rightW=${this.rightW}`);
    }, 6500);
  }

  private calcPaneListHeight(): void {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const h: number = this.getUIContext().px2vp(d.height);
      this.paneListH = Math.max(240, Math.floor(h) - 250);
      hilog.info(0x0000, 'ArkMain', `paneListH=${this.paneListH} (vp height=${Math.floor(h)})`);
    } catch (e) {
      this.paneListH = 520;
    }
  }

  // 尝试跟随系统「动画缩放 = 0」（减弱动效）。
  // 说明：@ohos.settings 的 ANIMATOR_DURATION_SCALE 常量自 API 21 起已废弃，
  // 这里按底层键名直接读取；读不到就保持应用内开关的行为。
  private readSystemMotionPref(): void {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const raw: string = sysSettings.getValueSync(ctx, 'animator_duration_scale', '1');
      const scale: number = Number(raw);
      hilog.info(0x0000, 'OpenSPHMotion', `system animator_duration_scale='${raw}'`);
      if (Number.isFinite(scale) && scale === 0) {
        this.reduceMotion = true;
        MOTION_SCALE = 0;
        hilog.info(0x0000, 'OpenSPHMotion', 'system requests no animation -> reduceMotion=true');
      }
    } catch (e) {
      const err = e as Error;
      hilog.info(0x0000, 'OpenSPHMotion', `system motion pref unavailable: ${err.message ?? String(e)}`);
    }
  }

  aboutToAppear(): void {
    this.loadMotionPref();
    this.readSystemMotionPref();
    this.calcPaneListHeight();
    this.loadPaneWidths();
    this.noticeService.subscribe((notice: AppNotice) => {
      this.history = this.history.concat([notice]).slice(-40);
      this.unread += 1;
      this.toasts = this.toasts.concat([notice]).slice(-4);
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseIn }, () => {
          this.toasts = this.toasts.filter((t: AppNotice) => t.id !== notice.id);
        });
      }, 3600);
    });
    this.loadCatalog();
    this.getUIContext().animateTo({ duration: durMs(DUR_SLOW), curve: Curve.EaseOut }, () => {
      this.appeared = true;
    });
  }

  private loadCatalog(): void {
    try {
      const raw: string = String(ark.version());
      // 桥接库返回英文版本串，这里转成中文展示（内核本身不做本地化）
      this.bridgeVersion = raw.replace('OpenSPH ark bridge', 'OpenSPH 内核桥接')
        .replace('core-only', '仅核心');
      const list: JobEntry[] = JSON.parse(String(ark.jobCatalog())) as JobEntry[];
      const map: Map<string, JobEntry[]> = new Map<string, JobEntry[]>();
      for (const item of list) {
        const key: string = item.category.length > 0 ? item.category : 'other';
        if (!map.has(key)) {
          map.set(key, []);
        }
        map.get(key)!.push(item);
      }
      const out: CategoryGroup[] = [];
      map.forEach((items: JobEntry[], name: string) => {
        out.push({ name: name, items: items });
      });
      out.sort((a: CategoryGroup, b: CategoryGroup) => a.name.localeCompare(b.name));
      this.groups = out;
    } catch (e) {
      this.bridgeVersion = '桥接加载失败: ' + JSON.stringify(e);
      this.noticeService.error('桥接加载失败', String(e));
    }
  }

  private label(category: string): string {
    return CATEGORY_LABEL.get(category) ?? category;
  }

  private nodeTitle(className: string): string {
    return NODE_LABEL.get(className) ?? className;
  }

  // 一键预设：把「方向/分辨率/帧率/画质/时长」一次配好，省掉逐项点选
  private applyExportPreset(id: number): void {
    if (id === 0) {
      // 快速预览片：720p 横屏 / 24fps / 3 秒 / 快速画质
      this.exportOrientation = 0;
      this.exportResolution = 0;
      this.exportFps = 24;
      this.exportFrames = 72;
      this.exportQuality = 1;
      this.exportBitrate = 4;
    } else if (id === 1) {
      // 标准成片：1080p 横屏 / 30fps / 5 秒 / 标准画质
      this.exportOrientation = 0;
      this.exportResolution = 1;
      this.exportFps = 30;
      this.exportFrames = 150;
      this.exportQuality = 2;
      this.exportBitrate = 8;
    } else {
      // 高质量 4K：4K 横屏 / 30fps / 5 秒 / 高画质（2× 采样）
      this.exportOrientation = 0;
      this.exportResolution = 3;
      this.exportFps = 30;
      this.exportFrames = 150;
      this.exportQuality = 3;
      this.exportBitrate = 20;
    }
    this.exportPreset = id;
    hilog.info(0x0000, 'OpenSPHExport', `preset=${id} res=${this.exportResolution} fps=${this.exportFps} frames=${this.exportFrames} quality=${this.exportQuality}`);
  }

  private exportSize(): number[] {
    const base: number[] = this.exportResolution === 0 ? [1280, 720]
      : this.exportResolution === 1 ? [1920, 1080]
      : this.exportResolution === 2 ? [2560, 1440] : [3840, 2160];
    if (this.exportOrientation === 1) {
      return [base[1], base[0]];
    }
    if (this.exportOrientation === 2) {
      return [base[1], base[1]];
    }
    return base;
  }

  private startRecordingPreview(): void {
    const w: number = Math.floor(this.previewCtx.width / 2) * 2;
    const h: number = Math.floor(this.previewCtx.height / 2) * 2;
    if (w <= 0 || h <= 0) {
      // 预览画布还没布局（当前在节点图页签）：自动切到预览页签，布局完成后再真正开始录制。
      // 之前这里只弹一个瞬时提示就返回，用户会觉得按钮坏了。
      if (this.canvasTab !== 1) {
        this.noticeService.info('正在切换到预览', '录制需要预览画布尺寸');
        this.canvasTab = 1;
        setTimeout(() => {
          this.startRecordingPreview();
        }, 400);
        return;
      }
      this.noticeService.warn('无法录制', '预览画布尺寸为 0，请稍后重试');
      return;
    }
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const dir: string = ctx.filesDir + '/videos';
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
    } catch (e) {
      // 已存在
    }
    const safeName: string = this.exportName.length > 0 ? this.exportName : 'opensph-recording';
    const path: string = `${dir}/${safeName}.mp4`;
    if (fs.accessSync(path)) {
      try {
        fs.unlinkSync(path);
      } catch (e) {
        // ignore
      }
    }
    interface RecordOptions {
      width: number;
      height: number;
      fps: number;
      bitrate: number;
      path: string;
    }
    const options: RecordOptions = {
      width: w,
      height: h,
      fps: 15,
      bitrate: this.exportBitrate * 1000000,
      path: path
    };
    let started: boolean = false;
    try {
      interface StartResult {
        ok: boolean;
        error?: string;
      }
      const res: StartResult = JSON.parse(String(ark.startCloudRecording(this.nodeById(this.selectedNode)!.handle, JSON.stringify(options)))) as StartResult;
      started = res.ok;
      if (!started) {
        this.noticeService.error('录制启动失败', res.error ?? '');
        return;
      }
    } catch (e) {
      this.noticeService.error('录制启动失败', String(e));
      return;
    }
    this.recordPath = path;
    this.recording = true;
    this.recordedFrames = 0;
    this.recordWarned = false;
    this.noticeService.info('开始录制', `${w} × ${h} · 15 fps`);
    this.recordTimer = setInterval(() => {
      try {
        ark.recordCloudFrame(this.yaw, this.pitch);
        this.recordedFrames += 1;
      } catch (e) {
        if (!this.recordWarned) {
          this.recordWarned = true;
          const err = e as Error;
          hilog.error(0x0000, 'OpenSPHRec', `record frame failed: ${err.message ?? String(e)}`);
        }
      }
    }, 66);
  }

  private captureBusy: boolean = false;

  private async captureFrame(w: number, h: number): Promise<void> {
    if (this.captureBusy) {
      return;
    }
    this.captureBusy = true;
    try {
      const pm: image.PixelMap = this.previewCtx.getPixelMap(0, 0, w, h);
      const buf: ArrayBuffer = new ArrayBuffer(w * h * 4);
      await pm.readPixelsToBuffer(buf);
      ark.pushVideoFrame(buf);
      this.recordedFrames += 1;
      pm.release();
    } catch (e) {
      if (!this.recordWarned) {
        this.recordWarned = true;
        const err = e as Error;
        hilog.error(0x0000, 'OpenSPHRec', `frame capture failed: ${err.message ?? String(e)}`);
      }
    }
    this.captureBusy = false;
  }

  private stopRecordingPreview(): void {
    if (this.recordTimer >= 0) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
    this.recording = false;
    try {
      interface StopResult {
        ok: boolean;
        frames: number;
        bytes: number;
        error?: string;
      }
      const res: StopResult = JSON.parse(String(ark.stopRecording())) as StopResult;
      if (res.ok) {
        this.noticeService.success('录制完成', `${res.frames} 帧 · ${Math.round(res.bytes / 1024)} KB`);
        SystemNotifier.publish(103, 'OpenSPH 录制完成', `${this.exportName}.mp4（${res.frames} 帧）`);
        this.saveExportToPicker(this.recordPath, 'opensph-recording');
      } else {
        this.noticeService.error('录制失败', res.error ?? '未知错误');
      }
    } catch (e) {
      this.noticeService.error('录制结束失败', String(e));
    }
  }

  private startExport(): void {
    const node: GraphNode | undefined = this.nodeById(this.selectedNode);
    if (!node || node.handle < 0) {
      this.noticeService.warn('未选择节点', '请先在节点图中选择一个节点');
      return;
    }
    const size: number[] = this.exportSize();
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const dir: string = ctx.filesDir + '/videos';
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
    } catch (e) {
      // 目录已存在
    }
    const safeName: string = this.exportName.length > 0 ? this.exportName : 'opensph-export';
    const path: string = `${dir}/${safeName}.mp4`;
    if (fs.accessSync(path)) {
      try {
        fs.unlinkSync(path);
      } catch (e) {
        // ignore
      }
    }
    interface ExportOptions {
      width: number;
      height: number;
      fps: number;
      bitrate: number;
      frames: number;
      path: string;
      quality: number;
    }
    const options: ExportOptions = {
      width: size[0],
      height: size[1],
      fps: this.exportFps,
      bitrate: this.exportBitrate * 1000000,
      frames: this.exportFrames,
      path: path,
      quality: this.exportQuality
    };
    hilog.info(0x0000, 'OpenSPHExport', `start handle=${node.handle} ${JSON.stringify(options)}`);
    try {
      ark.startExportVideo(node.handle, JSON.stringify(options));
    } catch (e) {
      this.noticeService.error('导出失败', String(e));
      return;
    }
    this.exportRunning = true;
    this.exportProgress = 0;
    this.exportStartMs = Date.now();
    this.exportEtaText = '';
    this.exportStatusText = `渲染 0 / ${this.exportFrames} 帧`;
    this.pollExport();
  }

  private pollExport(): void {
    if (this.exportTimer >= 0) {
      clearTimeout(this.exportTimer);
      this.exportTimer = -1;
    }
    this.exportTimer = setTimeout(() => {
      interface ExportStatus {
        running: boolean;
        done: boolean;
        ok: boolean;
        rendered: number;
        total: number;
        error?: string;
        path?: string;
      }
      let st: ExportStatus | null = null;
      try {
        st = JSON.parse(String(ark.exportStatus())) as ExportStatus;
      } catch (e) {
        st = null;
      }
      if (st === null) {
        this.exportRunning = false;
        this.noticeService.error('导出状态读取失败', '');
        return;
      }
      this.exportProgress = st.total > 0 ? Math.min(1, st.rendered / st.total) : 0;
      const elapsed: number = Date.now() - this.exportStartMs;
      if (st.rendered > 0 && elapsed > 500 && st.rendered < st.total) {
        const perFrame: number = elapsed / st.rendered;
        const remainMs: number = Math.max(0, (st.total - st.rendered) * perFrame);
        const fps: number = 1000 / perFrame;
        const remainS: number = Math.ceil(remainMs / 1000);
        this.exportEtaText = `约 ${fps.toFixed(1)} 帧/秒 · 预计剩余 ${remainS} 秒`;
        this.exportStatusText = `渲染 ${st.rendered} / ${st.total} 帧`;
      } else {
        this.exportStatusText = `渲染 ${st.rendered} / ${st.total} 帧`;
      }
      if (st.running) {
        this.pollExport();
        return;
      }
      this.exportRunning = false;
      hilog.info(0x0000, 'OpenSPHExport', `done ok=${st.ok} rendered=${st.rendered}/${st.total} err=${st.error ?? ''} path=${st.path ?? ''}`);
      if (st.ok) {
        this.exportProgress = 1;
        this.exportStatusText = '导出完成';
        const totalS: number = Math.max(1, Math.round((Date.now() - this.exportStartMs) / 1000));
        this.exportEtaText = `用时 ${totalS} 秒`;
        this.noticeService.success('视频已生成', `${this.exportName}.mp4`);
        SystemNotifier.publish(101, 'OpenSPH 视频导出完成', `${this.exportName}.mp4 已保存到应用目录`);
        this.saveExportToPicker(st.path ?? '');
      } else {
        this.noticeService.error('导出失败', st.error ?? '未知错误');
        SystemNotifier.publish(102, 'OpenSPH 视频导出失败', st.error ?? '未知错误');
      }
    }, 300);
  }

  private async saveExportToPicker(srcPath: string, baseName: string = ''): Promise<void> {
    if (srcPath.length === 0) {
      return;
    }
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      const fileName: string = baseName.length > 0 ? baseName : this.exportName;
      options.newFileNames = [`${fileName}.mp4`];
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const uris: string[] = await viewPicker.save(options);
      if (uris.length === 0) {
        return;
      }
      const dest: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_WRITE);
      fs.copyFileSync(srcPath, dest.fd);
      fs.closeSync(dest);
      this.noticeService.success('已保存到所选位置', `${baseName.length > 0 ? baseName : this.exportName}.mp4`);
    } catch (e) {
      this.noticeService.warn('未保存到外部目录', '文件仍在应用目录中');
    }
  }

  private startSim(): void {
    const node: GraphNode | undefined = this.nodeById(this.selectedNode);
    if (!node || node.handle < 0) {
      this.noticeService.warn('未选择节点', '请先选择一个模拟节点');
      return;
    }
    try {
      interface OpResult {
        ok: boolean;
        error?: string;
      }
      const res: OpResult = JSON.parse(String(ark.runSimulation(node.handle, 0))) as OpResult;
      if (!res.ok) {
        this.noticeService.error('无法启动模拟', res.error ?? '');
        return;
      }
    } catch (e) {
      this.noticeService.error('无法启动模拟', String(e));
      return;
    }
    this.simRunning = true;
    this.simPaused = false;
    this.noticeService.info('模拟已启动', node.title);
    // 自动切到预览页签，运行中实时显示粒子演化
    this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
      this.canvasTab = 1;
    });
    this.pollSim();
  }

  private pollSim(): void {
    if (this.simTimer >= 0) {
      clearTimeout(this.simTimer);
      this.simTimer = -1;
    }
    this.simTimer = setTimeout(() => {
      interface SimStatus {
        running: boolean;
        paused: boolean;
        done: boolean;
        ok: boolean;
        time: number;
        steps: number;
        particles: number;
        recording: boolean;
        recFrames: number;
        error?: string;
      }
      let st: SimStatus | null = null;
      try {
        st = JSON.parse(String(ark.simulationStatus())) as SimStatus;
      } catch (e) {
        st = null;
      }
      if (st === null) {
        this.simRunning = false;
        return;
      }
      this.simRunning = st.running;
      this.simPaused = st.paused;
      this.simTime = st.time;
      this.simSteps = st.steps;
      this.simParticles = st.particles;
      // 运行中且停在预览页签时，实时刷新粒子快照
      if (st.running && this.canvasTab === 1) {
        this.refreshLiveSnapshot();
      }
      if (this.simRecording) {
        this.simRecFrames = st.recFrames;
      }
      if (st.running) {
        hilog.info(0x0000, 'OpenSPHSim', `tick t=${st.time} steps=${st.steps} particles=${st.particles} tab=${this.canvasTab}`);
        this.pollSim();
        return;
      }
      if (st.done) {
        hilog.info(0x0000, 'OpenSPHSim', `done ok=${st.ok} steps=${st.steps} t=${st.time} err=${st.error ?? ''}`);
        if (this.simRecording) {
          this.stopSimRec();
        }
        if (st.ok) {
          this.noticeService.success('模拟完成', `${st.steps} 步 · t = ${st.time.toFixed(3)}`);
          SystemNotifier.publish(201, 'OpenSPH 模拟完成', `${st.steps} 步，结束时间 ${st.time.toFixed(3)}`);
        } else {
          this.noticeService.error('模拟失败', st.error ?? '未知错误');
          SystemNotifier.publish(202, 'OpenSPH 模拟失败', st.error ?? '未知错误');
        }
      }
    }, 500);
  }

  private startSimRec(): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const dir: string = ctx.filesDir + '/videos';
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
    } catch (e) {
      // 已存在
    }
    const path: string = `${dir}/opensph-sim.mp4`;
    if (fs.accessSync(path)) {
      try {
        fs.unlinkSync(path);
      } catch (e) {
        // ignore
      }
    }
    interface RecOptions {
      width: number;
      height: number;
      fps: number;
      bitrate: number;
      every: number;
      path: string;
    }
    const options: RecOptions = {
      width: 1280,
      height: 720,
      fps: 15,
      bitrate: 6000000,
      every: 5,
      path: path
    };
    interface OpResult {
      ok: boolean;
      error?: string;
    }
    const res: OpResult = JSON.parse(String(ark.startSimRecording(JSON.stringify(options)))) as OpResult;
    if (!res.ok) {
      this.noticeService.warn('无法开始录制', res.error ?? '');
      return;
    }
    this.simRecPath = path;
    this.simRecording = true;
    this.simRecFrames = 0;
    this.noticeService.info('开始录制模拟', '每 5 步一帧 · 1280×720');
  }

  private stopSimRec(): void {
    if (!this.simRecording) {
      return;
    }
    this.simRecording = false;
    interface StopResult {
      ok: boolean;
      frames: number;
      bytes: number;
      error?: string;
    }
    const res: StopResult = JSON.parse(String(ark.stopSimRecording())) as StopResult;
    if (res.ok && res.frames > 0) {
      this.noticeService.success('模拟录制完成', `${res.frames} 帧 · ${Math.round(res.bytes / 1024)} KB`);
      SystemNotifier.publish(301, 'OpenSPH 模拟录制完成', `${res.frames} 帧已保存`);
      this.saveExportToPicker(this.simRecPath, 'opensph-sim');
    } else {
      this.noticeService.error('录制失败', res.error ?? '没有采集到帧');
    }
  }

  private toggleAutoRotate(): void {
    this.autoRotate = !this.autoRotate;
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
      this.rotateTimer = -1;
    }
    if (this.autoRotate) {
      this.rotateTimer = setInterval(() => {
        if (this.canvasTab !== 1) {
          return;
        }
        if (this.previewPts.length === 0) {
          return;
        }
        this.yaw += 0.03;
        this.pvTick += 1;
      }, 60);
      this.noticeService.info('自动旋转', '预览视角持续旋转');
    } else {
      this.noticeService.info('自动旋转', '已停止');
    }
  }

  private refreshLiveSnapshot(): void {
    try {
      interface Snapshot {
        count: number;
        step: number;
        points: number[];
      }
      const raw: string = String(ark.simSnapshot());
      hilog.info(0x0000, 'OpenSPHSnap', `len=${raw.length} head=${raw.substring(0, 40)} tail=${raw.substring(raw.length - 40)}`);
      const snap: Snapshot = JSON.parse(raw) as Snapshot;
      if (snap.count > 0) {
        this.previewPts = snap.points;
        this.previewKind = 'particles';
        this.previewCount = snap.count;
        this.previewError = '';
        this.pvTick += 1;
      }
    } catch (e) {
      const err = e as Error;
      hilog.error(0x0000, 'OpenSPHSnap', `snapshot failed: ${err.message ?? String(e)}`);
    }
  }

  private toggleSimPause(): void {
    hilog.info(0x0000, 'OpenSPHChip', 'pause clicked');
    this.simPaused = !this.simPaused;
    try {
      ark.setSimulationPaused(this.simPaused);
      this.noticeService.info(this.simPaused ? '已暂停' : '已继续', '');
    } catch (e) {
      // ignore
    }
  }

  private stopSim(): void {
    hilog.info(0x0000, 'OpenSPHChip', 'stop clicked');
    try {
      ark.stopSimulation();
      this.noticeService.info('已请求停止', '');
    } catch (e) {
      // ignore
    }
  }

  private async selfTest(): Promise<void> {
    this.noticeService.info('自检开始', '创建 IC + 模拟节点并连线');
    hilog.info(0x0000, 'OpenSPHSt', 'step1 create nodes');
    let icHandle: number = -1;
    let sphHandle: number = -1;
    try {
      icHandle = Number(ark.createNode('create monolithic body'));
      sphHandle = Number(ark.createNode('SPH run'));
    } catch (e) {
      this.noticeService.error('自检失败', '创建节点异常');
      return;
    }
    hilog.info(0x0000, 'OpenSPHSt', `step2 handles ic=${icHandle} sph=${sphHandle}`);
    if (icHandle < 0 || sphHandle < 0) {
      this.noticeService.error('自检失败', `节点创建失败 ic=${icHandle} sph=${sphHandle}`);
      return;
    }
    // 说明：不再在自检里改粒子数——setNodeSetting 曾导致 Cpp Crash（待查）
    hilog.info(0x0000, 'OpenSPHSt', 'step3 slots');
    interface SlotInfo {
      name: string;
      used: boolean;
      connected: boolean;
    }
    let connectedSlot: string = '';
    try {
      const slots: SlotInfo[] = JSON.parse(String(ark.nodeSlots(sphHandle))) as SlotInfo[];
      for (const slot of slots) {
        if (!slot.used || slot.connected) {
          continue;
        }
        interface OpResult {
          ok: boolean;
          error?: string;
        }
        const res: OpResult = JSON.parse(String(ark.connectNodes(icHandle, sphHandle, slot.name))) as OpResult;
        if (res.ok) {
          connectedSlot = slot.name;
          break;
        }
      }
    } catch (e) {
      connectedSlot = '';
    }
    hilog.info(0x0000, 'OpenSPHSt', `step4 slot=${connectedSlot}`);
    if (connectedSlot.length === 0) {
      this.noticeService.error('自检失败', '没有可连接的槽位');
      return;
    }
    this.noticeService.success('已连接', `槽位 ${connectedSlot}，开始运行`);
    interface OpResult2 {
      ok: boolean;
      error?: string;
    }
    hilog.info(0x0000, 'OpenSPHSt', 'step5 run');
    // 自检把结束时间放大到 60s，留出足够时间点录制/暂停
    const runRes: OpResult2 = JSON.parse(String(ark.runSimulation(sphHandle, 60.0))) as OpResult2;
    hilog.info(0x0000, 'OpenSPHSt', `step6 runResult ok=${runRes.ok} err=${runRes.error ?? ''}`);
    if (!runRes.ok) {
      this.noticeService.error('启动失败', runRes.error ?? '');
      return;
    }
    this.simRunning = true;
    this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
      this.canvasTab = 1;
    });
    this.pollSim();
  }

  private togglePalette(): void {
    this.getUIContext().animateTo({ duration: durMs(DUR_SLOW), curve: Curve.Friction }, () => {
      this.collapsed = !this.collapsed;
    });
  }

  private addNode(item: JobEntry): void {
    const offset: number = (this.nodes.length % 6) * 28;
    let handle: number = -1;
    try {
      handle = Number(ark.createNode(item.className));
      hilog.info(0x0000, 'ArkMain', 'createNode %{public}s -> %{public}d', item.className, handle);
    } catch (e) {
      handle = -1;
    }
    const node: GraphNode = new GraphNode(
      this.nextId,
      handle,
      item.className,
      this.nodeTitle(item.className),
      this.label(item.category),
      60 + offset,
      60 + offset
    );
    this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
      this.nextId += 1;
      this.nodes = this.nodes.concat([node]);
      this.selectedNode = node.id;
      this.settingsNode = -1;
      this.loadSettings(node.id);
      this.noticeService.success('已添加节点', `${node.title} · ${node.category}`);
    });
  }

  private removeNode(id: number): void {
    const node: GraphNode | undefined = this.nodeById(id);
    if (node) {
      this.noticeService.info('已删除节点', node.title);
    }
    if (node && node.handle >= 0) {
      try {
        ark.releaseNode(node.handle);
      } catch (e) {
        // ignore
      }
    }
    this.getUIContext().animateTo({ duration: durMs(DUR_FAST), curve: Curve.EaseIn }, () => {
      this.nodes = this.nodes.filter((n: GraphNode) => n.id !== id);
      this.links = this.links.filter((l: GraphLink) => l.from !== id && l.to !== id);
      this.linkVersion += 1;
      if (this.selectedNode === id) {
        this.selectedNode = -1;
      }
    });
  }

  private nodeById(id: number): GraphNode | undefined {
    for (const n of this.nodes) {
      if (n.id === id) {
        return n;
      }
    }
    return undefined;
  }

  private startLink(id: number): void {
    hilog.info(0x0000, 'OpenSPHLink', `start id=${id}`);
    const n: GraphNode | undefined = this.nodeById(id);
    if (!n) {
      return;
    }
    this.linkFrom = id;
    this.linkX = n.x + CARD_W;
    this.linkY = n.y + CARD_H / 2;
    this.linkVersion += 1;
  }

  private moveLink(id: number, dx: number, dy: number): void {
    const n: GraphNode | undefined = this.nodeById(id);
    if (!n) {
      return;
    }
    this.linkX = n.x + CARD_W + dx;
    this.linkY = n.y + CARD_H / 2 + dy;
    // 临时连线必须跟着指针走：Canvas 只在 linkVersion 变化时重绘
    this.linkVersion += 1;
  }

  private finishLink(id: number): void {
    hilog.info(0x0000, 'OpenSPHLink', `end id=${id} linkX=${this.linkX.toFixed(1)} linkY=${this.linkY.toFixed(1)} from=${this.linkFrom}`);
    if (this.linkFrom < 0) {
      return;
    }
    const from: number = this.linkFrom;
    let target: number = -1;
    let best: number = 60;
    for (const n of this.nodes) {
      if (n.id === from) {
        continue;
      }
      const px: number = n.x;
      const py: number = n.y + CARD_H / 2;
      const dist: number = Math.sqrt((px - this.linkX) * (px - this.linkX) + (py - this.linkY) * (py - this.linkY));
      if (dist < best) {
        best = dist;
        target = n.id;
      }
    }
    hilog.info(0x0000, 'OpenSPHLink', `target=${target} best=${best.toFixed(1)} nodes=${this.nodes.length}`);
    if (target < 0) {
      // 没落到端口：立即清掉临时连线，不留残影
      this.linkFrom = -1;
      this.linkVersion += 1;
      return;
    }
    this.linkFrom = -1;
    this.linkVersion += 1;
    for (const l of this.links) {
      if (l.from === from && l.to === target) {
        return;
      }
    }
    const fromNode: GraphNode | undefined = this.nodeById(from);
    const toNode: GraphNode | undefined = this.nodeById(target);
    let slotUsed: string = '';
    if (fromNode && toNode && fromNode.handle >= 0 && toNode.handle >= 0) {
      slotUsed = this.connectJobs(fromNode.handle, toNode.handle);
    }
    // 只有内核真的连上了才画线，避免「提示失败但界面显示已连线」的说谎状态
    if (slotUsed.length === 0) {
      if (fromNode && toNode) {
        this.noticeService.warn('连接未生效', `${toNode.title} 没有匹配的输入槽位`);
      }
      this.linkVersion += 1;
      return;
    }
    this.links = this.links.concat([{ id: this.nextId, from: from, to: target } as GraphLink]);
    this.nextId += 1;
    this.linkVersion += 1;
    if (fromNode && toNode) {
      this.noticeService.info('已建立连接', `${fromNode.title} → ${toNode.title}（槽位 ${slotUsed}）`);
    }
  }

  private loadSettings(id: number): void {
    if (this.settingsNode === id) {
      return;
    }
    this.settingsNode = id;
    this.settings = [];
    const node: GraphNode | undefined = this.nodeById(id);
    if (!node || node.handle < 0) {
      return;
    }
    try {
      const raw: string = String(ark.nodeSettings(node.handle));
      hilog.info(0x0000, 'ArkMain', 'settings handle=%{public}d len=%{public}d head=%{public}s',
        node.handle, raw.length, raw.length > 90 ? raw.substring(0, 90) : raw);
      const parsed: SettingCategory[] = JSON.parse(raw) as SettingCategory[];
      hilog.info(0x0000, 'ArkMain', 'settings parsed cats=%{public}d', parsed.length);
      this.settings = parsed;
    } catch (e) {
      const err = e as Error;
      hilog.error(0x0000, 'ArkMain', `settings parse failed: ${err.message ?? String(e)}`);
      this.settings = [];
    }
  }

  private categoryLabel(category: string): string {
    hilog.info(0x0000, 'ArkMain', 'render category %{public}s', category);
    return CATEGORY_LABELS.get(category) ?? CATEGORY_SETTING_LABEL.get(category) ?? category;
  }

  private settingLabel(name: string): string {
    return SETTING_LABELS.get(name) ?? SETTING_LABELS_EXTRA.get(name) ?? SETTING_LABEL.get(name) ?? name;
  }

  private enumOptionLabel(option: SettingOption): string {
    const raw: string = option.label;
    const capitalized: string = raw.length > 0 ? raw.charAt(0).toUpperCase() + raw.slice(1) : raw;
    return ENUM_LABELS.get(raw) ?? ENUM_LABELS.get(capitalized)
      ?? ENUM_LABELS_EXTRA.get(raw) ?? ENUM_LABELS_EXTRA.get(capitalized) ?? raw;
  }

  private applySetting(entry: SettingEntry, rawIn: string): void {
    let raw: string = rawIn;
    if (entry.type === 'int' || entry.type === 'float') {
      raw = this.sanitizeNumeric(entry, rawIn);
      if (raw.length === 0) {
        return;
      }
    }
    const node: GraphNode | undefined = this.nodeById(this.settingsNode);
    if (!node || node.handle < 0) {
      return;
    }
    try {
      ark.setNodeSetting(node.handle, entry.key, raw, entry.type);
      hilog.info(0x0000, 'OpenSPHSet',
        `set key=${entry.key} type=${entry.type} value=${raw} handle=${node.handle}`);
      this.noticeService.success('已更新参数', `${this.settingLabel(entry.name)} = ${raw}`);
    } catch (e) {
      this.noticeService.error('参数写入失败', String(e));
      return;
    }
    this.loadSettingsForce(node.id);
  }

  private loadSettingsForce(id: number): void {
    this.settingsNode = -1;
    this.loadSettings(id);
  }

  // 内核生成的默认实例名（unnamed sphere 等）在界面上翻译成中文。
  // 只做显示层替换；写回内核时仍用原文，避免改动上游语义。
  private displayNameValue(raw: string): string {
    const mapped: string | undefined = SETTING_LABELS.get(raw) ?? SETTING_LABELS_EXTRA.get(raw);
    if (mapped !== undefined) {
      return mapped;
    }
    const prefix: string = 'unnamed ';
    if (raw.startsWith(prefix)) {
      return `未命名${raw.substring(prefix.length)}`;
    }
    return raw;
  }

  private valueText(entry: SettingEntry): string {
    if (typeof entry.value === 'number') {
      const n: number = entry.value as number;
      if (entry.type === 'float') {
        const abs: number = Math.abs(n);
        if (abs !== 0 && (abs >= 1e6 || abs < 1e-3)) {
          return n.toExponential(3);
        }
        return String(Math.round(n * 1000) / 1000);
      }
      return String(n);
    }
    if (entry.key === 'name' && typeof entry.value === 'string') {
      return this.displayNameValue(entry.value as string);
    }
    if (typeof entry.value === 'boolean') {
      return (entry.value as boolean) ? '是' : '否';
    }
    if (entry.value === null) {
      return '—';
    }
    return String(entry.value);
  }

  private enumIndex(entry: SettingEntry): number {
    const v: number = typeof entry.value === 'number' ? entry.value as number : 0;
    for (let i = 0; i < entry.options.length; i++) {
      if (entry.options[i].value === v) {
        return i;
      }
    }
    return 0;
  }

  private enumLabel(entry: SettingEntry): string {
    const v: number = typeof entry.value === 'number' ? entry.value as number : 0;
    for (const o of entry.options) {
      if (o.value === v) {
        return this.enumOptionLabel(o);
      }
    }
    return String(v);
  }

  private connectJobs(fromHandle: number, toHandle: number): string {
    interface SlotInfo {
      name: string;
      used: boolean;
      connected: boolean;
    }
    try {
      const slots: SlotInfo[] = JSON.parse(String(ark.nodeSlots(toHandle))) as SlotInfo[];
      for (const slot of slots) {
        if (!slot.used || slot.connected) {
          continue;
        }
        interface OpResult {
          ok: boolean;
          error?: string;
        }
        const res: OpResult = JSON.parse(String(ark.connectNodes(fromHandle, toHandle, slot.name))) as OpResult;
        if (res.ok) {
          return slot.name;
        }
      }
    } catch (e) {
      return '';
    }
    return '';
  }

  private removeLink(id: number): void {
    this.links = this.links.filter((l: GraphLink) => l.id !== id);
    this.linkVersion += 1;
  }

  private bezier(x1: number, y1: number, x2: number, y2: number): string {
    const dx: number = Math.max(40, Math.abs(x2 - x1) * 0.5);
    return `M ${x1} ${y1} C ${x1 + dx} ${y1} ${x2 - dx} ${y2} ${x2} ${y2}`;
  }

  private linkPath(from: GraphNode, to: GraphNode): string {
    return this.bezier(from.x + CARD_W, from.y + CARD_H / 2, to.x, to.y + CARD_H / 2);
  }

  private clearAll(): void {
    for (const n of this.nodes) {
      if (n.handle >= 0) {
        try {
          ark.releaseNode(n.handle);
        } catch (e) {
          // ignore
        }
      }
    }
    this.nodes = [];
    this.links = [];
    this.selectedNode = -1;
    this.settings = [];
    this.settingsNode = -1;
    this.linkVersion += 1;
  }

  private sessionPath(): string {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return `${ctx.filesDir}/session.sph`;
  }

  private saveSession(): void {
    interface SaveResult {
      ok: boolean;
      nodes: number;
      connections: number;
      error?: string;
    }
    try {
      const res: SaveResult = JSON.parse(String(ark.saveSession(this.sessionPath()))) as SaveResult;
      if (res.ok) {
        this.noticeService.success('会话已保存', `${res.nodes} 个节点 · ${res.connections} 条连接`);
      } else {
        this.noticeService.error('保存失败', res.error ?? '');
      }
    } catch (e) {
      this.noticeService.error('保存失败', String(e));
    }
  }

  private loadSession(): void {
    interface LoadedNode {
      handle: number;
      className: string;
      instanceName: string;
    }
    interface LoadedLink {
      from: number;
      to: number;
    }
    interface LoadResult {
      ok: boolean;
      nodes: number;
      connections: number;
      nodeList: LoadedNode[];
      linkList: LoadedLink[];
      error?: string;
    }
    let res: LoadResult | null = null;
    try {
      res = JSON.parse(String(ark.loadSession(this.sessionPath()))) as LoadResult;
    } catch (e) {
      this.noticeService.error('加载失败', String(e));
      return;
    }
    if (res === null || !res.ok) {
      this.noticeService.warn('加载失败', res === null ? '' : (res.error ?? '文件不存在或格式错误'));
      return;
    }
    // 重建画布
    this.nodes = [];
    this.links = [];
    this.selectedNode = -1;
    const handleToId: Map<number, number> = new Map<number, number>();
    let idCounter: number = 1;
    for (const n of res.nodeList) {
      const node: GraphNode = new GraphNode(idCounter, n.handle, n.className,
        this.nodeTitle(n.className), this.label(this.categoryOf(n.className)),
        (idCounter % 3) * 230 + 40, Math.floor(idCounter / 3) * 100 + 40);
      handleToId.set(n.handle, idCounter);
      this.nodes = this.nodes.concat([node]);
      idCounter += 1;
    }
    let linkId: number = 1;
    for (const l of res.linkList) {
      const fromId: number | undefined = handleToId.get(l.from);
      const toId: number | undefined = handleToId.get(l.to);
      if (fromId !== undefined && toId !== undefined) {
        this.links = this.links.concat([{ id: linkId, from: fromId, to: toId } as GraphLink]);
        linkId += 1;
      }
    }
    this.nextId = idCounter;
    this.linkVersion += 1;
    this.noticeService.success('会话已加载', `${res.nodes} 个节点 · ${res.connections} 条连接`);
  }

  private categoryOf(className: string): string {
    for (const g of this.groups) {
      for (const item of g.items) {
        if (item.className === className) {
          return item.category;
        }
      }
    }
    return 'other';
  }

  private async sessionSelfTest(): Promise<void> {
    hilog.info(0x0000, 'OpenSPHSess', 'session test: create nodes');
    // 1) 建两个节点
    const sphere = Number(ark.createNode('sphere'));
    const cyl = Number(ark.createNode('cylinder'));
    if (sphere < 0 || cyl < 0) {
      this.noticeService.error('会话测试失败', '节点创建失败');
      return;
    }
    this.nodes = this.nodes.concat([
      new GraphNode(this.nextId, sphere, 'sphere', this.nodeTitle('sphere'), this.label('geometry'), 60, 60)
    ]);
    this.nextId += 1;
    this.nodes = this.nodes.concat([
      new GraphNode(this.nextId, cyl, 'cylinder', this.nodeTitle('cylinder'), this.label('geometry'), 300, 60)
    ]);
    this.nextId += 1;
    // 2) 保存
    interface SaveResult {
      ok: boolean;
      nodes: number;
      connections: number;
      error?: string;
    }
    const saved: SaveResult = JSON.parse(String(ark.saveSession(this.sessionPath()))) as SaveResult;
    hilog.info(0x0000, 'OpenSPHSess', `session test: saved ok=${saved.ok} nodes=${saved.nodes} err=${saved.error ?? ''}`);
    if (!saved.ok) {
      this.noticeService.error('保存失败', saved.error ?? '');
      return;
    }
    // 3) 清空后重新加载
    this.clearAll();
    interface LoadedNode {
      handle: number;
      className: string;
      instanceName: string;
    }
    interface LoadedLink {
      from: number;
      to: number;
    }
    interface LoadResult {
      ok: boolean;
      nodes: number;
      connections: number;
      nodeList: LoadedNode[];
      linkList: LoadedLink[];
      error?: string;
    }
    const loaded: LoadResult = JSON.parse(String(ark.loadSession(this.sessionPath()))) as LoadResult;
    hilog.info(0x0000, 'OpenSPHSess', `session test: loaded ok=${loaded.ok} nodes=${loaded.nodes} err=${loaded.error ?? ''}`);
    if (!loaded.ok) {
      this.noticeService.error('加载失败', loaded.error ?? '');
      return;
    }
    hilog.info(0x0000, 'OpenSPHSess', `rebuild: nodeList=${loaded.nodeList ? loaded.nodeList.length : -1} linkList=${loaded.linkList ? loaded.linkList.length : -1}`);
    const idMap: Map<number, number> = new Map<number, number>();
    let idc: number = 1;
    for (const n of loaded.nodeList) {
      this.nodes = this.nodes.concat([
        new GraphNode(idc, n.handle, n.className, this.nodeTitle(n.className),
          this.label(this.categoryOf(n.className)), (idc % 3) * 230 + 40, Math.floor(idc / 3) * 100 + 40)
      ]);
      idMap.set(n.handle, idc);
      idc += 1;
    }
    this.nextId = idc;
    this.linkVersion += 1;
    hilog.info(0x0000, 'OpenSPHSess', `rebuild done: canvas nodes=${this.nodes.length}`);
    this.noticeService.success('会话往返成功', `保存 ${saved.nodes} 节点 → 加载 ${loaded.nodes} 节点`);
  }

  private about(): void {
    this.noticeService.info('关于 OpenSPH', `${this.bridgeVersion} · 归档 ${this.countItems()} 个节点`);
  }

  private menuX(name: string): number {
    if (name === '文件') {
      return 62;
    }
    if (name === '编辑') {
      return 110;
    }
    if (name === '视图') {
      return 158;
    }
    if (name === '模拟') {
      return 202;
    }
    if (name === '渲染') {
      return 245;
    }
    return 292;
  }

  private cancelMenuClose(): void {
    if (this.menuCloseTimer >= 0) {
      clearTimeout(this.menuCloseTimer);
      this.menuCloseTimer = -1;
    }
  }

  private scheduleMenuClose(): void {
    this.cancelMenuClose();
    this.menuCloseTimer = setTimeout(() => {
      this.menuCloseTimer = -1;
      if (!this.menuHoverKeep) {
        this.getUIContext().animateTo({ duration: durMs(DUR_FAST), curve: Curve.EaseOut }, () => {
          this.openMenu = '';
        });
      }
    }, 260);
  }

  private hoverMenu(name: string): void {
    this.cancelMenuClose();
    if (this.openMenu === 'ALL' && this.menuFocus === name) {
      return;
    }
    this.getUIContext().animateTo({ duration: durMs(DUR_FAST), curve: Curve.EaseOut }, () => {
      this.menuFocus = name;
      this.openMenu = 'ALL';
    });
  }

  private toggleMenu(name: string): void {
    hilog.info(0x0000, 'OpenSPHMenu', `menu clicked ${name}`);
    this.getUIContext().animateTo({ duration: durMs(DUR_FAST), curve: Curve.EaseOut }, () => {
      this.openMenu = this.openMenu === name ? '' : name;
    });
  }

  private runMenuAction(name: string, index: number): void {
    this.openMenu = '';
    if (name === '文件') {
      if (index === 0) {
        this.clearAll();
        this.noticeService.info('新建会话', '已清空画布');
      } else if (index === 1) {
        this.loadSession();
      } else if (index === 2) {
        this.saveSession();
      } else {
        const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
        ctx.terminateSelf();
      }
    } else if (name === '编辑') {
      if (index === 0) {
        if (this.selectedNode >= 0) {
          this.removeNode(this.selectedNode);
        } else {
          this.noticeService.warn('删除节点', '先选中一个节点');
        }
      } else if (index === 1) {
        if (this.selectedNode >= 0) {
          this.cloneNodeOnly(this.selectedNode);
        } else {
          this.noticeService.warn('克隆节点', '先选中一个节点');
        }
      } else if (index === 2) {
        if (this.selectedNode >= 0) {
          this.deleteTree(this.selectedNode);
        } else {
          this.noticeService.warn('删除节点及其下游', '先选中一个节点');
        }
      } else {
        this.clearAll();
      }
    } else if (name === '视图') {
      if (index === 0) {
        this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
          this.canvasTab = 0;
        });
      } else if (index === 1) {
        this.getUIContext().animateTo({ duration: durMs(DUR_FAST), curve: Curve.Friction }, () => {
          this.canvasTab = 1;
        });
        this.loadPreview();
      } else if (index === 2) {
        if (this.canvasTab !== 1) {
          this.noticeService.warn('自动旋转', '仅在预览页签可用');
        } else {
          this.toggleAutoRotate();
        }
      } else if (index === 3) {
        this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
          this.panX = 0;
          this.panY = 0;
          this.zoom = 1;
        });
        this.noticeService.info('画布已复位', '平移与缩放回到 100%');
      } else if (index === 4) {
        this.reduceMotion = !this.reduceMotion;
        MOTION_SCALE = this.reduceMotion ? 0 : 1;
        hilog.info(0x0000, 'OpenSPHMotion',
          `reduceMotion=${this.reduceMotion} MOTION_SCALE=${MOTION_SCALE} durBase=${durMs(DUR_BASE)}ms durFast=${durMs(DUR_FAST)}ms`);
        this.saveMotionPref();
      } else if (index === 5) {
        this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
          this.collapsed = false;
          this.leftW = Math.min(420, this.leftW + 40);
        });
        hilog.info(0x0000, 'OpenSPHPane', `menu wide-left -> leftW=${this.leftW} rightW=${this.rightW}`);
        this.savePaneWidths();
      } else if (index === 6) {
        this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
          this.rightCollapsed = false;
          this.rightW = Math.min(460, this.rightW + 40);
        });
        hilog.info(0x0000, 'OpenSPHPane', `menu wide-right -> leftW=${this.leftW} rightW=${this.rightW}`);
        this.savePaneWidths();
      } else {
        this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
          this.leftW = 230;
          this.rightW = 320;
          this.collapsed = false;
          this.rightCollapsed = false;
        });
        hilog.info(0x0000, 'OpenSPHPane', `menu reset -> leftW=${this.leftW} rightW=${this.rightW}`);
        this.savePaneWidths();
        this.noticeService.info('面板已复位', '左 230 · 右 320');
      }
    } else if (name === '模拟') {
      if (index === 0) {
        if (this.simRunning) {
          this.noticeService.warn('模拟已在运行', '请先停止或暂停');
        } else {
          this.startSim();
        }
      } else if (index === 1) {
        if (this.simRunning) {
          this.toggleSimPause();
        } else {
          this.noticeService.warn('没有运行中的模拟', '先开始运行');
        }
      } else if (index === 2) {
        this.stopSim();
      } else if (index === 3) {
        if (this.simRecording) {
          this.stopSimRec();
        } else {
          this.startSimRec();
        }
      } else {
        this.selfTest();
      }
    } else if (name === '渲染') {
      if (index === 1) {
        this.exportMode = 1;
      } else {
        this.exportMode = 0;
        if (index === 2) {
          this.exportResolution = 3;
          this.exportFrames = 3 * this.exportFps;
        }
      }
      this.exportVisible = true;
    } else {
      if (index === 0) {
        this.selfTest();
      } else {
        this.about();
      }
    }
  }

  private menuLabels(name: string): string[] {
    if (name === '文件') {
      return ['新建会话', '打开会话', '保存会话', '退出'];
    }
    if (name === '编辑') {
      return ['删除选中节点', '克隆选中节点', '删除选中节点及其下游', '清空画布'];
    }
    if (name === '视图') {
      return ['节点图', '预览', this.autoRotate ? '停止自动旋转' : '自动旋转',
        '复位画布', this.reduceMotion ? '恢复动效' : '减少动效',
        '加宽左栏', '加宽右栏', '复位面板宽度'];
    }
    if (name === '模拟') {
      return ['开始运行', this.simPaused ? '继续' : '暂停', '停止',
        this.simRecording ? '停止录制' : '录制过程', '自检（IC+模拟）'];
    }
    if (name === '渲染') {
      return ['导出视频…', '录制预览', '以 4K / 3 秒导出'];
    }
    return ['自检', '关于'];
  }

  // ---------- 节点右键菜单（对齐原版 8 项 + 查看属性） ----------
  private upstreamOf(id: number): number[] {
    const out: number[] = [];
    for (const l of this.links) {
      if (l.to === id) {
        out.push(l.from);
      }
    }
    return out;
  }

  private downstreamOf(id: number): number[] {
    const out: number[] = [];
    for (const l of this.links) {
      if (l.from === id) {
        out.push(l.to);
      }
    }
    return out;
  }

  private cloneNodeOnly(id: number): number {
    const src: GraphNode | undefined = this.nodeById(id);
    if (src === undefined) {
      return -1;
    }
    const handle: number = Number(ark.createNode(src.className));
    if (handle < 0) {
      this.noticeService.error('克隆失败', '内核创建节点失败');
      return -1;
    }
    const copy: GraphNode = new GraphNode(this.nextId, handle, src.className, src.title, src.category,
      src.x + 40, src.y + 70);
    this.nextId += 1;
    this.nodes = this.nodes.concat([copy]);
    this.noticeService.info('已克隆节点', `${src.title} → ${copy.title}`);
    return copy.id;
  }

  private addLinkKernel(fromId: number, toId: number): boolean {
    const a: GraphNode | undefined = this.nodeById(fromId);
    const b: GraphNode | undefined = this.nodeById(toId);
    if (a === undefined || b === undefined) {
      return false;
    }
    const slot: string = this.connectJobs(a.handle, b.handle);
    if (slot.length === 0) {
      return false;
    }
    this.links = this.links.concat([{ id: this.nextId, from: fromId, to: toId } as GraphLink]);
    this.nextId += 1;
    this.linkVersion += 1;
    return true;
  }

  private cloneTree(id: number): void {
    const order: number[] = [];
    const seen: Set<number> = new Set<number>();
    const stack: number[] = [id];
    while (stack.length > 0) {
      const cur: number | undefined = stack.pop();
      if (cur === undefined || seen.has(cur)) {
        continue;
      }
      seen.add(cur);
      order.push(cur);
      for (const p of this.upstreamOf(cur)) {
        stack.push(p);
      }
    }
    order.reverse();
    const map: Map<number, number> = new Map<number, number>();
    for (const oldId of order) {
      const nid: number = this.cloneNodeOnly(oldId);
      if (nid >= 0) {
        map.set(oldId, nid);
      }
    }
    let linked: number = 0;
    for (const l of this.links) {
      const f: number | undefined = map.get(l.from);
      const t: number | undefined = map.get(l.to);
      if (f !== undefined && t !== undefined) {
        if (this.addLinkKernel(f, t)) {
          linked += 1;
        }
      }
    }
    this.noticeService.success('已克隆整棵树', `${order.length} 个节点 · ${linked} 条连接`);
  }

  private deleteTree(id: number): void {
    const seen: Set<number> = new Set<number>();
    const stack: number[] = [id];
    while (stack.length > 0) {
      const cur: number | undefined = stack.pop();
      if (cur === undefined || seen.has(cur)) {
        continue;
      }
      seen.add(cur);
      for (const d of this.downstreamOf(cur)) {
        stack.push(d);
      }
    }
    const ids: number[] = Array.from(seen);
    for (const each of ids) {
      this.removeNode(each);
    }
    this.noticeService.info('已删除整棵树', `${ids.length} 个节点`);
  }

  private autoLayoutTree(id: number): void {
    // 按「上游深度」分列，同列按顺序分行
    const depth: Map<number, number> = new Map<number, number>();
    depth.set(id, 0);
    let frontier: number[] = [id];
    let d: number = 0;
    while (frontier.length > 0 && d < 12) {
      const next: number[] = [];
      for (const cur of frontier) {
        for (const p of this.upstreamOf(cur)) {
          if (!depth.has(p)) {
            depth.set(p, d + 1);
            next.push(p);
          }
        }
      }
      frontier = next;
      d += 1;
    }
    const rows: Map<number, number> = new Map<number, number>();
    let maxDepth: number = 0;
    for (const v of depth.values()) {
      maxDepth = Math.max(maxDepth, v);
    }
    for (const n of this.nodes) {
      const dep: number | undefined = depth.get(n.id);
      if (dep === undefined) {
        continue;
      }
      const row: number = rows.get(dep) ?? 0;
      rows.set(dep, row + 1);
      n.x = 40 + (maxDepth - dep) * 250;
      n.y = 40 + row * 110;
    }
    this.linkVersion += 1;
    this.noticeService.info('已自动布局', `${depth.size} 个节点`);
  }

  @Builder
  nodeContextMenu() {
    Column() {
      ForEach(this.nodeCtxItems(), (label: string, index: number) => {
        Text(label)
          .fontSize(13)
          .fontColor(index >= 7 ? '#d93025' : '#1f2328')
          .width('100%')
          .height(34)
          .padding({ left: 12 })
          .borderRadius(6)
          .backgroundColor(this.hoverCtx === index ? (index >= 7 ? '#fdecea' : '#f2f4f7') : Color.Transparent)
          .onHover((isHover: boolean) => {
            this.hoverCtx = isHover ? index : (this.hoverCtx === index ? -1 : this.hoverCtx);
          })
          .onClick(() => {
            this.runNodeCtxAction(index);
          })
      }, (label: string) => label)
    }
    .width(168)
    .padding(6)
    .backgroundColor('#ffffff')
    .borderRadius(10)
    .border({ width: 1, color: '#e4e7eb' })
    .shadow({ radius: 16, color: '#26000000', offsetY: 6 })
    .position({ x: this.ctxWX, y: this.ctxWY })
    .transition(TransitionEffect.OPACITY.animation({ duration: durMs(DUR_FAST), curve: Curve.EaseOut }))
  }

  private nodeCtxItems(): string[] {
    return ['查看属性', '预览此节点', '渲染此节点', '开始运行',
      '克隆', '克隆整棵树', '自动布局', '删除', '删除整棵树'];
  }

  private runNodeCtxAction(index: number): void {
    const id: number = this.ctxNode;
    this.ctxNode = -1;
    if (id < 0) {
      return;
    }
    const node: GraphNode | undefined = this.nodeById(id);
    if (node === undefined) {
      return;
    }
    if (index === 0) {
      this.selectedNode = id;
      this.loadSettingsForce(id);
    } else if (index === 1) {
      this.selectedNode = id;
      this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
        this.canvasTab = 1;
      });
      this.loadPreview();
    } else if (index === 2) {
      this.selectedNode = id;
      this.exportMode = 0;
      this.exportVisible = true;
    } else if (index === 3) {
      this.selectedNode = id;
      this.startSim();
    } else if (index === 4) {
      this.cloneNodeOnly(id);
    } else if (index === 5) {
      this.cloneTree(id);
    } else if (index === 6) {
      this.autoLayoutTree(id);
    } else if (index === 7) {
      this.removeNode(id);
    } else {
      this.deleteTree(id);
    }
  }

  private allMenuGroups(): string[] {
    return ['文件', '编辑', '视图', '模拟', '渲染', '帮助'];
  }

  @Builder
  allMenuPanel() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.allMenuGroups().filter((g: string) => this.menuFocus.length === 0 || g === this.menuFocus), (group: string) => {
            Divider().color('#f0f2f5').margin({ top: 4 });
            Text(group)
              .fontSize(11)
              .fontColor('#8b929b')
              .width('100%')
              .height(26)
              .padding({ left: 14 });
            ForEach(this.menuLabels(group), (label: string, index: number) => {
              Text(label)
                .fontSize(13)
                .fontColor('#1f2328')
                .width('100%')
                .height(40)
                .padding({ left: 22, right: 18 })
                .backgroundColor(this.hoverPanel === group + '/' + label ? '#f2f4f7' : Color.Transparent)
                .onHover((isHover: boolean) => {
                  const key: string = group + '/' + label;
                  this.hoverPanel = isHover ? key : (this.hoverPanel === key ? '' : this.hoverPanel);
                })
                .onClick(() => {
                  this.runMenuAction(group, index);
                })
            }, (label: string) => group + '/' + label)
          }, (group: string) => group)
        }
        .width('100%')
      }
    }
    .width(210)
    .constraintSize({ maxHeight: 640 })
    .padding({ top: 4, bottom: 8 })
    .backgroundColor('#ffffff')
    .borderRadius(10)
    .border({ width: 1, color: '#e4e7eb' })
    .shadow({ radius: 18, color: '#26000000', offsetY: 6 })
    .position({ x: this.menuFocus.length > 0 ? this.menuX(this.menuFocus) : 8, y: 66 })
    .onHover((isHover: boolean) => {
      if (isHover) {
        this.menuHoverKeep = true;
        this.cancelMenuClose();
      } else {
        this.menuHoverKeep = false;
        this.scheduleMenuClose();
      }
    })
    .transition(TransitionEffect.OPACITY
      .animation({ duration: durMs(DUR_FAST), curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ y: -6 })))
  }

  @Builder
  menuDropdown() {
    Column() {
      ForEach(this.menuLabels(this.openMenu), (label: string, index: number) => {
        Text(label)
          .fontSize(13)
          .fontColor('#1f2328')
          .width('100%')
          .padding({ left: 14, right: 18, top: 8, bottom: 8 })
          .stateStyles({
            normal: { .backgroundColor(Color.Transparent) },
            hovered: { .backgroundColor('#f2f4f7') },
            pressed: { .backgroundColor('#e6effd') }
          })
          .onClick(() => {
            this.runMenuAction(this.openMenu, index);
          })
      }, (label: string) => label)
    }
    .width(190)
    .padding({ top: 6, bottom: 6 })
    .backgroundColor('#ffffff')
    .borderRadius(10)
    .border({ width: 1, color: '#e4e7eb' })
    .shadow({ radius: 18, color: '#26000000', offsetY: 6 })
    .position({ x: this.menuX(this.openMenu), y: 66 })
    .transition(TransitionEffect.OPACITY
      .animation({ duration: durMs(DUR_FAST), curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ y: -6 })))
  }

  @Builder
  menuBar() {
    Row({ space: 2 }) {
      Text('OpenSPH')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1f2328')
        .margin({ left: 14, right: 10 });
      ForEach(['文件', '编辑', '视图', '模拟', '渲染', '帮助'], (item: string) => {
        Column() {
          Text(item)
            .fontSize(14)
            .fontWeight(this.openMenu === item ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.openMenu === item || this.hoverTop === item ? '#0b57d0' : '#1f2328')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 });
          Column()
            .width(20)
            .height(2)
            .borderRadius(1)
            .backgroundColor(this.openMenu === item ? '#0b57d0' : Color.Transparent);
        }
        .borderRadius(6)
        .backgroundColor(this.openMenu === item ? '#dbe7fb'
          : (this.hoverTop === item ? '#eef3fd' : Color.Transparent))
        .onHover((isHover: boolean) => {
          this.hoverTop = isHover ? item : (this.hoverTop === item ? '' : this.hoverTop);
          hilog.info(0x0000, 'OpenSPHHover', `${item} hover=${isHover} state=${this.hoverTop}`);
          if (isHover) {
            this.menuHoverKeep = true;
            this.hoverMenu(item);
          } else {
            this.menuHoverKeep = false;
            this.scheduleMenuClose();
          }
        })
        .onClick(() => {
          this.getUIContext().animateTo({ duration: durMs(DUR_FAST), curve: Curve.EaseOut }, () => {
            this.menuFocus = item;
            this.openMenu = this.openMenu === 'ALL' && this.menuFocus === item ? '' : 'ALL';
          });
        })
      }, (item: string) => item);
      Blank();
    }
    .width('100%')
    .height(46)
    .margin({ top: 16 })
    .backgroundColor('#ffffff')
    .border({ width: { bottom: 1 }, color: '#e4e7eb' })
  }

  @Builder
  paletteHeader() {
    Row() {
      if (!this.collapsed) {
        Text('节点库').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#5f6670');
        Blank();
        Text(`${this.groups.length} 类`).fontSize(12).fontColor('#8b929b').margin({ right: 4 });
      }
      Text(this.collapsed ? '›' : '‹')
        .fontSize(16)
        .fontColor('#5f6670')
        .width(24)
        .height(24)
        .textAlign(TextAlign.Center)
        .borderRadius(6)
    }
    .width('100%')
    .padding({ left: this.collapsed ? 10 : 12, right: 8, top: 10, bottom: 6 })
    .onClick(() => {
      this.togglePalette();
    })
  }

  @Builder
  libraryPane() {
    Column() {
      this.paletteHeader();
      if (!this.collapsed) {
        List({ space: 2 }) {
          ForEach(this.groups, (group: CategoryGroup) => {
            ListItemGroup({ header: this.groupHeader(group) }) {
              ForEach(group.items, (item: JobEntry) => {
                ListItem() {
                  Text(this.nodeTitle(item.className))
                    .fontSize(13)
                    .fontColor('#1f2328')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .padding({ left: 26, right: 12, top: 7, bottom: 7 })
                    .borderRadius(6)
                    .stateStyles({
                      normal: { .backgroundColor(Color.Transparent) },
                      hovered: { .backgroundColor('#eceff3') },
                      pressed: { .backgroundColor('#e6effd') }
                    })
                }
                .onClick(() => {
                  this.addNode(item);
                })
              }, (item: JobEntry) => item.className)
            }
          }, (group: CategoryGroup) => group.name)
        }
        .layoutWeight(1)
        .padding({ left: 6, right: 6 })
        .transition(TransitionEffect.OPACITY.animation({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }))
      }
    }
    .width(this.collapsed ? 56 : this.leftW)
    .height('100%')
    .backgroundColor('#fafbfc')
    .border({ width: { right: 1 }, color: '#e4e7eb' })
    .animation({ duration: durMs(DUR_SLOW), curve: Curve.Friction })
  }

  @Builder
  groupHeader(group: CategoryGroup) {
    Row() {
      Text(this.label(group.name)).fontSize(13).fontColor('#5f6670').fontWeight(FontWeight.Medium);
      Blank();
      Text(`${group.items.length}`).fontSize(12).fontColor('#9aa1aa');
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 4 })
  }

  @Builder
  linkLayer() {
    Canvas(this.linkCtx)
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .onReady(() => {
        this.drawLinks();
      })
      .onClick((event: ClickEvent) => {
        const px: number = event.x;
        const py: number = event.y;
        let hit: number = -1;
        let best: number = 16;
        for (const l of this.links) {
          const from: GraphNode | undefined = this.nodeById(l.from);
          const to: GraphNode | undefined = this.nodeById(l.to);
          if (!from || !to) {
            continue;
          }
          const d: number = this.distanceToSegment(px, py,
            from.x + CARD_W, from.y + CARD_H / 2, to.x, to.y + CARD_H / 2);
          if (d < best) {
            best = d;
            hit = l.id;
          }
        }
        if (hit >= 0) {
          this.removeLink(hit);
        }
      })
  }

  @Builder
  canvasTabs() {
    Row({ space: 4 }) {
      if (this.canvasTab === 0) {
        Row({ space: 2 }) {
          Text('＋')
            .zoomBtn()
            .onClick(() => { this.zoom = Math.min(2.5, Math.round((this.zoom + 0.15) * 100) / 100); });
          Text('－')
            .zoomBtn()
            .onClick(() => { this.zoom = Math.max(0.4, Math.round((this.zoom - 0.15) * 100) / 100); });
          Text(`${Math.round(this.zoom * 100)}%`)
            .fontSize(11)
            .fontColor('#5f6670')
            .width(40)
            .textAlign(TextAlign.Center);
          Text('归位')
            .fontSize(11)
            .fontColor('#3c4149')
            .width(38)
            .height(24)
            .textAlign(TextAlign.Center)
            .borderRadius(6)
            .backgroundColor('#f0f2f5')
            .onClick(() => {
              this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
                this.panX = 0;
                this.panY = 0;
                this.zoom = 1;
              });
            });
        }
        .margin({ left: 8 });
      }
      if (this.canvasTab === 1) {
        Text(this.autoRotate ? '停止旋转' : '自动旋转')
          .fontSize(11)
          .fontColor(this.autoRotate ? '#ffffff' : '#3c4149')
          .width(76)
          .height(24)
          .textAlign(TextAlign.Center)
          .margin({ left: 6 })
          .borderRadius(6)
          .backgroundColor(this.autoRotate ? '#0b57d0' : '#f0f2f5')
          .onClick(() => {
            this.toggleAutoRotate();
          });
      }
      ForEach(['节点图', '预览'], (title: string, index: number) => {
        Text(title)
          .fontSize(12)
          .fontColor(this.canvasTab === index ? '#0b57d0' : '#5f6670')
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .borderRadius(6)
          .backgroundColor(this.canvasTab === index ? '#e6effd' : Color.Transparent)
          .stateStyles({
            normal: { .backgroundColor(this.canvasTab === index ? '#e6effd' : Color.Transparent) },
            hovered: { .backgroundColor(this.canvasTab === index ? '#dbe7fb' : '#eceff3') },
            pressed: { .backgroundColor('#dbe7fb') }
          })
          .onClick(() => {
            this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
              this.canvasTab = index;
            });
            if (index === 1) {
              this.loadPreview();
            }
          })
      }, (title: string) => title);
      Blank();
      if (this.simRunning) {
        Row({ space: 6 }) {
          Text(`t=${this.simTime.toFixed(3)} · ${this.simSteps} 步 · ${this.simParticles} 粒子`)
            .fontSize(11)
            .fontColor('#0b57d0')
            .width(200)
            .textAlign(TextAlign.End);
          Text(this.simRecording ? `录制中 ${this.simRecFrames}` : '录制')
            .fontSize(11)
            .fontColor('#ffffff')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.simRecording ? '#d93025' : '#1e8e3e')
            .onClick(() => {
              if (this.simRecording) {
                this.stopSimRec();
              } else {
                this.startSimRec();
              }
            });
          Text(this.simPaused ? '继续' : '暂停')
            .fontSize(11)
            .fontColor('#ffffff')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#0b57d0')
            .onClick(() => {
              this.toggleSimPause();
            });
          Text('停止')
            .fontSize(11)
            .fontColor('#ffffff')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#d93025')
            .onClick(() => {
              this.stopSim();
            })
        }
        .margin({ right: 10 })
      }
      Text('会话')
        .fontSize(12)
        .fontColor('#3c4149')
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor('#f0f2f5')
        .onClick(() => {
          this.sessionSelfTest();
        })
        .margin({ right: 8 });
      Text('自检')
        .fontSize(12)
        .fontColor('#3c4149')
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor('#f0f2f5')
        .onClick(() => {
          this.selfTest();
        })
        .margin({ right: 8 });
      Text('弹窗预览')
        .fontSize(12)
        .fontColor('#3c4149')
        .width(76)
        .height(26)
        .textAlign(TextAlign.Center)
        .margin({ right: 8 })
        .borderRadius(6)
        .backgroundColor('#f0f2f5')
        .onClick(() => {
          this.openPreviewWindow();
        });
      Text('导出视频')
        .fontSize(12)
        .fontColor('#ffffff')
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor('#0b57d0')
        .stateStyles({
          normal: { .backgroundColor('#0b57d0') },
          hovered: { .backgroundColor('#0a4fbb') },
          pressed: { .backgroundColor('#08459f') }
        })
        .onClick(() => {
          this.exportVisible = true;
        })
        .margin({ right: 10 });
      if (this.canvasTab === 1) {
        if (this.previewLoading) {
          Row({ space: 6 }) {
            LoadingProgress().width(14).height(14).color('#0b57d0');
            Text('计算中…').fontSize(11).fontColor('#5f6670');
          }
        } else if (this.previewError.length > 0) {
          Text(this.previewError).fontSize(11).fontColor('#d93025');
        } else {
          Text(`${this.previewKind === 'domain' ? '几何采样' : '粒子'} · ${this.previewCount} 点`)
            .fontSize(11)
            .fontColor('#8b929b');
        }
      }
    }
    .width('100%')
    .height(34)
    .padding({ left: 8, right: 12 })
    .backgroundColor('#ffffff')
    .border({ width: { bottom: 1 }, color: '#e4e7eb' })
  }

  @Builder
  previewPane() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.previewCtx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.drawPreview();
        })
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 0 })
            .onActionStart(() => {
              this.lastPanX = 0;
              this.lastPanY = 0;
              this.previewDragging = true;
              this.dragTick = 0;
            })
            .onActionEnd(() => {
              this.previewDragging = false;
              this.pvTick += 1;
              this.refreshPixel(this.yaw, this.pitch, true);
            })
            .onActionUpdate((event: GestureEvent) => {
              const dx: number = event.offsetX - this.lastPanX;
              const dy: number = event.offsetY - this.lastPanY;
              this.lastPanX = event.offsetX;
              this.lastPanY = event.offsetY;
              this.yaw += dx * 0.01;
              this.pitch = Math.max(-1.5, Math.min(1.5, this.pitch + dy * 0.01));
              this.pvTick += 1;
              this.dragTick = (this.dragTick + 1) % 3;
              if (this.dragTick === 0) {
                this.refreshPixel(this.yaw, this.pitch, false);
              }
            })
        )
      if (this.previewKind === 'particles' && this.previewPts.length > 0
        && Math.floor(this.previewPts.length / 3) < 500) {
        Text(`仅 ${Math.floor(this.previewPts.length / 3)} 个粒子 · 调大「半径系数」或开启「精确距离」可加密`)
          .fontSize(11)
          .fontColor('#a08a5a')
          .margin({ left: 12, top: 8 });
      }
      if (this.previewPts.length === 0 && this.previewError.length === 0 && !this.previewLoading) {
        Text('拖动旋转视角')
          .fontSize(11)
          .fontColor('#6b7280')
          .margin({ left: 12, top: 8 })
          .geometryTransition(MOTION_SCALE > 0 ? 'canvasHint' : '');
      }
    }
    .layoutWeight(1)
    .height('100%')
    .clip(true)
    .transition(TransitionEffect.OPACITY.animation({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }))
  }

  @Builder
  canvasPane() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.canvasTab === 1) {
        this.previewPane()
      } else if (this.nodes.length === 0) {
        Column() {
          Text('节点图')
            .fontSize(13)
            .fontColor('#5f6670')
            .geometryTransition(MOTION_SCALE > 0 ? 'canvasHint' : '');
          Text('点击左侧节点库添加，拖动卡片移动，从右侧圆点拖到另一节点左侧圆点连线')
            .fontSize(12)
            .fontColor('#9aa1aa')
            .margin({ top: 6 })
            .textAlign(TextAlign.Center);
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .transition(TransitionEffect.OPACITY.animation({ duration: durMs(DUR_BASE) }))
      }
      if (this.canvasTab === 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.linkLayer()
          ForEach(this.nodes, (n: GraphNode) => {
        NodeCard({
          node: n,
          selected: this.selectedNode,
          onSelect: (id: number) => {
            this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.Friction }, () => {
              this.selectedNode = id;
            });
            this.loadSettingsForce(id);
          },
          onRemove: (id: number) => {
            this.removeNode(id);
          },
          onMove: () => {
            this.linkVersion += 1;
          },
          onLinkStart: (id: number) => {
            this.startLink(id);
          },
          onLinkMove: (id: number, dx: number, dy: number) => {
            this.moveLink(id, dx, dy);
          },
          onLinkEnd: (id: number) => {
            this.finishLink(id);
          },
          onContextMenu: (id: number, wx: number, wy: number) => {
            const n: GraphNode | undefined = this.nodeById(id);
            if (n === undefined) {
              return;
            }
            if (this.ctxNode === id && wx <= 0 && wy <= 0) {
              // 同一个卡片的 ⋯ 再点一次 → 收起，避免「重新弹出」的突兀感
              this.ctxNode = -1;
              return;
            }
            this.ctxNode = id;
            if (wx > 0 || wy > 0) {
              // 鼠标右键：直接用窗口坐标
              this.ctxWX = wx;
              this.ctxWY = wy;
            } else {
              // ⋯ 按钮：按卡片位置换算到窗口坐标（画布偏移 + 缩放/平移）
              this.ctxWX = 220 + (n.x + CARD_W - 40) * this.zoom + this.panX;
              this.ctxWY = 140 + (n.y + 28) * this.zoom + this.panY;
            }
          }
        })
          }, (n: GraphNode) => String(n.id))
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.panX, y: this.panY })
        .scale({ x: this.zoom, y: this.zoom })
        .animation({ duration: 0 })
        .gesture(
          PanGesture({ fingers: 1, distance: 12 })
            .onActionUpdate((event: GestureEvent) => {
              this.panX += event.offsetX - this.lastPanX;
              this.panY += event.offsetY - this.lastPanY;
              this.lastPanX = event.offsetX;
              this.lastPanY = event.offsetY;
            })
            .onActionEnd(() => {
              this.lastPanX = 0;
              this.lastPanY = 0;
            })
        )
      }
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor('#f5f6f8')
    .clip(true)
    .onClick(() => {
      if (this.ctxNode >= 0) {
        this.ctxNode = -1;
      }
    })
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 8 })
    .animation({ duration: durMs(DUR_SLOW), curve: Curve.EaseOut })
  }

  private numAt(entry: SettingEntry, index: number): string {
    if (entry.value === null || !Array.isArray(entry.value)) {
      return index === 0 ? this.valueText(entry) : '0';
    }
    const arr: number[] = entry.value as number[];
    if (index >= arr.length) {
      return '0';
    }
    const n: number = arr[index];
    if (entry.type === 'float' && Math.abs(n) !== 0 && (Math.abs(n) >= 1e6 || Math.abs(n) < 1e-3)) {
      return n.toExponential(3);
    }
    return String(Math.round(n * 1000) / 1000);
  }

  private applyVectorPart(entry: SettingEntry, index: number, text: string): void {
    const parts: number[] = [0, 0, 0];
    for (let i = 0; i < 3; i++) {
      const raw: string = i === index ? text : this.numAt(entry, i);
      const v: number = Number(raw);
      parts[i] = Number.isFinite(v) ? v : 0;
    }
    this.applySettingRaw(entry, `${parts[0]},${parts[1]},${parts[2]}`);
  }

  private applyIntervalPart(entry: SettingEntry, isLower: boolean, text: string): void {
    const lo: string = isLower ? text : this.numAt(entry, 0);
    const hi: string = isLower ? this.numAt(entry, 1) : text;
    const loV: number = Number(lo);
    const hiV: number = Number(hi);
    this.applySettingRaw(entry, `${Number.isFinite(loV) ? loV : 0},${Number.isFinite(hiV) ? hiV : 0}`);
  }

  // 数值清洗：拦截非法/超范围输入，避免把 1e8 个粒子之类写进内核
  private sanitizeNumeric(entry: SettingEntry, raw: string): string {
    const v: number = Number(raw);
    if (!Number.isFinite(v)) {
      this.noticeService.warn('输入无效', '请输入数字');
      return '';
    }
    if (entry.type === 'int') {
      let iv: number = Math.round(v);
      const k: string = entry.key.toLowerCase();
      if (k.includes('count') || k.includes('particles')) {
        iv = Math.min(2000000, Math.max(1, iv));   // 粒子类：1 ~ 200 万
      } else if (k.includes('step') || k.includes('iteration')) {
        iv = Math.min(1000000, Math.max(0, iv));
      } else {
        iv = Math.min(1000000000, Math.max(-1000000000, iv));
      }
      return String(iv);
    }
    // float：限制到有限且量级合理，保留最多 6 位小数
    const clamped: number = Math.min(1e12, Math.max(-1e12, v));
    return String(Math.round(clamped * 1e6) / 1e6);
  }

  private pendingOf(key: string): string {
    const v: string | undefined = this.pendingByKey.get(key);
    return v === undefined ? '' : v;
  }

  private setPending(key: string, value: string): void {
    this.pendingByKey.set(key, value);
  }

  // 输入防抖提交：上次输入后 700ms 无新输入才写入内核。
  // 之所以不依赖 onEditChange/onSubmit：在触摸输入下这两个回调在多项输入行里不触发，
  // 导致向量/区间改了界面却没写进内核（实测确认）。
  private scheduleCommit(key: string, commit: () => void): void {
    const prev: number | undefined = this.pendingTimers.get(key);
    if (prev !== undefined) {
      clearTimeout(prev);
    }
    const timer: number = setTimeout(() => {
      this.pendingTimers.delete(key);
      commit();
    }, 700);
    this.pendingTimers.set(key, timer);
  }

  private applySettingRaw(entry: SettingEntry, raw: string): void {
    const node: GraphNode | undefined = this.nodeById(this.settingsNode);
    if (!node || node.handle < 0) {
      return;
    }
    try {
      ark.setNodeSetting(node.handle, entry.key, raw, entry.type);
      hilog.info(0x0000, 'OpenSPHSet',
        `set key=${entry.key} type=${entry.type} value=${raw} handle=${node.handle}`);
      this.noticeService.success('已更新参数', `${this.settingLabel(entry.name)} = ${raw}`);
      this.loadSettingsForce(node.id);
    } catch (e) {
      this.noticeService.error('参数写入失败', String(e));
    }
  }

  @Builder
  entryRow(entry: SettingEntry) {
    Column() {
      Row() {
        Text(this.settingLabel(entry.name))
          .fontSize(12)
          .fontColor(entry.enabled ? '#3c4149' : '#a8aeb6')
          .layoutWeight(1)
          .maxLines(2);
        if (entry.type === 'vector') {
          Row({ space: 4 }) {
            ForEach([0, 1, 2], (i: number) => {
              TextInput({ text: this.numAt(entry, i) })
                .type(InputType.NUMBER_DECIMAL)
                .fontSize(11)
                .width(58)
                .height(26)
                .padding({ left: 6, right: 6 })
                .borderRadius(6)
                .backgroundColor('#f5f6f8')
                .border({ width: 1, color: '#e4e7eb' })
                .onEditChange((isEditing: boolean) => {
                  if (!isEditing) {
                    const txt: string = this.pendingOf(entry.key + '#' + i);
                    if (txt.length > 0) {
                      this.applyVectorPart(entry, i, txt);
                      this.setPending(entry.key + '#' + i, '');
                    }
                  }
                })
                .onChange((value: string) => {
                  const k: string = entry.key + '#' + i;
                  this.setPending(k, value);
                  this.scheduleCommit(k, () => {
                    const txt: string = this.pendingOf(k);
                    if (txt.length > 0) {
                      this.applyVectorPart(entry, i, txt);
                    }
                  });
                })
                .onSubmit(() => {
                  const txt: string = this.pendingOf(entry.key + '#' + i);
                  if (txt.length > 0) {
                    this.applyVectorPart(entry, i, txt);
                    this.setPending(entry.key + '#' + i, '');
                  }
                })
            }, (i: number) => entry.key + '#' + i)
          }
        } else if (entry.type === 'interval') {
          Row({ space: 4 }) {
            ForEach([0, 1], (i: number) => {
              TextInput({ text: this.numAt(entry, i) })
                .type(InputType.NUMBER_DECIMAL)
                .fontSize(11)
                .width(64)
                .height(26)
                .padding({ left: 6, right: 6 })
                .borderRadius(6)
                .backgroundColor('#f5f6f8')
                .border({ width: 1, color: '#e4e7eb' })
                .onEditChange((isEditing: boolean) => {
                  if (!isEditing) {
                    const txt: string = this.pendingOf(entry.key + 'i' + i);
                    if (txt.length > 0) {
                      this.applyIntervalPart(entry, i === 0, txt);
                      this.setPending(entry.key + 'i' + i, '');
                    }
                  }
                })
                .onChange((value: string) => {
                  const k: string = entry.key + 'i' + i;
                  this.setPending(k, value);
                  this.scheduleCommit(k, () => {
                    const txt: string = this.pendingOf(k);
                    if (txt.length > 0) {
                      this.applyIntervalPart(entry, i === 0, txt);
                    }
                  });
                })
                .onSubmit(() => {
                  const txt: string = this.pendingOf(entry.key + 'i' + i);
                  if (txt.length > 0) {
                    this.applyIntervalPart(entry, i === 0, txt);
                    this.setPending(entry.key + 'i' + i, '');
                  }
                })
            }, (i: number) => entry.key + 'i' + i)
          }
        } else if (entry.type === 'bool') {
          Toggle({ type: ToggleType.Switch, isOn: entry.value === true })
            .selectedColor('#0b57d0')
            .onChange((isOn: boolean) => {
              this.applySetting(entry, isOn ? 'true' : 'false');
            })
        } else if (entry.type === 'enum') {
          Select(entry.options.map((o: SettingOption): SelectOption => {
            const item: SelectOption = { value: this.enumOptionLabel(o) };
            return item;
          }))
            .selected(this.enumIndex(entry))
            .value(this.enumLabel(entry))
            .font({ size: 12 })
            .onSelect((index: number) => {
              if (index >= 0 && index < entry.options.length) {
                this.applySetting(entry, String(entry.options[index].value));
              }
            })
        } else if (entry.type === 'int' || entry.type === 'float') {
          TextInput({ text: this.valueText(entry) })
            .type(entry.type === 'float' ? InputType.NUMBER_DECIMAL : InputType.Number)
            .fontSize(12)
            .width(96)
            .height(28)
            .padding({ left: 8, right: 8 })
            .borderRadius(6)
            .backgroundColor('#f5f6f8')
            .border({ width: 1, color: '#e4e7eb' })
            .onChange((value: string) => {
              this.pendingValue = value;
            })
            .onSubmit(() => {
              this.applySetting(entry, this.pendingValue);
            })
            .onEditChange((isEditing: boolean) => {
              if (!isEditing) {
                this.applySetting(entry, this.pendingValue);
              }
            })
        } else {
          Text(this.valueText(entry))
            .fontSize(12)
            .fontColor('#5f6670')
            .layoutWeight(1)
            .textAlign(TextAlign.End)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
      Divider().color('#f0f2f5')
    }
    .width('100%')
  }

  @Builder
  @Builder
  paneCollapseBtn(collapsed: boolean, onTap: () => void) {
    Text(collapsed ? '‹' : '›')
      .fontSize(14)
      .fontColor('#5f6670')
      .width(22)
      .height(22)
      .textAlign(TextAlign.Center)
      .borderRadius(4)
      .backgroundColor(this.hoverCollapse ? '#eceff3' : Color.Transparent)
      .onHover((h: boolean) => { this.hoverCollapse = h; })
      .onClick(onTap);
  }

  @Builder
  propertyPane() {
    Column() {
      Row() {
        if (!this.rightCollapsed) {
          Text('属性').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#5f6670');
        }
        Blank();
        if (this.selectedNode >= 0 && !this.rightCollapsed) {
          Text(`${this.countIn(this.selectedNode)} 入 / ${this.countOut(this.selectedNode)} 出`)
            .fontSize(11)
            .fontColor('#9aa1aa')
            .margin({ right: 6 });
        }
        this.paneCollapseBtn(this.rightCollapsed, () => {
          this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
            this.rightCollapsed = !this.rightCollapsed;
          });
        });
      }
      .width('100%')
      .padding({ top: 10, bottom: 6, right: 6 })

      if (!this.rightCollapsed && this.selectedNode >= 0 && this.nodeById(this.selectedNode) !== undefined) {
        Row() {
          Text(this.nodeById(this.selectedNode)!.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1f2328');
          Blank();
          Text(this.nodeById(this.selectedNode)!.category)
            .fontSize(11)
            .fontColor('#8b929b')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('#f0f2f5')
            .borderRadius(4)
        }
        .width('100%')
        .margin({ bottom: 6 })
        .transition(TransitionEffect.OPACITY.animation({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }))

        Column() {
        Scroll() {
          Column() {
            ForEach(this.settings, (cat: SettingCategory) => {
              Text(this.categoryLabel(cat.category))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#5f6670')
                .width('100%')
                .padding({ top: 10, bottom: 4 });
              ForEach(cat.entries, (entry: SettingEntry) => {
                this.entryRow(entry)
              }, (entry: SettingEntry) => cat.category + '/' + entry.key)
            }, (cat: SettingCategory) => cat.category)
          }
          .width('100%')
        }
        .width('100%')
        .height(this.paneListH)
        .scrollBar(BarState.Auto)
        }
        .width('100%')
      } else if (!this.rightCollapsed) {
        Text('未选择节点')
          .fontSize(13)
          .fontColor('#9aa1aa')
          .transition(TransitionEffect.OPACITY.animation({ duration: durMs(DUR_BASE) }));
      }
    }
    .width(this.rightCollapsed ? 44 : this.rightW)
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14 })
    .backgroundColor('#ffffff')
    .border({ width: { left: 1 }, color: '#e4e7eb' })
  }

  private countIn(id: number): number {
    let n: number = 0;
    for (const l of this.links) {
      if (l.to === id) {
        n += 1;
      }
    }
    return n;
  }

  private countOut(id: number): number {
    let n: number = 0;
    for (const l of this.links) {
      if (l.from === id) {
        n += 1;
      }
    }
    return n;
  }

  @Builder
  toastCard(notice: AppNotice) {
    Row() {
      Column()
        .width(3)
        .height(40)
        .borderRadius(2)
        .backgroundColor(notice.level === NoticeLevel.ERROR ? '#d93025'
          : notice.level === NoticeLevel.WARN ? '#e8a33d'
          : notice.level === NoticeLevel.SUCCESS ? '#1e8e3e' : '#0b57d0')
      Column() {
        Row() {
          Text(notice.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#1f2328').layoutWeight(1);
          Text(notice.stamp).fontSize(10).fontColor('#9aa1aa');
        }
        .width('100%')
        if (notice.message.length > 0) {
          Text(notice.message)
            .fontSize(12)
            .fontColor('#5f6670')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width(300)
    .constraintSize({ minHeight: 44, maxHeight: 96 })
    .backgroundColor('#ffffff')
    .borderRadius(10)
    .border({ width: 1, color: '#e4e7eb' })
    .shadow({ radius: 16, color: '#22000000', offsetY: 4 })
    .margin({ top: 8 })
    .transition(TransitionEffect.OPACITY
      .animation({ duration: durMs(DUR_SLOW), curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ y: -10 })))
  }

  @Builder
  toastStack() {
    Column() {
      ForEach(this.toasts, (notice: AppNotice) => {
        this.toastCard(notice)
      }, (notice: AppNotice) => String(notice.id))
    }
    .width(320)
    .margin({ top: 52, right: 16 })
    .alignItems(HorizontalAlign.End)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  historyPanel() {
    Column() {
      Row() {
        Text('通知').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#1f2328');
        Blank();
        Text('清空全部').fontSize(11).fontColor('#0b57d0').onClick(() => {
          this.history = [];
          this.unread = 0;
        })
      }
      .width('100%')
      .padding({ bottom: 6 })
      Divider().color('#f0f2f5')
      Scroll() {
        Column() {
          ForEach(this.history.slice().reverse(), (notice: AppNotice) => {
            Column() {
              Row() {
                Text(notice.title).fontSize(12).fontColor('#1f2328').layoutWeight(1);
                Text(notice.stamp).fontSize(10).fontColor('#9aa1aa');
              }
              .width('100%')
              Text(notice.message).fontSize(11).fontColor('#5f6670').width('100%').margin({ top: 2 })
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
            .alignItems(HorizontalAlign.Start)
          }, (notice: AppNotice) => 'h' + String(notice.id))
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width(320)
    .height(300)
    .position({ x: 1040, y: 640 })
    .padding(12)
    .backgroundColor('#ffffff')
    .borderRadius(12)
    .border({ width: 1, color: '#e4e7eb' })
    .shadow({ radius: 20, color: '#26000000', offsetY: 6 })
    .margin({ top: 52, right: 16 })
    .transition(TransitionEffect.OPACITY
      .animation({ duration: durMs(DUR_BASE), curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ x: 12 })))
  }

  @Builder
  exportDialog() {
    Column() {
      Row() {
        if (this.simRunning) {
        Row({ space: 6 }) {
          Text(`t=${this.simTime.toFixed(3)} · ${this.simSteps} 步 · ${this.simParticles} 粒子`)
            .fontSize(11)
            .fontColor('#0b57d0')
            .width(200)
            .textAlign(TextAlign.End);
          Text(this.simRecording ? `录制中 ${this.simRecFrames}` : '录制')
            .fontSize(11)
            .fontColor('#ffffff')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.simRecording ? '#d93025' : '#1e8e3e')
            .onClick(() => {
              if (this.simRecording) {
                this.stopSimRec();
              } else {
                this.startSimRec();
              }
            });
          Text(this.simPaused ? '继续' : '暂停')
            .fontSize(11)
            .fontColor('#ffffff')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#0b57d0')
            .onClick(() => {
              this.toggleSimPause();
            });
          Text('停止')
            .fontSize(11)
            .fontColor('#ffffff')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#d93025')
            .onClick(() => {
              this.stopSim();
            })
        }
        .margin({ right: 10 })
      }
      Text('会话')
        .fontSize(12)
        .fontColor('#3c4149')
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor('#f0f2f5')
        .onClick(() => {
          this.sessionSelfTest();
        })
        .margin({ right: 8 });
      Text('自检')
        .fontSize(12)
        .fontColor('#3c4149')
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor('#f0f2f5')
        .onClick(() => {
          this.selfTest();
        })
        .margin({ right: 8 });
      Text('导出视频').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1f2328');
        Blank();
        Text('✕')
          .fontSize(14)
          .fontColor('#8b929b')
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(6)
          .onClick(() => {
            if (!this.exportRunning) {
              this.exportVisible = false;
            }
          })
      }
      .width('100%')
      .padding({ bottom: 10 })

      Row() {
        Text('模式').fontSize(12).fontColor('#5f6670').width(70);
        ForEach(['离线渲染', '录制预览'], (label: string, index: number) => {
          Text(label)
            .fontSize(12)
            .fontColor(this.exportMode === index ? '#0b57d0' : '#3c4149')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(6)
            .backgroundColor(this.exportMode === index ? '#e6effd' : '#f5f6f8')
            .onClick(() => {
              if (!this.recording) {
                this.exportMode = index;
              }
            })
        }, (label: string) => label)
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      Row() {
        Text('预设').fontSize(12).fontColor('#5f6670').width(70);
        ForEach([0, 1, 2], (pid: number) => {
          Text(pid === 0 ? '快速预览片' : (pid === 1 ? '标准成片' : '高质量 4K'))
            .fontSize(12)
            .fontColor(this.exportPreset === pid ? '#0b57d0' : '#3c4149')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(6)
            .backgroundColor(this.exportPreset === pid ? '#e8f0fe' : '#f2f4f7')
            .onClick(() => {
              this.applyExportPreset(pid);
            });
        }, (pid: number) => `${pid}`)
      }
      .width('100%')
      .padding({ top: 4, bottom: 6 })

      if (this.exportMode === 0) {
      Row() {
        Text('方向').fontSize(12).fontColor('#5f6670').width(70);
        ForEach(['横屏', '竖屏', '方形'], (label: string, index: number) => {
          Text(label)
            .fontSize(12)
            .fontColor(this.exportOrientation === index ? '#0b57d0' : '#3c4149')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(6)
            .backgroundColor(this.exportOrientation === index ? '#e6effd' : '#f5f6f8')
            .onClick(() => {
              this.exportOrientation = index;
            })
        }, (label: string) => label)
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      Row() {
        Text('分辨率').fontSize(12).fontColor('#5f6670').width(70);
        ForEach(['720p', '1080p', '1440p', '4K'], (label: string, index: number) => {
          Text(label)
            .fontSize(12)
            .fontColor(this.exportResolution === index ? '#0b57d0' : '#3c4149')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(6)
            .backgroundColor(this.exportResolution === index ? '#e6effd' : '#f5f6f8')
            .onClick(() => {
              this.exportResolution = index;
            })
        }, (label: string) => label)
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      Row() {
        Text('帧率').fontSize(12).fontColor('#5f6670').width(70);
        ForEach([24, 30, 60], (value: number) => {
          Text(`${value}`)
            .fontSize(12)
            .fontColor(this.exportFps === value ? '#0b57d0' : '#3c4149')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(6)
            .backgroundColor(this.exportFps === value ? '#e6effd' : '#f5f6f8')
            .onClick(() => {
              this.exportFps = value;
            })
        }, (value: number) => String(value))
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      Row() {
        Text('帧数').fontSize(12).fontColor('#5f6670').width(70);
        TextInput({ text: `${this.exportFrames}` })
          .type(InputType.Number)
          .fontSize(12)
          .width(90)
          .height(28)
          .onChange((value: string) => {
            const v: number = Number(value);
            if (Number.isFinite(v) && v > 0) {
              this.exportFrames = Math.min(3600, Math.floor(v));
            }
          })
        Text('码率 (Mbps)').fontSize(12).fontColor('#5f6670').margin({ left: 12 });
        TextInput({ text: `${this.exportBitrate}` })
          .type(InputType.Number)
          .fontSize(12)
          .width(70)
          .height(28)
          .onChange((value: string) => {
            const v: number = Number(value);
            if (Number.isFinite(v) && v > 0) {
              this.exportBitrate = Math.min(80, Math.floor(v));
            }
          })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      Row() {
        Text('画质').fontSize(12).fontColor('#5f6670').width(70);
        ForEach([1, 2, 3], (q: number) => {
          Text(q === 1 ? '快速' : (q === 2 ? '标准' : '高（2× 采样）'))
            .fontSize(12)
            .fontColor(this.exportQuality === q ? '#0b57d0' : '#3c4149')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(6)
            .backgroundColor(this.exportQuality === q ? '#e8f0fe' : '#f2f4f7')
            .onClick(() => {
              this.exportQuality = q;
            });
        }, (q: number) => `${q}`)
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      Row() {
        Text('时长').fontSize(12).fontColor('#5f6670').width(70);
        ForEach([3, 5, 10], (sec: number) => {
          Text(`${sec}s`)
            .fontSize(12)
            .fontColor('#3c4149')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
            .borderRadius(6)
            .backgroundColor('#f5f6f8')
            .onClick(() => {
              this.exportFrames = sec * this.exportFps;
            })
        }, (sec: number) => String(sec))
        Text(`= ${this.exportFrames} 帧`).fontSize(11).fontColor('#8b929b');
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      Row() {
        Text('文件名').fontSize(12).fontColor('#5f6670').width(70);
        TextInput({ text: this.exportName })
          .fontSize(12)
          .layoutWeight(1)
          .height(28)
          .onChange((value: string) => {
            this.exportName = value;
          })
        Text('.mp4').fontSize(12).fontColor('#8b929b').margin({ left: 4 });
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      Row() {
        Text(`${this.exportSize()[0]} × ${this.exportSize()[1]} · ${this.exportFps} fps · ${this.exportFrames} 帧`
          + (this.exportMode === 0 ? ` · 画质：${this.exportQuality === 1 ? '快速' : (this.exportQuality === 2 ? '标准' : '高（2× 采样）')}` : ' · 录制模式'))
          .fontSize(11)
          .fontColor('#8b929b');
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      if (this.exportRunning || this.exportProgress > 0) {
        Column() {
          Progress({ value: this.exportProgress * 100, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color('#0b57d0')
          Row() {
            Text(this.exportStatusText).fontSize(11).fontColor('#5f6670');
            if (this.exportEtaText.length > 0) {
              Text(this.exportEtaText)
                .fontSize(11)
                .fontColor('#8b929b')
                .margin({ left: 10 });
            }
          }
          .width('100%')
          .margin({ top: 4 })
        }
        .width('100%')
        .padding({ top: 4, bottom: 8 })
      }

      }
      if (this.exportMode === 1) {
        Text(this.recording ? `录制中… 已捕获 ${this.recordedFrames} 帧（切换预览页签并拖动可录制不同视角）`
          : '录制会以预览画布当前尺寸逐帧编码，适合记录交互过程')
          .fontSize(11)
          .fontColor(this.recording ? '#0b57d0' : '#8b929b')
          .width('100%')
          .margin({ top: 4, bottom: 4 })
      }

      Row() {
        Button(this.exportMode === 1 ? (this.recording ? '停止录制' : '开始录制')
          : (this.exportRunning ? '导出中…' : '开始导出'))
          .fontSize(13)
          .height(34)
          .layoutWeight(1)
          .backgroundColor((this.exportRunning) ? '#b9c6da' : '#0b57d0')
          .enabled(!this.exportRunning)
          .onClick(() => {
            if (this.exportMode === 1) {
              if (this.recording) {
                this.stopRecordingPreview();
              } else {
                this.startRecordingPreview();
              }
            } else {
              this.startExport();
            }
          })
        Button('关闭')
          .fontSize(13)
          .height(34)
          .margin({ left: 10 })
          .backgroundColor('#f0f2f5')
          .fontColor('#3c4149')
          .enabled(!this.exportRunning && !this.recording)
          .onClick(() => {
            this.exportVisible = false;
          })
      }
      .width('100%')
    }
    .width(430)
    .padding(16)
    .backgroundColor('#ffffff')
    .borderRadius(14)
    .shadow({ radius: 30, color: '#33000000', offsetY: 8 })
    .transition(TransitionEffect.OPACITY
      .animation({ duration: durMs(DUR_BASE), curve: Curve.EaseOut })
      .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 })))
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
    Column() {
      this.menuBar()
      Row() {
        this.libraryPane()
        if (!this.collapsed) {
          Column()
            .width(8)
            .height('100%')
            .backgroundColor(this.dragSide === 1 ? '#0b57d0'
              : (this.hoverDivider === 1 ? '#c3c8cf' : '#eceff3'))
            .onHover((h: boolean) => { this.hoverDivider = h ? 1 : (this.hoverDivider === 1 ? 0 : this.hoverDivider); })
            .gesture(
              PanGesture({ fingers: 1, distance: 1 })
                .onActionStart(() => { this.dragSide = 1; })
                .onActionUpdate((e: GestureEvent) => {
                  this.leftW = Math.min(420, Math.max(160, this.leftW + e.offsetX - this.lastDragX));
                  this.lastDragX = e.offsetX;
                })
                .onActionEnd(() => { this.dragSide = 0; this.lastDragX = 0; this.savePaneWidths(); })
            )
        }
        Column() {
          this.canvasTabs()
          this.canvasPane()
        }
        .layoutWeight(1)
        .height('100%')
        if (!this.rightCollapsed) {
          Column()
            .width(8)
            .height('100%')
            .backgroundColor(this.dragSide === 2 ? '#0b57d0'
              : (this.hoverDivider === 2 ? '#c3c8cf' : '#eceff3'))
            .onHover((h: boolean) => { this.hoverDivider = h ? 2 : (this.hoverDivider === 2 ? 0 : this.hoverDivider); })
            .gesture(
              PanGesture({ fingers: 1, distance: 1 })
                .onActionStart(() => { this.dragSide = 2; })
                .onActionUpdate((e: GestureEvent) => {
                  this.rightW = Math.min(460, Math.max(220, this.rightW - e.offsetX + this.lastDragX));
                  this.lastDragX = e.offsetX;
                })
                .onActionEnd(() => { this.dragSide = 0; this.lastDragX = 0; this.savePaneWidths(); })
            )
        }
        this.propertyPane()
      }
      .layoutWeight(1)
      .width('100%')
      Row() {
        Text(this.bridgeVersion).fontSize(12).fontColor('#5f6670');
        Blank();
        Row() {
          Text('🔔').fontSize(12).fontColor('#5f6670');
          Text(this.unread > 0 ? String(this.unread) : '').fontSize(11).fontColor('#0b57d0').margin({ left: 2 });
        }
        .padding({ left: 6, right: 8, top: 2, bottom: 2 })
        .borderRadius(6)
        .stateStyles({
          normal: { .backgroundColor(Color.Transparent) },
          hovered: { .backgroundColor('#eceff3') },
          pressed: { .backgroundColor('#e6effd') }
        })
        .onClick(() => {
          this.getUIContext().animateTo({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }, () => {
            this.showHistory = !this.showHistory;
            if (this.showHistory) {
              this.unread = 0;
            }
          });
        })
        .margin({ right: 10 });
        Text('减少动效')
          .fontSize(11)
          .fontColor(this.reduceMotion ? '#0b57d0' : '#8b929b')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(6)
          .stateStyles({
            normal: { .backgroundColor(Color.Transparent) },
            hovered: { .backgroundColor('#eceff3') },
            pressed: { .backgroundColor('#e6effd') }
          })
          .onClick(() => {
            this.reduceMotion = !this.reduceMotion;
            MOTION_SCALE = this.reduceMotion ? 0 : 1;
            this.saveMotionPref();
            this.noticeService.info('动效设置', this.reduceMotion ? '已减少动效' : '已恢复动效');
          })
          .margin({ right: 10 });
        Text(`已注册节点 ${this.countItems()} · 画布节点 ${this.nodes.length} · 连线 ${this.links.length}`)
          .fontSize(12)
          .fontColor('#5f6670');
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor('#fafbfc')
      .border({ width: { top: 1 }, color: '#e4e7eb' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#ffffff')
    .opacity(this.appeared ? 1 : 0)
      if (this.showHistory) {
        this.historyPanel()
      }
      if (this.ctxNode >= 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000000')
          .onClick(() => {
            this.ctxNode = -1;
          })
        this.nodeContextMenu()
      }
      if (this.openMenu === 'ALL') {
        this.allMenuPanel()
      }
      if (this.exportVisible) {
        Column() {
          this.exportDialog()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#40000000')
        .hitTestBehavior(HitTestMode.Transparent)
      }
      this.toastStack()
    }
    .width('100%')
    .height('100%')
  }

  private countItems(): number {
    let n: number = 0;
    for (const g of this.groups) {
      n += g.items.length;
    }
    return n;
  }
}

/// 单个节点卡片：@ObjectLink 让坐标变化驱动重绘；左/右端口负责连线。
@Component
struct NodeCard {
  @ObjectLink node: GraphNode;
  @Prop selected: number;
  onSelect: (id: number) => void = () => {};
  onRemove: (id: number) => void = () => {};
  onMove: () => void = () => {};
  onLinkStart: (id: number) => void = () => {};
  onLinkMove: (id: number, dx: number, dy: number) => void = () => {};
  onLinkEnd: (id: number) => void = () => {};
  onContextMenu: (id: number, x: number, y: number) => void = () => {};
  private dragStartX: number = 0;
  private dragStartY: number = 0;

  private isSelected(): boolean {
    return this.selected === this.node.id;
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Column() {
        Row() {
          Text(this.node.title)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1f2328')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text('⋯')
            .fontSize(14)
            .fontColor('#5f6670')
            .width(20)
            .height(20)
            .textAlign(TextAlign.Center)
            .borderRadius(4)
            .stateStyles({
              normal: { .backgroundColor(Color.Transparent) },
              hovered: { .backgroundColor('#eceff3') },
              pressed: { .backgroundColor('#e6effd') }
            })
            .onClick(() => {
              this.onContextMenu(this.node.id, 0, 0);
            })
            .margin({ right: 2 });
          Text('×')
            .fontSize(14)
            .fontColor('#8b929b')
            .width(20)
            .height(20)
            .textAlign(TextAlign.Center)
            .borderRadius(4)
            .stateStyles({
              normal: { .backgroundColor(Color.Transparent) },
              hovered: { .backgroundColor('#f0d6d6') },
              pressed: { .backgroundColor('#f3c9c9') }
            })
            .onClick(() => {
              this.onRemove(this.node.id);
            })
        }
        .width('100%')
        Text(this.node.category)
          .fontSize(11)
          .fontColor('#8b929b')
          .margin({ top: 2 })
      }
      .width(CARD_W)
      .height(CARD_H)
      .padding({ left: 16, right: 10, top: 8, bottom: 8 })
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#ffffff')
      .borderRadius(10)
      .border({ width: this.isSelected() ? 2 : 1, color: this.isSelected() ? '#0b57d0' : '#dfe3e8' })
      .shadow({ radius: this.isSelected() ? 14 : 6, color: '#1a000000', offsetY: 2 })
      .gesture(
        GestureGroup(
          GestureMode.Parallel,
          TapGesture()
            .onAction(() => {
              this.onSelect(this.node.id);
            }),
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 0 })
            .onActionStart(() => {
              this.onSelect(this.node.id);
              this.dragStartX = this.node.x;
              this.dragStartY = this.node.y;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.node.x = this.dragStartX + event.offsetX;
              this.node.y = this.dragStartY + event.offsetY;
              this.onMove();
            })
        )
      )

      // 输入端口（左）
      Circle({ width: PORT_R * 2, height: PORT_R * 2 })
        .fill('#ffffff')
        .stroke('#8ab4f8')
        .strokeWidth(2)
        .offset({ x: -PORT_R })

      // 输出端口（右）+ 拖拽连线
      Circle({ width: PORT_R * 2, height: PORT_R * 2 })
        .fill('#8ab4f8')
        .offset({ x: CARD_W - PORT_R })
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 0 })
            .onActionStart(() => {
              this.onLinkStart(this.node.id);
            })
            .onActionUpdate((event: GestureEvent) => {
              this.onLinkMove(this.node.id, event.offsetX, event.offsetY);
            })
            .onActionEnd(() => {
              this.onLinkEnd(this.node.id);
            })
        )
    }
    .width(CARD_W + PORT_R * 2)
    .height(CARD_H)
    .margin({ left: -PORT_R })
    .position({ x: this.node.x, y: this.node.y })
    .onMouse((event: MouseEvent) => {
      if (event.action === MouseAction.Press) {
        hilog.info(0x0000, 'OpenSPHMouse', `card mouse button=${event.button} xy=${event.x},${event.y}`);
      }
      if (event.button === MouseButton.Right && event.action === MouseAction.Press) {
        this.onContextMenu(this.node.id, event.windowX, event.windowY);
        event.stopPropagation();
      }
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: durMs(DUR_BASE), curve: Curve.EaseOut }))
  }
}
