#!/usr/bin/env python3
"""Génère les 12 icônes (1024x1024 opaques) + aperçus 256px dans Assets.xcassets."""
import json, math, os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 2  # supersampling
OUT = os.path.join(os.path.dirname(__file__), "..", "Galerie", "Assets.xcassets")

def grad(c1, c2, size=S*SS, angle=135):
    img = Image.new("RGB", (size, size))
    px = img.load()
    a = math.radians(angle)
    dx, dy = math.cos(a), math.sin(a)
    for y in range(size):
        for x in range(size):
            t = ((x/size-0.5)*dx + (y/size-0.5)*dy) + 0.5
            t = max(0, min(1, t))
            px[x, y] = tuple(int(c1[i]+(c2[i]-c1[i])*t) for i in range(3))
    return img

def flower(img, colors, center_color=None, petals=8, scale=1.0, alpha=235):
    size = img.size[0]
    layer = Image.new("RGBA", img.size, (0,0,0,0))
    cx = cy = size/2
    r = size*0.30*scale
    for i in range(petals):
        petal = Image.new("RGBA", img.size, (0,0,0,0))
        d = ImageDraw.Draw(petal)
        w, h = size*0.17*scale, size*0.31*scale
        d.ellipse([cx-w, cy-h-r*0.05, cx+w, cy+h*0.05-r*0.05], fill=colors[i % len(colors)] + (alpha,))
        petal = petal.rotate(i*360/petals, center=(cx, cy), resample=Image.BICUBIC)
        layer = Image.alpha_composite(layer, petal)
    base = img.convert("RGBA")
    out = Image.alpha_composite(base, layer)
    if center_color:
        d = ImageDraw.Draw(out)
        rr = size*0.09*scale
        d.ellipse([cx-rr, cy-rr, cx+rr, cy+rr], fill=center_color + (255,))
    return out.convert("RGB")

def lens(img, ring, inner, glint=(255,255,255)):
    size = img.size[0]
    d = ImageDraw.Draw(img)
    cx = cy = size/2
    for frac, col in [(0.36, ring), (0.30, tuple(int(c*0.55) for c in ring)), (0.24, inner), (0.14, tuple(int(c*0.5) for c in inner))]:
        r = size*frac
        d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=col)
    r = size*0.045
    gx, gy = cx-size*0.08, cy-size*0.09
    d.ellipse([gx-r, gy-r, gx+r, gy+r], fill=glint)
    return img

def photo_glyph(img, sky_top, sky_bot, mountain, sun):
    size = img.size[0]
    d = ImageDraw.Draw(img)
    m = size*0.2
    box = [m, m*1.1, size-m, size-m*1.1]
    frame = Image.new("RGB", img.size, (0,0,0))
    fd = ImageDraw.Draw(frame)
    h = int(box[3]-box[1])
    for y in range(h):
        t = y/max(1,h-1)
        col = tuple(int(sky_top[i]+(sky_bot[i]-sky_top[i])*t) for i in range(3))
        fd.line([(box[0], box[1]+y), (box[2], box[1]+y)], fill=col)
    fd.polygon([(box[0], box[3]), (box[0]+size*0.22, box[1]+size*0.30), (box[0]+size*0.36, box[3]-size*0.15), (box[0]+size*0.48, box[1]+size*0.38), (box[2], box[3])], fill=mountain)
    rr = size*0.06
    sx, sy = box[2]-size*0.17, box[1]+size*0.14
    fd.ellipse([sx-rr, sy-rr, sx+rr, sy+rr], fill=sun)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=size*0.07, fill=255)
    img.paste(frame, (0,0), mask)
    return img

def glass_overlay(img):
    size = img.size[0]
    over = Image.new("RGBA", img.size, (0,0,0,0))
    d = ImageDraw.Draw(over)
    d.ellipse([-size*0.2, -size*0.55, size*1.2, size*0.45], fill=(255,255,255,55))
    over = over.filter(ImageFilter.GaussianBlur(size*0.01))
    return Image.alpha_composite(img.convert("RGBA"), over).convert("RGB")

W = (255,255,255)
ICONS = {}

def icon_default():
    i = grad((20,24,60),(70,40,140),angle=120)
    return flower(i, [(255,255,255),(210,225,255)], center_color=(255,214,102), petals=8)
def icon_lens():
    i = grad((30,30,36),(8,8,12),angle=90)
    return lens(i, (190,190,200), (40,70,140))
def icon_gradient():
    i = grad((255,138,76),(190,60,160),angle=135)
    return flower(i, [(255,255,255)], center_color=(255,236,170), petals=6, alpha=225)
def icon_glass():
    i = grad((150,200,255),(200,170,255),angle=135)
    i = flower(i, [(255,255,255),(235,245,255)], center_color=(255,255,255), petals=8, alpha=150)
    return glass_overlay(i)
def icon_mono():
    i = Image.new("RGB",(S*SS,S*SS),(0,0,0))
    return flower(i, [(255,255,255),(200,200,200)], center_color=(255,255,255), petals=8, alpha=240)
def icon_rose():
    i = grad((255,200,220),(240,110,160),angle=135)
    return flower(i, [(255,255,255),(255,235,243)], center_color=(255,200,90), petals=8)
def icon_violet():
    i = grad((120,70,220),(60,20,120),angle=135)
    return flower(i, [(255,255,255),(230,215,255)], center_color=(255,210,120), petals=8)
def icon_blue():
    i = grad((70,170,255),(20,70,210),angle=135)
    return flower(i, [(255,255,255),(220,238,255)], center_color=(255,220,110), petals=8)
def icon_dark():
    i = grad((34,36,44),(12,13,18),angle=135)
    return flower(i, [(120,130,160),(90,100,130)], center_color=(200,210,235), petals=8)
def icon_light():
    i = grad((255,255,255),(228,232,242),angle=135)
    return flower(i, [(90,110,170),(130,150,210)], center_color=(255,180,70), petals=8, alpha=230)
def icon_multi():
    i = grad((250,250,252),(235,235,245),angle=135)
    cols = [(255,69,58),(255,159,10),(255,214,10),(48,209,88),(10,132,255),(94,92,230),(191,90,242),(255,55,95)]
    return flower(i, cols, center_color=(60,60,70), petals=8, alpha=225)
def icon_photo():
    i = grad((30,40,70),(14,16,30),angle=90)
    return photo_glyph(i, (255,170,110),(255,225,170),(40,50,90),(255,250,225))

BUILD = [
 ("AppIcon","default",icon_default),("Icon-Lens","lens",icon_lens),("Icon-Gradient","gradient",icon_gradient),
 ("Icon-Glass","glass",icon_glass),("Icon-Mono","mono",icon_mono),("Icon-Rose","rose",icon_rose),
 ("Icon-Violet","violet",icon_violet),("Icon-Blue","blue",icon_blue),("Icon-Dark","dark",icon_dark),
 ("Icon-Light","light",icon_light),("Icon-Multi","multi",icon_multi),("Icon-Photo","photo",icon_photo),
]

def write_json(path, obj):
    with open(path, "w") as f: json.dump(obj, f, indent=2)

os.makedirs(OUT, exist_ok=True)
write_json(os.path.join(OUT,"Contents.json"), {"info":{"author":"xcode","version":1}})
for asset, key, fn in BUILD:
    big = fn().resize((S,S), Image.LANCZOS)
    d = os.path.join(OUT, asset+".appiconset"); os.makedirs(d, exist_ok=True)
    big.save(os.path.join(d,"icon.png"), "PNG")
    write_json(os.path.join(d,"Contents.json"), {"images":[{"filename":"icon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}})
    # aperçu (coins arrondis, pour le sélecteur)
    prev = big.resize((256,256), Image.LANCZOS)
    pd = os.path.join(OUT, "IconPreview-"+key+".imageset"); os.makedirs(pd, exist_ok=True)
    prev.save(os.path.join(pd,"preview.png"),"PNG")
    write_json(os.path.join(pd,"Contents.json"), {"images":[{"filename":"preview.png","idiom":"universal"}],"info":{"author":"xcode","version":1}})
print("ok")
