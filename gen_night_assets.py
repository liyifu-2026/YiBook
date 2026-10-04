# -*- coding: utf-8 -*-
# 亦书 · 夜城素材生成器（扁平矢量 + 波普 + Lo-fi 嘻哈专辑封面风）
# 三色纪律：深藏蓝（夜）、亮橙（暖光/AI）、纯黑（剪影/描边/硬阴影）；暖白只给月光与文字级高光。
# 全部手绘形状，无渐变、无滤镜；SVG 只用 rect/circle/ellipse/polygon/path，兼容 ArkUI Image。
import os
from PIL import Image, ImageDraw

MEDIA = 'entry/src/main/resources/base/media'
PREV = 'assets'
os.makedirs(PREV, exist_ok=True)

# ---------- 调色 ----------
N0 = '#0A1220'   # 夜最深（街面/剪影备用）
N1 = '#101E33'   # 深藏蓝 · 主底
N2 = '#182A47'   # 藏蓝 · 面板
N3 = '#23395C'   # 藏蓝 · 中景
N4 = '#34527D'   # 藏蓝 · 远景
OR = '#FF8A2A'   # 亮橙 · 暖光
OD = '#E0621A'   # 橙 · 硬阴影色
OP = '#FFC58F'   # 橙 · 高光
WH = '#F7F0E4'   # 暖白 · 月光/文字高光
BK = '#060B12'   # 纯黑 · 剪影/描边/硬阴影

W, H = 600, 900  # 封面画布 2:3


def svg(name, body, w=W, h=H):
    doc = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}">'
           f'{body}</svg>')
    for d in (MEDIA, PREV):
        with open(os.path.join(d, name), 'w', encoding='utf-8') as f:
            f.write(doc)
    print('svg', name, len(doc), 'bytes')


def stars(seed_w, y_max, n=16, r=2.2):
    # 固定伪随机星点（白/橙交错，克制密度）
    s, out = 7, ''
    for i in range(n):
        s = (s * 73 + 41) % 997
        x = 20 + (s % (seed_w - 40))
        s = (s * 73 + 41) % 997
        y = 24 + (s % y_max)
        c, rr = (WH, r) if i % 3 else (OR, r - 0.6)
        out += f'<circle cx="{x}" cy="{y}" r="{rr}" fill="{c}" fill-opacity="{0.9 if c==WH else 0.8}"/>'
    return out


def dots(x0, y0, x1, y1, step, r, color, op):
    # 波普 Ben-Day 圆点阵
    out, j = '', 0
    y = y0
    while y <= y1:
        x = x0 + (step // 2 if j % 2 else 0)
        while x <= x1:
            out += f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}" fill-opacity="{op}"/>'
            x += step
        y += step
        j += 1
    return out


def frame():
    # 复古漫画框：内缩纯黑描边
    return f'<rect x="5" y="5" width="{W-10}" height="{H-10}" fill="none" stroke="{BK}" stroke-width="10"/>'


def moon_crescent(cx, cy, r, cut=0.82):
    # 弦月：暖白圆叠底色圆（硬边，无渐变）
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{WH}"/>'
            f'<circle cx="{cx + r * cut * 0.55:.0f}" cy="{cy - r * cut * 0.42:.0f}" r="{r * cut:.0f}" fill="{N1}"/>')


# ---------- 封面 A · 夜游者餐吧 ----------
def cover_diner():
    b = f'<rect width="{W}" height="{H}" fill="{N1}"/>'
    b += stars(W, 300, 14)
    b += moon_crescent(480, 130, 40)
    # 远景楼群
    for x, w_, h_ in [(0, 90, 190), (70, 70, 150), (420, 80, 210), (500, 100, 160)]:
        b += f'<rect x="{x}" y="{470 - h_}" width="{w_}" height="{h_}" fill="{N4}"/>'
    for x, w_, h_ in [(130, 80, 120), (330, 90, 150)]:
        b += f'<rect x="{x}" y="{470 - h_}" width="{w_}" height="{h_}" fill="{N3}"/>'
    # 餐吧主体（纯黑体量 + 暖橙橱窗）
    b += f'<rect x="40" y="470" width="520" height="210" fill="{BK}"/>'
    b += f'<rect x="40" y="470" width="520" height="14" fill="{OD}"/>'          # 檐口橙线
    b += f'<rect x="368" y="414" width="130" height="56" fill="{BK}"/>'          # 招牌底板
    b += f'<rect x="380" y="426" width="106" height="32" fill="{OR}"/>'          # 招牌亮面
    # 三扇橱窗 + 吧台后的客人剪影（头肩越过台面）
    for i, wx in enumerate([64, 232, 400]):
        b += f'<rect x="{wx}" y="508" width="136" height="128" fill="{OR}"/>'
        b += f'<rect x="{wx}" y="574" width="136" height="62" fill="{OD}"/>'        # 台面下暖橙暗部
        b += f'<rect x="{wx}" y="568" width="136" height="8" fill="{BK}"/>'         # 吧台沿
        # 客人：圆头 + 溜肩半身，从台面后探出
        b += f'<circle cx="{wx + 48}" cy="552" r="14" fill="{BK}"/>'
        b += f'<path d="M{wx + 26} 576 q6 -18 22 -18 q16 0 22 18 Z" fill="{BK}"/>'
        if i == 1:
            b += f'<circle cx="{wx + 98}" cy="548" r="12" fill="{BK}"/>'
            b += f'<path d="M{wx + 80} 568 q5 -15 18 -15 q13 0 18 15 Z" fill="{BK}"/>'
    b += f'<rect x="196" y="508" width="10" height="128" fill="{BK}"/>'          # 窗棂
    b += f'<rect x="364" y="508" width="10" height="128" fill="{BK}"/>'
    # 街面 + 硬投影 + 橙色倒影
    b += f'<rect x="0" y="680" width="{W}" height="220" fill="{N0}"/>'
    b += f'<polygon points="64,680 560,680 600,716 24,716" fill="{BK}"/>'        # 建筑投在街面的硬影
    for wx in [64, 232, 400]:
        b += (f'<rect x="{wx + 18}" y="740" width="100" height="8" fill="{OR}" fill-opacity="0.4"/>'
              f'<rect x="{wx + 34}" y="764" width="68" height="6" fill="{OR}" fill-opacity="0.22"/>')
    b += f'<rect x="40" y="850" width="520" height="6" fill="{WH}" fill-opacity="0.10"/>'
    b += frame()
    svg('cover_diner.svg', b)


# ---------- 封面 B · 天台与错版月亮 ----------
def cover_rooftop():
    b = f'<rect width="{W}" height="{H}" fill="{N1}"/>'
    b += stars(W, 220, 12)
    # 波普错版月：橙圆在下面偏右下，暖白圆盖住左上
    b += f'<circle cx="322" cy="268" r="112" fill="{OR}" fill-opacity="0.85"/>'
    b += f'<circle cx="298" cy="246" r="112" fill="{WH}"/>'
    b += dots(60, 400, 540, 452, 34, 3, WH, 0.22)      # 月下点阵带
    # 远中景
    for x, w_, h_ in [(0, 110, 120), (90, 90, 90), (360, 100, 130), (470, 130, 100)]:
        b += f'<rect x="{x}" y="{600 - h_}" width="{w_}" height="{h_}" fill="{N4}"/>'
    for x, w_, h_ in [(170, 110, 70), (280, 90, 110)]:
        b += f'<rect x="{x}" y="{600 - h_}" width="{w_}" height="{h_}" fill="{N3}"/>'
    # 前景天台（纯黑）
    b += f'<rect x="0" y="600" width="{W}" height="300" fill="{BK}"/>'
    b += f'<rect x="0" y="600" width="{W}" height="10" fill="{N3}"/>'            # 檐口高光
    # 水塔（宽罐 + 覆檐 + 四腿）
    b += (f'<rect x="128" y="470" width="64" height="66" fill="{BK}"/>'
          f'<rect x="124" y="458" width="72" height="16" fill="{BK}"/>'
          f'<polygon points="116,460 204,460 160,428" fill="{BK}"/>'
          f'<rect x="132" y="536" width="10" height="64" fill="{BK}"/>'
          f'<rect x="178" y="536" width="10" height="64" fill="{BK}"/>'
          f'<rect x="146" y="486" width="28" height="18" fill="{N3}"/>')            # 罐身检修口
    # 天线 + 橙色航空灯
    b += (f'<rect x="432" y="520" width="6" height="80" fill="{BK}"/>'
          f'<rect x="452" y="536" width="5" height="64" fill="{BK}"/>'
          f'<rect x="420" y="548" width="5" height="52" fill="{BK}"/>'
          f'<circle cx="435" cy="512" r="7" fill="{OR}"/>')
    # 亮着一扇窗 + 窗内猫剪影
    b += (f'<rect x="252" y="640" width="96" height="76" fill="{OR}"/>'
          f'<polygon points="266,716 278,694 290,716" fill="{BK}"/>'
          f'<polygon points="306,716 318,694 330,716" fill="{BK}"/>'
          f'<ellipse cx="298" cy="716" rx="26" ry="12" fill="{BK}"/>'
          f'<rect x="252" y="716" width="96" height="6" fill="{N3}"/>')
    b += frame()
    svg('cover_rooftop.svg', b)


# ---------- 封面 C · 路灯与黑猫 ----------
def cover_lamp():
    b = f'<rect width="{W}" height="{H}" fill="{N1}"/>'
    b += stars(W, 240, 10)
    b += moon_crescent(120, 140, 34)
    for x, w_, h_ in [(0, 100, 90), (420, 90, 120), (510, 90, 80)]:
        b += f'<rect x="{x}" y="{640 - h_}" width="{w_}" height="{h_}" fill="{N3}"/>'
    # 光锥（单色平涂透明）+ 地面光池
    b += f'<polygon points="330,318 210,780 470,780" fill="{OR}" fill-opacity="0.16"/>'
    # 街道
    b += f'<rect x="0" y="700" width="{W}" height="200" fill="{N0}"/>'
    b += f'<ellipse cx="336" cy="762" rx="168" ry="34" fill="{OR}" fill-opacity="0.25"/>'
    # 路灯（纯黑杆 + 橙灯头）
    b += f'<rect x="322" y="318" width="14" height="470" fill="{BK}"/>'
    b += f'<rect x="322" y="318" width="90" height="12" fill="{BK}"/>'
    b += f'<polygon points="392,330 448,330 436,296 404,296" fill="{BK}"/>'
    b += f'<rect x="408" y="330" width="24" height="10" fill="{OR}"/>'
    b += f'<rect x="296" y="786" width="66" height="10" fill="{BK}"/>'           # 灯杆底座
    # 猫（坐在光池中央）
    b += (f'<path d="M300 762 Q298 706 336 702 Q376 700 376 756 L376 762 Z" fill="{BK}"/>'
          f'<polygon points="310,708 318,682 330,704" fill="{BK}"/>'
          f'<polygon points="338,702 350,680 360,704" fill="{BK}"/>'
          f'<circle cx="322" cy="722" r="4.5" fill="{OR}"/>'
          f'<circle cx="346" cy="722" r="4.5" fill="{OR}"/>'
          f'<path d="M282 760 q-20 4 -34 -6" stroke="{BK}" stroke-width="10" fill="none" stroke-linecap="round"/>')
    # 道路中线
    for y in (810, 846, 878):
        b += f'<rect x="{296 if y==810 else 288}" y="{y}" width="26" height="8" fill="{WH}" fill-opacity="0.4"/>'
    b += frame()
    svg('cover_lamp.svg', b)


# ---------- 封面 D · 窗台猫与热汽 ----------
def cover_window():
    b = f'<rect width="{W}" height="{H}" fill="{N2}"/>'
    b += f'<rect x="0" y="740" width="{W}" height="160" fill="{N1}"/>'           # 室内地面
    # 窗外夜景（先画，再压窗框）
    b += f'<rect x="110" y="140" width="380" height="400" fill="{N1}"/>'
    b += stars(490, 110, 8, 1.8)
    b += f'<circle cx="200" cy="230" r="42" fill="{WH}"/>'
    b += f'<circle cx="200" cy="230" r="58" fill="{WH}" fill-opacity="0.10"/>'
    for x, w_, h_ in [(110, 70, 90), (180, 60, 60), (250, 80, 110), (330, 60, 80), (400, 90, 70)]:
        b += f'<rect x="{x}" y="{540 - h_}" width="{w_}" height="{h_}" fill="{N4}"/>'
    b += f'<rect x="290" y="470" width="18" height="14" fill="{OR}"/>'           # 远处一扇亮窗
    # 窗框（纯黑描边 + 十字棂，不遮窗内夜景）
    b += f'<rect x="104" y="134" width="392" height="412" fill="none" stroke="{BK}" stroke-width="20"/>'
    b += f'<rect x="294" y="134" width="12" height="412" fill="{BK}"/>'
    b += f'<rect x="104" y="330" width="392" height="12" fill="{BK}"/>'
    # 窗台板
    b += f'<rect x="70" y="546" width="460" height="34" fill="{BK}"/>'
    b += f'<rect x="70" y="546" width="460" height="8" fill="{N3}"/>'
    # 马克杯 + 热汽
    b += (f'<rect x="180" y="486" width="64" height="62" fill="{OR}"/>'
          f'<rect x="180" y="486" width="64" height="10" fill="{OD}"/>'
          f'<path d="M244 500 q26 4 0 34" stroke="{OR}" stroke-width="10" fill="none"/>'
          f'<path d="M204 462 q10 -14 0 -26 q-10 -12 2 -24" stroke="{WH}" stroke-width="5" fill="none" stroke-linecap="round" fill-opacity="0.9"/>'
          f'<path d="M228 466 q10 -14 0 -26" stroke="{WH}" stroke-width="4" fill="none" stroke-linecap="round" fill-opacity="0.7"/>')
    # 蜷坐的猫（背对，望向窗外月亮）
    b += (f'<path d="M330 546 Q328 468 392 462 Q458 460 458 546 Z" fill="{BK}"/>'
          f'<polygon points="352,478 362,446 380,472" fill="{BK}"/>'
          f'<polygon points="398,468 410,440 424,470" fill="{BK}"/>'
          f'<path d="M458 540 q26 -2 34 -22" stroke="{BK}" stroke-width="12" fill="none" stroke-linecap="round"/>')
    # 地面月光斑（平涂）
    b += f'<polygon points="120,742 300,742 340,812 80,812" fill="{WH}" fill-opacity="0.07"/>'
    b += frame()
    svg('cover_window.svg', b)


# ---------- 封面 E · 波普落日环城 ----------
def cover_pop():
    b = f'<rect width="{W}" height="{H}" fill="{N1}"/>'
    b += f'<rect x="0" y="0" width="{W}" height="150" fill="{N2}"/>'
    b += f'<rect x="0" y="150" width="{W}" height="150" fill="{N1}"/>'
    b += f'<rect x="0" y="300" width="{W}" height="120" fill="{N2}"/>'
    b += dots(30, 30, 570, 132, 36, 3.2, WH, 0.18)     # 天空点阵
    # 落日（错版双圆）
    b += f'<circle cx="318" cy="452" r="152" fill="{OD}"/>'
    b += f'<circle cx="298" cy="436" r="152" fill="{OR}"/>'
    b += f'<circle cx="298" cy="436" r="96" fill="{OP}" fill-opacity="0.35"/>'  # 内环平涂高光
    # 远景
    b += f'<rect x="0" y="560" width="{W}" height="60" fill="{N4}"/>'
    # 剪影楼群
    for x, w_, h_ in [(0, 90, 240), (86, 70, 170), (156, 110, 280), (266, 80, 200),
                      (346, 120, 300), (466, 70, 190), (536, 64, 250)]:
        b += f'<rect x="{x}" y="{820 - h_}" width="{w_}" height="{h_}" fill="{BK}"/>'
    # 亮窗（橙为主、白点缀，克制散布）
    wins = [(30, 620), (60, 660), (110, 700), (180, 590), (210, 640), (240, 700),
            (292, 660), (376, 580), (410, 640), (438, 700), (486, 680), (556, 620)]
    for i, (x, y) in enumerate(wins):
        b += f'<rect x="{x}" y="{y}" width="16" height="22" fill="{OR if i % 4 else WH}"/>'
    b += f'<rect x="0" y="820" width="{W}" height="80" fill="{N0}"/>'
    for x in (120, 300, 480):
        b += f'<rect x="{x}" y="850" width="60" height="6" fill="{OR}" fill-opacity="0.35"/>'
    b += frame()
    svg('cover_pop.svg', b)


# ---------- 管家 · 黑猫（描边剪影，透明底） ----------
def cat():
    # 512 画布，坐姿黑猫 + 暖白描边（漫画风）+ 橙眼
    b = ('<path d="M150 400 Q142 250 256 242 Q372 250 366 400 Z" fill="#0A1220" stroke="#F7F0E4" stroke-width="10"/>'
         '<polygon points="176,262 196,186 232,248" fill="#0A1220" stroke="#F7F0E4" stroke-width="10" stroke-linejoin="round"/>'
         '<polygon points="286,246 318,184 340,260" fill="#0A1220" stroke="#F7F0E4" stroke-width="10" stroke-linejoin="round"/>'
         '<circle cx="216" cy="308" r="13" fill="#FF8A2A"/>'
         '<circle cx="300" cy="308" r="13" fill="#FF8A2A"/>'
         '<path d="M176 352 q-16 8 -30 2 M340 352 q16 8 30 2" stroke="#F7F0E4" stroke-width="6" fill="none" stroke-linecap="round"/>'
         '<path d="M366 384 q40 -4 52 -34" stroke="#0A1220" stroke-width="22" fill="none" stroke-linecap="round"/>'
         '<path d="M366 384 q40 -4 52 -34" stroke="#F7F0E4" stroke-width="8" fill="none" stroke-linecap="round"/>')
    svg('cat.svg', b, 512, 512)


# ---------- 空书房场景（透明底不适合，用夜色底） ----------
def empty_shelf():
    w, h = 1024, 720
    b = f'<rect width="{w}" height="{h}" fill="{N1}"/>'
    b += f'<rect x="0" y="560" width="{w}" height="160" fill="{N0}"/>'
    # 右侧大窗
    b += f'<rect x="620" y="90" width="330" height="420" fill="{N1}"/>'
    b += stars(950, 140, 10, 2)
    b += f'<circle cx="800" cy="220" r="52" fill="{WH}"/>'
    b += f'<circle cx="800" cy="220" r="72" fill="{WH}" fill-opacity="0.10"/>'
    for x, w_, h_ in [(620, 70, 110), (700, 60, 80), (770, 80, 130), (860, 90, 100)]:
        b += f'<rect x="{x}" y="{510 - h_}" width="{w_}" height="{h_}" fill="{N4}"/>'
    b += f'<rect x="604" y="74" width="362" height="452" fill="none" stroke="{BK}" stroke-width="26"/>'
    b += f'<rect x="775" y="74" width="16" height="452" fill="{BK}"/>'
    b += f'<rect x="604" y="286" width="362" height="16" fill="{BK}"/>'
    # 地面月光
    b += f'<polygon points="640,560 940,560 1000,680 560,680" fill="{WH}" fill-opacity="0.08"/>'
    # 窗下望月的猫（暖白描边在夜色里可读）
    b += (f'<path d="M740 560 Q738 486 800 480 Q864 486 862 560 Z" fill="{BK}" stroke="{N3}" stroke-width="6"/>'
          f'<polygon points="762,494 774,458 792,490" fill="{BK}" stroke="{N3}" stroke-width="6" stroke-linejoin="round"/>'
          f'<polygon points="812,488 826,456 842,492" fill="{BK}" stroke="{N3}" stroke-width="6" stroke-linejoin="round"/>'
          f'<circle cx="784" cy="512" r="5" fill="{OR}"/>'
          f'<circle cx="822" cy="512" r="5" fill="{OR}"/>'
          f'<path d="M862 552 q26 -2 34 -22" stroke="{BK}" stroke-width="14" fill="none" stroke-linecap="round"/>')
    # 左侧一摞书（黑/藏蓝 + 一本橙），加大存在感
    for i, (x, y, w_, h_, c) in enumerate([(120, 600, 260, 52, BK), (140, 548, 230, 52, N3),
                                           (108, 496, 268, 52, OR), (150, 444, 210, 52, N4)]):
        b += f'<rect x="{x}" y="{y}" width="{w_}" height="{h_}" fill="{c}"/>'
        b += f'<rect x="{x}" y="{y}" width="16" height="{h_}" fill="{WH}" fill-opacity="0.22"/>'
        b += f'<rect x="{x + w_ - 26}" y="{y + 10}" width="10" height="{h_ - 20}" fill="{WH}" fill-opacity="0.10"/>'
    b += f'<rect x="392" y="600" width="12" height="70" fill="{OD}"/>'   # 书立
    b += f'<rect x="96" y="652" width="330" height="10" fill="{N2}"/>'   # 搁板
    svg('empty_shelf.svg', b, w, h)


# ---------- App 图标（PIL 画扁平形状） ----------
def hex2rgb(hx):
    hx = hx.lstrip('#')
    return tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))


def icon():
    S = 1024
    navy = hex2rgb(N1)
    orange = hex2rgb(OR)
    black = hex2rgb(BK)
    white = hex2rgb(WH)
    # 背景层：藏蓝 + 角落点阵
    bg = Image.new('RGB', (S, S), navy)
    d = ImageDraw.Draw(bg)
    for j in range(6):
        for i in range(6):
            x, y = 760 + i * 42, 90 + j * 42
            d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=hex2rgb(N3))
    bg.save('AppScope/resources/base/media/background.png', optimize=True)
    bg.save('entry/src/main/resources/base/media/background.png', optimize=True)
    # 前景层：黑影 + 橙色打开的书 + 白月点（透明底）
    fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    cx, cy = S // 2, S // 2 + 40
    wpage, hpage = 300, 210
    # 书本硬阴影（右下偏移纯黑）
    d.polygon([(cx - wpage, cy - hpage // 2 + 36), (cx, cy - hpage // 6 + 36), (cx + wpage, cy - hpage // 2 + 36),
               (cx + wpage, cy + hpage // 2 + 36), (cx, cy + hpage + 36), (cx - wpage, cy + hpage // 2 + 36)],
              fill=black + (255,))
    # 书页两片（橙）
    d.polygon([(cx - wpage, cy - hpage // 2), (cx, cy - hpage // 6), (cx, cy + hpage), (cx - wpage, cy + hpage // 2)],
              fill=orange + (255,))
    d.polygon([(cx + wpage, cy - hpage // 2), (cx, cy - hpage // 6), (cx, cy + hpage), (cx + wpage, cy + hpage // 2)],
              fill=orange + (255,))
    # 中缝（藏蓝细缝制造体积，平涂）
    d.polygon([(cx - 14, cy - hpage // 6 + 12), (cx + 14, cy - hpage // 6 + 12),
               (cx + 14, cy + hpage - 8), (cx - 14, cy + hpage - 8)], fill=navy + (255,))
    # 月亮点
    d.ellipse([cx + 150, cy - 300, cx + 214, cy - 236], fill=white + (255,))
    fg.save('AppScope/resources/base/media/foreground.png', optimize=True)
    fg.save('entry/src/main/resources/base/media/foreground.png', optimize=True)
    # startIcon：背景 + 前景合成
    ic = bg.convert('RGBA')
    ic.alpha_composite(fg)
    ic.save('entry/src/main/resources/base/media/startIcon.png', optimize=True)
    ic.convert('RGB').save('assets/app_icon.png', optimize=True)
    print('icon done')


if __name__ == '__main__':
    cover_diner()
    cover_rooftop()
    cover_lamp()
    cover_window()
    cover_pop()
    cat()
    empty_shelf()
    icon()
    print('media:', sorted(os.listdir(MEDIA)))
