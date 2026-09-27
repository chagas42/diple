import sys, glob
from PIL import Image

def build(frames, out, fps=20, width=760, bg=(11,13,16), trim=True):
    ims = []
    box = None
    for f in frames:
        im = Image.open(f).convert("RGBA")
        flat = Image.new("RGB", im.size, bg)
        flat.paste(im, (0,0), im)
        ims.append(flat)
    if trim:
        # caixa que contem conteudo em QUALQUER quadro
        for im in ims:
            g = im.convert("L").point(lambda p: 255 if p > 24 else 0)
            b = g.getbbox()
            if b:
                box = b if box is None else (min(box[0],b[0]), min(box[1],b[1]),
                                             max(box[2],b[2]), max(box[3],b[3]))
        if box:
            pad = 10
            box = (max(0,box[0]-pad), max(0,box[1]-pad),
                   min(ims[0].size[0],box[2]+pad), min(ims[0].size[1],box[3]+pad))
            ims = [im.crop(box) for im in ims]
    w0, h0 = ims[0].size
    h = int(h0 * width / w0)
    ims = [im.resize((width, h), Image.LANCZOS) for im in ims]
    pal = [im.quantize(colors=128, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG) for im in ims]
    pal[0].save(out, save_all=True, append_images=pal[1:],
                duration=int(1000/fps), loop=0, optimize=True, disposal=2)
    return out, (width, h), len(ims)

if __name__ == "__main__":
    src, out, a, b = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    width = int(sys.argv[5]) if len(sys.argv) > 5 else 760
    step = int(sys.argv[6]) if len(sys.argv) > 6 else 2
    fs = sorted(glob.glob(f"{src}/frame-*.png"))[a:b:step]
    o, size, n = build(fs, out, fps=20//step, width=width)
    import os
    print(f"{out}  {size[0]}x{size[1]}  {n} frames  {os.path.getsize(o)//1024} KB")
