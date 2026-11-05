// 作业输入槽位名的中文标签（穷举全部 59 个作业、25 个唯一槽位名）
const SLOT_LABELS: Map<string, string> = new Map<string, string>([
  ['particles', '粒子'],
  ['particles 1', '粒子 1'],
  ['particles 2', '粒子 2'],
  ['particles 3', '粒子 3'],
  ['particles A', '粒子 A'],
  ['particles B', '粒子 B'],
  ['reference particles', '参考粒子'],
  ['test particles', '待测粒子'],
  ['boundary', '边界'],
  ['domain', '域'],
  ['geometry', '几何'],
  ['material', '材质'],
  ['material 1', '材质 1'],
  ['base material', '基础材质'],
  ['base shape', '基础形状'],
  ['shape', '形状'],
  ['shape 1', '形状 1'],
  ['impactor', '撞击体'],
  ['target', '目标'],
  ['original', '原始体'],
  ['fragments', '碎片'],
  ['spheres', '球体组'],
  ['gravity source', '引力源'],
  ['orbiting', '绕行体'],
  ['operand A', '操作数 A'],
  ['operand B', '操作数 B']
]);

export function slotLabel(slot: string): string {
  if (slot.length === 0) {
    return '输入';
  }
  const hit: string | undefined = SLOT_LABELS.get(slot);
  return hit !== undefined ? hit : slot;
}
