import sys, glob, os
from PIL import Image, ImageFilter

BACK = "backdrop.jpg"          # 1280x720 do desktop real
MENUBAR_H = 27                 # altura da barra de menu nessa escala

def backdrop(scale=3):
    b = Image.open(BACK).convert("RGB")
    W, H = b.size
    bar = b.crop((0, 0, W, MENUBAR_H))
    body = b.crop((0, MENUBAR_H, W, H)).filter(ImageFilter.GaussianBlur(14))
    out = Image.new("RGB", (W, H))
    out.paste(bar, (0, 0)); out.paste(body, (0, MENUBAR_H))
    # escurece o corpo para o painel dominar
    body2 = out.crop((0, MENUBAR_H, W, H)).point(lambda p: int(p * 0.62))
    out.paste(body2, (0, MENUBAR_H))
    return out.resize((W*scale, H*scale), Image.LANCZOS)

def compose(frames, out, panel_w_frac=0.40, crop=None, width=820, fps=10):
    base = backdrop()
    BW, BH = base.size
    pw = int(BW * panel_w_frac)
    ims = []
    for f in frames:
        p = Image.open(f).convert("RGBA")
        ph = int(p.size[1] * pw / p.size[0])
        p = p.resize((pw, ph), Image.LANCZOS)
        c = base.copy()
        c.paste(p, ((BW - pw)//2, 0), p)
        ims.append(c)
    if crop:
        ims = [im.crop(crop) for im in ims]
    w0, h0 = ims[0].size
    h = int(h0 * width / w0)
    ims = [im.resize((width, h), Image.LANCZOS) for im in ims]
    q = [im.quantize(colors=160, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG) for im in ims]
    q[0].save(out, save_all=True, append_images=q[1:], duration=int(1000/fps), loop=0, disposal=1)
    print(f"{out}  {width}x{h}  {len(ims)} frames  {os.path.getsize(out)//1024} KB")

if __name__ == "__main__":
    src, out, a, b, step = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
    fs = sorted(glob.glob(f"{src}/frame-*.png"))[a:b:step]
    # recorte medio: centrado no painel, mostrando a barra e o desktop em volta
    BW, BH = 1280*3, 720*3
    cw = int(BW * 0.62); ch = int(BH * 0.47)
    x0 = (BW - cw)//2
    compose(fs, out, crop=(x0, 0, x0+cw, ch), width=int(sys.argv[6]) if len(sys.argv)>6 else 820)
