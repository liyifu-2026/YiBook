import io, os
from PIL import Image, ImageDraw

OUT = 'entry/src/main/resources/base/media'
PREV = 'assets'
INK = (22, 22, 22, 255)        # 墨黑
VIOLET = (10, 132, 255, 255)   # 液态彩
WHITE = (255, 255, 255, 255)

def new_layer(size):
    return Image.new('RGBA', size, (0, 0, 0, 0))

# ---------- 管家吉祥物（扁平墨滴小机器人） ----------
def draw_mascot(wave: bool):
    im = new_layer((512, 512))
    d = ImageDraw.Draw(im)
    # 身体：圆角墨滴方块
    d.rounded_rectangle((126, 150, 386, 452), radius=80, fill=INK)
    # 天线 + 液态彩端点
    d.line((256, 150, 256, 96), fill=INK, width=10)
    d.ellipse((240, 70, 272, 102), fill=VIOLET)
    # 独眼（白底 + 液态彩瞳）
    d.ellipse((212, 236, 300, 324), fill=WHITE)
    d.ellipse((238, 262, 282, 306), fill=VIOLET)
    # 脚
    d.rounded_rectangle((170, 448, 240, 480), radius=14, fill=INK)
    d.rounded_rectangle((272, 448, 342, 480), radius=14, fill=INK)
    # 挥手臂
    if wave:
        d.rounded_rectangle((356, 132, 416, 252), radius=30, fill=INK)
        d.ellipse((384, 96, 448, 160), fill=INK)
    return im

mascot = draw_mascot(False)
mascot.save(f'{OUT}/mascot.png')
mascot.save(f'{PREV}/mascot.png')
wave = draw_mascot(True)
wave.save(f'{OUT}/mascot_wave.png')
wave.save(f'{PREV}/mascot_wave.png')
print('mascot ok')

# ---------- 空状态（合上的书 + 将落的液态彩滴） ----------
im = new_layer((512, 512))
d = ImageDraw.Draw(im)
d.rounded_rectangle((116, 268, 396, 356), radius=12, fill=INK)
d.rectangle((128, 256, 384, 272), fill=(238, 238, 238, 255))
d.polygon([(256, 96), (230, 152), (282, 152)], fill=VIOLET)
d.ellipse((226, 148, 286, 208), fill=VIOLET)
im.save(f'{OUT}/empty_flat.png')
im.save(f'{PREV}/empty_flat.png')
print('empty ok')

# ---------- App 图标（扁平：黑圆角方块 + 白色开书 V + 液态彩滴） ----------
im = new_layer((1024, 1024))
d = ImageDraw.Draw(im)
d.rounded_rectangle((192, 192, 832, 832), radius=190, fill=INK)
d.polygon([(292, 560), (512, 462), (512, 540), (292, 620)], fill=WHITE)
d.polygon([(732, 560), (512, 462), (512, 540), (732, 620)], fill=WHITE)
d.polygon([(512, 236), (478, 306), (546, 306)], fill=VIOLET)
d.ellipse((474, 296, 550, 372), fill=VIOLET)
im = im.convert('RGB')
im.save(f'{OUT}/app_icon_fg.png')   # 不透明扁平前景（白底上更稳）
bg = Image.new('RGB', (1024, 1024), (250, 250, 250))
bg.save(f'{OUT}/app_icon_bg.png')
im.save(f'{PREV}/app_icon.png')
bg.save(f'{PREV}/app_icon_bg.png')
print('app icon ok')
