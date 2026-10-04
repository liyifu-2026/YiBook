// 主题模块（纯逻辑，可单测）：夜城 = 暗色（品牌基调），昼港 = 亮色（同族演绎）。
// 两套调色板共享同一份字段契约：换主题 = 换调色板对象，不改任何布局代码。
// 色彩纪律不变：深藏蓝 / 亮橙（唯一暖光=交互与AI）/ 纯黑硬阴影；昼间把藏蓝让给纸白。

export interface Palette {
  bg: string;      // 页面底色
  bgDeep: string;  // 最深处（书脊槽/街面）
  panel: string;   // 面板/卡片
  panelMenu: string; // 弹出菜单底
  hair: string;    // 发丝线
  chip: string;    // 次级 chip 底
  chipActive: string; // chip 激活底（选中笔等）
  text: string;    // 主文字（暖白/藏蓝）
  dim: string;     // 次级文字
  faint: string;   // 三级文字
  accent: string;  // 亮橙（不变）
  onAccent: string; // 橙底文字（两模式同为纯黑，波普纪律）
  shadow: string;  // 硬阴影（两模式同为纯黑）
}

// 夜城（暗）：深夜里亮着暖光的窗
export const NIGHT: Palette = {
  bg: '#101E33',
  bgDeep: '#0A1220',
  panel: '#182A47',
  panelMenu: '#13233C',
  hair: '#23395C',
  chip: '#22395F',
  chipActive: '#34527D',
  text: '#F7F0E4',
  dim: '#8CA2C0',
  faint: '#5C7396',
  accent: '#FF8A2A',
  onAccent: '#060B12',
  shadow: '#060B12'
};

// 昼港（亮）：同一座城市的清晨——纸白底、藏蓝字、橙灯不灭
export const DAY: Palette = {
  bg: '#F3EEE2',
  bgDeep: '#E7E0CE',
  panel: '#FFFFFF',
  panelMenu: '#FFFFFF',
  hair: '#D9D1BD',
  chip: '#FFFFFF',
  chipActive: '#FFDDB8',
  text: '#101E33',
  dim: '#5A6B85',
  faint: '#93A0B4',
  accent: '#FF8A2A',
  onAccent: '#060B12',
  shadow: '#060B12'
};

export function paletteOf(night: boolean): Palette {
  return night ? NIGHT : DAY;
}

const THEME_KEY = 'nightMode';

export function themeKey(): string {
  return THEME_KEY;
}
