import io, os
from PIL import Image, ImageChops

RAW = 'assets_raw'
MEDIA = 'entry/src/main/resources/base/media'
PREV = 'assets'
os.makedirs(PREV, exist_ok=True)

def audit_grayscale(path):
    im = Image.open(path).convert('RGB')
    g = im.convert('L')
    diff = ImageChops.difference(im, Image.merge('RGB', (g, g, g)))
    print(f'  灰阶偏差极值: {diff.getextrema()}')

def audit_alpha(path):
    im = Image.open(path)
    a = im.getchannel('A')
    print(f'  alpha 范围: {a.getextrema()}')

print('== 审计：封面灰阶（用户称 0 偏色）==')
for i in range(1, 6):
    p = f'{RAW}/cover_0{i}.png'
    print(f'cover_0{i}:')
    audit_grayscale(p)

print('== 审计：透明件 alpha ==')
for f in ['icon_fg.png', 'mascot.png', 'mascot_wave.png', 'empty_books.png', 'icons_sheet.png']:
    print(f + ':')
    audit_alpha(f'{RAW}/{f}')

print('== 审计：紫点缀存在性（mascot 采样）==')
im = Image.open(f'{RAW}/mascot.png').convert('RGBA')
violet = 0
px = im.load()
for y in range(0, im.height, 8):
    for x in range(0, im.width, 8):
        r, g, b, a = px[x, y]
        if a > 200 and b > 120 and b > g + 30 and r < b:
            violet += 1
print(f'  紫色系采样点: {violet}')

print('== 处理：缩放与输出 ==')
def save_scaled(src, dst_sizes):
    im = Image.open(src)
    for (dst, size) in dst_sizes:
        out = im.convert('RGBA') if im.mode in ('RGBA', 'LA', 'P') else im.convert('RGB')
        out = out.resize(size, Image.LANCZOS)
        out.save(dst, optimize=True)
        print(f'  {dst} <- {src} {out.size}')

# 封面 480x720
for i in range(1, 6):
    save_scaled(f'{RAW}/cover_0{i}.png', [
        (f'{MEDIA}/cover_0{i}.png', (480, 720)),
        (f'{PREV}/cover_0{i}.png', (480, 720)),
    ])

# 吉祥物/空状态 512
for f in ['mascot', 'mascot_wave', 'empty_books']:
    save_scaled(f'{RAW}/{f}.png', [
        (f'{MEDIA}/{f}.png', (512, 512)),
        (f'{PREV}/{f}.png', (512, 512)),
    ])

# 纸纹 512（平铺更轻）
for f in ['paper_warm', 'paper_white']:
    save_scaled(f'{RAW}/{f}.png', [
        (f'{MEDIA}/{f}.png', (512, 512)),
        (f'{PREV}/{f}.png', (512, 512)),
    ])

# App 图标层 1024（覆盖模板默认）
save_scaled(f'{RAW}/icon_fg.png', [('AppScope/resources/base/media/foreground.png', (1024, 1024))])
save_scaled(f'{RAW}/icon_bg.png', [('AppScope/resources/base/media/background.png', (1024, 1024))])

# 图标套件留档（暂不接线）
save_scaled(f'{RAW}/icons_sheet.png', [(f'{PREV}/icons_sheet.png', (1024, 1024))])

print('== 媒体目录终览 ==')
for f in sorted(os.listdir(MEDIA)):
    print(' ', f, os.path.getsize(f'{MEDIA}/{f}') // 1024, 'KB')
