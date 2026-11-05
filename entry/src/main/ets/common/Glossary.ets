// 专有名词注释：白名单里的英文术语不强行音译，但在显示时补一句中文解释，
// 让用户知道它是什么（例如 Barnes-Hut（树形引力近似））。
interface GlossEntry {
  term: string;
  gloss: string;
}

const GLOSSARY: GlossEntry[] = [
  { term: 'Barnes-Hut', gloss: '树形引力近似算法' },
  { term: 'Benz-Asphaug', gloss: '撞击强度模型' },
  { term: 'Morris-Monaghan', gloss: '人工传导形式' },
  { term: 'Marching Cubes', gloss: '等值面提取算法' },
  { term: 'Tillotson', gloss: '撞击高温物态方程' },
  { term: 'ANEOS', gloss: '物态方程数据库' },
  { term: 'Balsara', gloss: '抑制激波处黏性过大的开关' },
  { term: 'Courant', gloss: 'CFL 稳定性条件' },
  { term: 'Diehl', gloss: '碎片尺寸分布模型' },
  { term: 'delta-SPH', gloss: '密度扩散修正' },
  { term: 'XSPH', gloss: '速度平滑修正' },
  { term: 'PKDGRAV', gloss: '外部 N 体程序格式' },
  { term: 'MPCORP', gloss: '外部 N 体程序格式' },
  { term: 'HDF5', gloss: '分层数据文件格式' },
  { term: 'VTK', gloss: '可视化工具包格式' },
  { term: 'Toomre', gloss: '盘不稳定性判据' },
  { term: 'Hubbard & MacFarlane', gloss: '木星型行星内部物态模型' },
  { term: 'SPH', gloss: '光滑粒子流体动力学' },
  { term: 'N-body', gloss: 'N 体引力模拟' }
];

// 给含专有名词的文本补中文解释；已带解释则不重复添加
export function annotate(text: string): string {
  if (text.length === 0) {
    return text;
  }
  for (const e of GLOSSARY) {
    if (text.indexOf(e.term) >= 0 && text.indexOf(e.gloss) < 0) {
      return `${text}（${e.gloss}）`;
    }
  }
  return text;
}
