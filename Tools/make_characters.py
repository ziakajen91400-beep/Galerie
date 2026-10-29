#!/usr/bin/env python3
"""Personnages FICTIFS (créations originales, style manga) pour les thèmes et les icônes.

Aucun personnage existant n'est reproduit : visages, coiffures, tenues et accessoires sont dessinés ici,
de façon procédurale, à partir de paramètres. Génère dans Galerie/Assets.xcassets :
  - Char-<id>.imageset     : buste sur fond transparent (fond du thème)
  - CharFace-<id>.imageset : portrait carré (pastille du thème)
  - Icon-<Nom>.appiconset + IconPreview-<id>.imageset : icône d'app 1024 px assortie
Usage : python3 -I Tools/make_characters.py [--preview dossier]
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFilter

SS = 2                    # sur-échantillonnage
W, H = 1000, 1300         # espace de dessin (unités)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Galerie", "Assets.xcassets")


# ----------------------------------------------------------------- outils
def lighten(c, t): return tuple(int(c[i] + (255 - c[i]) * t) for i in range(3))
def darken(c, t): return tuple(int(c[i] * (1 - t)) for i in range(3))
def mix(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def catmull(pts, closed=True, n=14):
    """Spline de Catmull-Rom : points de contrôle -> courbe lisse."""
    p = list(pts)
    if closed:
        p = [p[-1]] + p + [p[0], p[1]]
    else:
        p = [p[0]] + p + [p[-1]]
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    if not closed:
        out.append(p[-2])
    return out

def mirror(pts, cx=500):
    return [(2 * cx - x, y) for x, y in pts]


class Canvas:
    def __init__(self):
        self.img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))

    def _s(self, pts): return [(x * SS, y * SS) for x, y in pts]

    def shape(self, pts, fill, ink=None, lw=5, smooth=True, alpha=255, closed=True):
        """Remplit une forme (spline) avec contour optionnel."""
        pts = catmull(pts, closed=closed) if smooth else list(pts)
        layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        if fill is not None:
            d.polygon(self._s(pts), fill=tuple(fill) + (alpha,))
        if ink is not None:
            line = self._s(pts + ([pts[0]] if closed else []))
            d.line(line, fill=tuple(ink) + (255,), width=int(lw * SS), joint="curve")
            for x, y in line[::6]:
                r = lw * SS / 2
                d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(ink) + (255,))
        self.img = Image.alpha_composite(self.img, layer)

    def ellipse(self, box, fill, ink=None, lw=4, alpha=255):
        layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        b = [v * SS for v in box]
        if fill is not None: d.ellipse(b, fill=tuple(fill) + (alpha,))
        if ink is not None: d.ellipse(b, outline=tuple(ink) + (255,), width=int(lw * SS))
        self.img = Image.alpha_composite(self.img, layer)

    def stroke(self, pts, color, lw=5, smooth=True, alpha=255, closed=False):
        pts = catmull(pts, closed=closed) if smooth else list(pts)
        layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        line = self._s(pts)
        d.line(line, fill=tuple(color) + (alpha,), width=int(lw * SS), joint="curve")
        r = lw * SS / 2
        for x, y in (line[0], line[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(color) + (alpha,))
        self.img = Image.alpha_composite(self.img, layer)

    def masked(self, mask_pts, painter):
        """Exécute painter(Canvas) puis ne garde que la zone du masque (pour dégradés et ombres)."""
        sub = Canvas()
        painter(sub)
        mask = Image.new("L", self.img.size, 0)
        ImageDraw.Draw(mask).polygon(self._s(catmull(mask_pts)), fill=255)
        a = sub.img.split()[3]
        from PIL import ImageChops
        sub.img.putalpha(ImageChops.multiply(a, mask))
        self.img = Image.alpha_composite(self.img, sub.img)

    def final(self, size):
        return self.img.resize(size, Image.LANCZOS)


# ----------------------------------------------------------------- personnage
class Girl:
    def __init__(self, **kw):
        self.name = kw["name"]
        self.hair = kw["hair"]; self.eye = kw["eye"]
        self.style = kw.get("style", "long")        # long | twin | bob | pony | braid | wavy
        self.bangs = kw.get("bangs", "side")        # side | parted | straight
        self.acc = kw.get("acc", "ribbon")          # ribbon | flower | glasses | star | bunny | cat | clip
        self.acc_color = kw.get("acc_color", (230, 60, 90))
        self.skin = kw.get("skin", (255, 229, 213))
        self.outfit = kw.get("outfit", "sailor")    # sailor | cardigan | scarf | magical | apron
        self.o1 = kw.get("o1", (40, 52, 110)); self.o2 = kw.get("o2", (255, 255, 255)); self.o3 = kw.get("o3", (230, 60, 90))
        self.mouth = kw.get("mouth", "smile")       # smile | open
        self.blush = kw.get("blush", (255, 140, 150))
        self.lash = kw.get("lash")
        self.hair_shadow = darken(self.hair, 0.22)
        self.hair_light = lighten(self.hair, 0.45)
        self.ink = kw.get("ink") or darken(self.hair, 0.62)
        self.skin_shadow = darken(self.skin, 0.09)

    # ---- couches
    def back_hair(self, c):
        h, hs, ink = self.hair, self.hair_shadow, self.ink
        base = [(325, 430), (362, 318), (500, 262), (638, 318), (675, 430)]
        if self.style == "long":
            pts = base + [(742, 640), (770, 900), (735, 1030), (640, 1000), (560, 880), (500, 840), (440, 880), (360, 1000), (265, 1030), (230, 900), (258, 640)]
        elif self.style == "wavy":
            pts = base + [(748, 640), (776, 820), (742, 930), (780, 1040), (690, 1010), (640, 920), (560, 880), (500, 850), (440, 880), (360, 920), (310, 1010), (220, 1040), (258, 930), (224, 820), (252, 640)]
        elif self.style == "bob":
            pts = base + [(700, 600), (708, 700), (665, 760), (560, 735), (500, 745), (440, 735), (335, 760), (292, 700), (300, 600)]
        elif self.style == "pony":
            pts = base + [(690, 560), (672, 690), (610, 735), (500, 720), (390, 735), (328, 690), (310, 560)]
        elif self.style == "braid":
            pts = base + [(700, 600), (712, 740), (660, 810), (560, 780), (500, 790), (440, 780), (340, 810), (288, 740), (300, 600)]
        else:  # twin
            pts = base + [(690, 560), (672, 690), (610, 735), (500, 720), (390, 735), (328, 690), (310, 560)]
        c.shape(pts, h, ink, 5)
        c.masked(pts, lambda s: (s.stroke([(318, 520), (300, 720), (316, 930)], hs, 46, alpha=120),
                                 s.stroke([(682, 520), (700, 720), (684, 930)], hs, 46, alpha=120),
                                 s.stroke([(500, 760), (500, 900)], hs, 30, alpha=90)))

    def tails(self, c):
        h, hs, ink = self.hair, self.hair_shadow, self.ink
        if self.style == "twin":
            left = [(330, 380), (270, 420), (190, 520), (150, 700), (165, 880), (205, 1010), (250, 930), (262, 780), (290, 650), (340, 540)]
            c.shape(left, h, ink, 5)
            c.shape(mirror(left), h, ink, 5)
            for pts in (left, mirror(left)):
                c.masked(pts, lambda s: s.stroke([(200, 560), (190, 760), (215, 930)], hs, 18, alpha=170))
        elif self.style == "pony":
            tail = [(612, 330), (700, 350), (800, 440), (850, 620), (840, 820), (790, 1000), (740, 880), (735, 720), (700, 560), (640, 470)]
            c.shape(tail, h, ink, 5)
            c.masked(tail, lambda s: s.stroke([(790, 470), (810, 680), (790, 900)], hs, 20, alpha=170))

    def body(self, c):
        o1, o2, o3, ink = self.o1, self.o2, self.o3, darken(self.o1, 0.55)
        sk, sks = self.skin, self.skin_shadow
        # cou
        neck = [(462, 650), (538, 650), (548, 790), (500, 830), (452, 790)]
        c.shape(neck, sk, darken(sk, 0.35), 4)
        c.masked(neck, lambda s: s.shape([(440, 650), (560, 650), (560, 745), (500, 770), (440, 745)], sks, None, 0, smooth=False, alpha=200))
        # épaules
        sh = [(190, 1300), (205, 1090), (300, 935), (455, 810), (500, 845), (545, 810), (700, 935), (795, 1090), (810, 1300)]
        base = o1 if self.outfit in ("sailor", "cardigan", "magical", "apron") else o1
        if self.outfit == "cardigan":
            c.shape(sh, o2, ink, 5)                      # chemise
            cl = [(190, 1300), (205, 1090), (300, 935), (420, 820), (470, 905), (455, 1300)]
            c.shape(cl, o1, ink, 5); c.shape(mirror(cl), o1, ink, 5)
        else:
            c.shape(sh, base, ink, 5)
        if self.outfit == "sailor":
            col = [(455, 800), (500, 842), (545, 800), (640, 850), (560, 1010), (500, 930), (440, 1010), (360, 850)]
            c.shape(col, o2, ink, 5)
            c.stroke([(380, 850), (500, 940)], o3, 6); c.stroke([(620, 850), (500, 940)], o3, 6)
            self.bow(c, (500, 960), o3, 1.0)
        elif self.outfit == "cardigan":
            c.shape([(455, 800), (500, 842), (545, 800), (560, 830), (500, 900), (440, 830)], darken(o2, 0.06), ink, 4)
            self.bow(c, (500, 905), o3, 0.95)
        elif self.outfit == "scarf":
            c.shape(sh, o1, ink, 5)
            sc = [(380, 790), (500, 840), (620, 790), (680, 880), (620, 960), (500, 940), (380, 960), (320, 880)]
            c.shape(sc, o3, darken(o3, 0.5), 5)
            tail = [(560, 930), (640, 1010), (660, 1180), (590, 1200), (565, 1080)]
            c.shape(tail, o3, darken(o3, 0.5), 5)
            c.stroke([(400, 850), (500, 890), (600, 850)], darken(o3, 0.25), 6)
        elif self.outfit == "magical":
            col = [(455, 800), (500, 842), (545, 800), (650, 850), (580, 960), (500, 900), (420, 960), (350, 850)]
            c.shape(col, o2, darken(o3, 0.4), 5)
            c.stroke([(365, 860), (500, 915), (635, 860)], o3, 8)
            self.star(c, (500, 960), 46, o3, darken(o3, 0.4))
        elif self.outfit == "apron":
            ap = [(330, 1300), (360, 960), (440, 905), (560, 905), (640, 960), (670, 1300)]
            c.shape(ap, o2, darken(o1, 0.5), 5)
            c.stroke([(440, 905), (400, 800)], o2, 14, smooth=False); c.stroke([(560, 905), (600, 800)], o2, 14, smooth=False)
            col = [(455, 800), (500, 842), (545, 800), (600, 840), (500, 900), (400, 840)]
            c.shape(col, o2, darken(o1, 0.5), 4)
            self.bow(c, (500, 920), o3, 0.8)

    def bow(self, c, p, col, s):
        x, y = p
        ink = darken(col, 0.5)
        l = [(x - 8 * s, y), (x - 70 * s, y - 40 * s), (x - 84 * s, y + 6 * s), (x - 66 * s, y + 46 * s)]
        c.shape(l, col, ink, 4); c.shape(mirror(l, x), col, ink, 4)
        c.ellipse([x - 20 * s, y - 20 * s, x + 20 * s, y + 20 * s], lighten(col, 0.12), ink, 4)

    def star(self, c, p, r, col, ink):
        pts = []
        for i in range(10):
            a = -math.pi / 2 + i * math.pi / 5
            rr = r if i % 2 == 0 else r * 0.45
            pts.append((p[0] + math.cos(a) * rr, p[1] + math.sin(a) * rr))
        c.shape(pts, col, ink, 4, smooth=False)

    def face(self, c):
        sk = self.skin
        face = [(500, 318), (588, 334), (645, 398), (660, 490), (642, 578), (600, 642), (545, 688), (500, 702), (455, 688), (400, 642), (358, 578), (340, 490), (355, 398), (412, 334)]
        c.shape(face, sk, darken(sk, 0.4), 5)
        # ombre douce sous le menton et sur les côtés
        c.masked(face, lambda s: s.stroke([(390, 672), (450, 704), (500, 712), (550, 704), (610, 672)], self.skin_shadow, 34, alpha=120))
        c.masked(face, lambda s: s.stroke([(352, 420), (344, 520), (366, 600)], self.skin_shadow, 16, alpha=120))
        # joues
        for x in (412, 588):
            layer = Canvas()
            layer.ellipse([x - 44, 572, x + 44, 622], self.blush, None, alpha=105)
            layer.img = layer.img.filter(ImageFilter.GaussianBlur(7 * SS))
            c.img = Image.alpha_composite(c.img, layer.img)
        # yeux
        for sx in (-1, 1):
            self.eye_at(c, 500 + sx * 74, 528, sx)
        # sourcils
        bc = self.hair_shadow
        c.stroke([(386, 462), (426, 448), (466, 452)], bc, 6)
        c.stroke([(534, 452), (574, 448), (614, 462)], bc, 6)
        # nez
        c.stroke([(498, 590), (503, 598), (498, 603)], darken(self.skin, 0.28), 3)
        # bouche
        if self.mouth == "open":
            m = [(466, 634), (500, 650), (534, 634), (522, 668), (500, 678), (478, 668)]
            c.shape(m, (150, 50, 70), (110, 30, 50), 4)
            c.shape([(482, 660), (500, 672), (518, 660), (500, 668)], (255, 130, 140), None, 0)
        else:
            c.stroke([(470, 640), (486, 652), (500, 654), (514, 652), (530, 640)], (170, 70, 85), 5)

    def eye_at(self, c, cx, cy, side):
        ink = self.lash or darken(self.hair, 0.7)
        iris, iris_d = self.eye, darken(self.eye, 0.45)
        # sclère
        sc = [(cx - 40, cy - 6), (cx - 28, cy - 42), (cx, cy - 52), (cx + 28, cy - 42), (cx + 40, cy - 6), (cx + 34, cy + 36), (cx, cy + 56), (cx - 34, cy + 36)]
        c.shape(sc, (255, 255, 255), None, 0)
        # iris avec dégradé
        ir = [(cx - 31, cy - 4), (cx - 22, cy - 38), (cx, cy - 46), (cx + 22, cy - 38), (cx + 31, cy - 4), (cx + 25, cy + 34), (cx, cy + 50), (cx - 25, cy + 34)]
        c.masked(ir, lambda s: (s.shape(ir, iris_d, None, 0),
                                s.ellipse([cx - 34, cy - 6, cx + 34, cy + 60], iris, None),
                                s.ellipse([cx - 24, cy + 14, cx + 24, cy + 56], lighten(iris, 0.35), None, alpha=210)))
        c.ellipse([cx - 13, cy - 14, cx + 13, cy + 22], (30, 22, 40))
        # reflets
        c.ellipse([cx - 22, cy - 34, cx - 2, cy - 8], (255, 255, 255))
        c.ellipse([cx + 8, cy + 14, cx + 20, cy + 26], (255, 255, 255), alpha=235)
        # cils supérieurs épais + virgule extérieure
        o = -side
        top = [(cx - 44 * o * -1 if False else cx - 46, cy - 4)]
        up = [(cx - 44, cy + 2), (cx - 30, cy - 40), (cx, cy - 56), (cx + 30, cy - 40), (cx + 44, cy + 2)]
        c.stroke(up, ink, 10)
        wing = [(cx + 44 * side, cy + 2), (cx + 58 * side, cy - 8), (cx + 66 * side, cy - 22)]
        c.stroke(wing, ink, 8)
        c.stroke([(cx - 30, cy + 44), (cx, cy + 56), (cx + 30, cy + 44)], darken(self.skin, 0.4), 3, alpha=150)
        c.stroke([(cx - 36, cy - 62), (cx, cy - 74), (cx + 36, cy - 62)], darken(self.skin, 0.30), 3, alpha=110)

    def bangs_layer(self, c):
        h, hs, hl, ink = self.hair, self.hair_shadow, self.hair_light, self.ink
        if self.bangs == "straight":
            b = [(332, 480), (336, 380), (404, 316), (500, 296), (596, 316), (664, 380), (668, 480), (640, 470), (616, 436), (590, 478), (556, 440), (528, 482), (500, 440), (472, 482), (444, 440), (410, 478), (384, 436), (360, 470)]
        elif self.bangs == "parted":
            b = [(332, 490), (336, 380), (404, 316), (480, 298), (500, 330), (520, 298), (596, 316), (664, 380), (668, 490), (648, 520), (618, 456), (580, 410), (540, 420), (516, 372), (500, 360), (484, 372), (460, 420), (420, 410), (382, 456), (352, 520)]
        else:  # side
            b = [(332, 490), (336, 380), (404, 316), (500, 296), (596, 316), (664, 380), (670, 500), (646, 450), (606, 468), (588, 420), (556, 478), (522, 424), (484, 470), (440, 420), (410, 470), (372, 440), (352, 520)]
        c.shape(b, h, ink, 5)
        c.masked(b, lambda s: s.shape([(320, 300), (680, 300), (680, 372), (320, 372)], hl, None, 0, smooth=False, alpha=0))
        # reflet « anneau angélique »
        c.masked(b, lambda s: s.stroke([(372, 376), (430, 342), (500, 330), (570, 342), (628, 376)], hl, 26, alpha=175))
        # mèches (traits d'encre fins)
        for x0, x1 in ((420, 436), (470, 480), (520, 510), (570, 560)):
            c.stroke([(x0, 330), (x1, 400), (x1 - 4, 440)], darken(h, 0.35), 3, alpha=140)
        # ombre portée du front sous les mèches
        # mèches latérales devant les oreilles
        l = [(336, 470), (352, 520), (360, 625), (344, 730), (320, 805), (322, 700), (318, 590), (320, 520)]
        c.shape(l, h, ink, 5); c.shape(mirror(l), h, ink, 5)
        for pts in (l, mirror(l)):
            c.masked(pts, lambda s: s.stroke([(336, 520), (338, 640), (330, 740)], hl, 9, alpha=150))

    def braid(self, c):
        h, hs, ink = self.hair, self.hair_shadow, self.ink
        pts = []
        y = 760
        for i in range(7):
            xo = -18 if i % 2 == 0 else 14
            c.ellipse([330 + xo - 50, y - 6, 330 + xo + 50, y + 82], h if i % 2 == 0 else hs, ink, 4)
            y += 64
        c.shape([(300, 1200), (360, 1200), (380, 1260), (330, 1290), (285, 1260)], h, ink, 4)
        c.ellipse([306, 1190, 354, 1214], self.acc_color, darken(self.acc_color, 0.5), 3)
        # attache haute
        c.ellipse([300, 735, 360, 765], self.acc_color, darken(self.acc_color, 0.5), 3)

    def accessory(self, c):
        a, col = self.acc, self.acc_color
        ink = darken(col, 0.5)
        if a == "ribbon":
            x, y = 612, 340
            l = [(x - 4, y), (x - 66, y - 52), (x - 92, y - 6), (x - 62, y + 42)]
            c.shape(l, col, ink, 4); c.shape(mirror(l, x), col, ink, 4)
            c.ellipse([x - 20, y - 20, x + 20, y + 20], lighten(col, 0.15), ink, 4)
        elif a == "flower":
            cx, cy = 396, 352
            for i in range(5):
                ang = -math.pi / 2 + i * 2 * math.pi / 5
                px, py = cx + math.cos(ang) * 30, cy + math.sin(ang) * 30
                c.ellipse([px - 24, py - 24, px + 24, py + 24], col, ink, 4)
            c.ellipse([cx - 18, cy - 18, cx + 18, cy + 18], (255, 214, 102), darken((255, 214, 102), 0.5), 4)
        elif a == "glasses":
            for sx in (-1, 1):
                cx = 500 + sx * 74
                c.ellipse([cx - 62, 468, cx + 62, 592], None, (70, 60, 90), 7)
                c.stroke([(cx - 40, 500), (cx - 20, 484)], (255, 255, 255), 5, alpha=170)
            c.stroke([(438, 520), (500, 508), (562, 520)], (70, 60, 90), 6)
            c.stroke([(376, 520), (352, 514)], (70, 60, 90), 6); c.stroke([(624, 520), (648, 514)], (70, 60, 90), 6)
        elif a == "star":
            self.star(c, (404, 372), 34, col, ink); self.star(c, (596, 372), 34, col, ink)
        elif a == "bunny":
            band = [(338, 420), (370, 330), (500, 292), (630, 330), (662, 420)]
            for x, tilt in ((420, -10), (580, 10)):
                ear = [(x - 34, 330), (x - 40, 200), (x - 26, 96), (x, 70), (x + 26, 96), (x + 40, 200), (x + 34, 330)]
                c.shape(ear, (255, 255, 255), (150, 130, 160), 5)
                c.shape([(x - 15, 310), (x - 18, 200), (x - 8, 120), (x, 104), (x + 8, 120), (x + 18, 200), (x + 15, 310)], (255, 170, 205), None, 0)
            c.stroke([(352, 400), (390, 338), (500, 306), (610, 338), (648, 400)], col, 13)
        elif a == "cat":
            for sx in (-1, 1):
                x = 500 + sx * 120
                ear = [(x - 60 * sx * -1 if False else x - 62, 360), (x - 38 * sx, 232), (x + 8 * sx, 270), (x + 62 * -sx * -1 if False else x + 62, 360)]
                ear = [(x - 62, 362), (x - 46 + (sx * 10), 226), (x + 16, 276), (x + 62, 362)]
                c.shape(ear, self.hair, self.ink, 5, smooth=False)
                c.shape([(x - 36, 350), (x - 28 + sx * 8, 262), (x + 16, 296), (x + 36, 350)], (255, 170, 190), None, 0, smooth=False)
        elif a == "clip":
            for x in (392, 424):
                c.stroke([(x - 22, 392), (x + 24, 352)], col, 12, smooth=False)
            for x in (392, 424):
                c.stroke([(x - 22, 352), (x + 24, 392)], lighten(col, 0.4), 6, smooth=False)

    # ---- assemblage
    def render(self):
        c = Canvas()
        self.tails(c)
        self.back_hair(c)
        self.body(c)
        self.face(c)
        if self.style == "braid": pass
        self.bangs_layer(c)
        if self.style == "braid": self.braid(c)
        self.accessory(c)
        return c.img


# ----------------------------------------------------------------- fond d'icône
def gradient(size, c1, c2, angle=135):
    img = Image.new("RGB", (size, size))
    px = img.load()
    a = math.radians(angle); dx, dy = math.cos(a), math.sin(a)
    for y in range(size):
        for x in range(size):
            t = max(0, min(1, ((x / size - 0.5) * dx + (y / size - 0.5) * dy) + 0.5))
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img

def sparkle(d, x, y, r, col):
    d.polygon([(x, y - r * 2.2), (x + r * 0.5, y - r * 0.5), (x + r * 2.2, y), (x + r * 0.5, y + r * 0.5), (x, y + r * 2.2), (x - r * 0.5, y + r * 0.5), (x - r * 2.2, y), (x - r * 0.5, y - r * 0.5)], fill=col)

def decorate(img, kind, accent):
    """Motifs simples derrière le personnage (étoiles, flocons, pétales, pattes…)."""
    S = img.size[0]
    d = ImageDraw.Draw(img, "RGBA")
    spots = [(0.14, 0.18, 14), (0.86, 0.16, 11), (0.9, 0.5, 9), (0.1, 0.5, 10), (0.2, 0.34, 7), (0.8, 0.32, 8), (0.5, 0.08, 9)]
    for (x, y, r) in spots:
        if kind == "snow":
            col = (255, 255, 255, 190)
            for k in range(3):
                a = k * math.pi / 3
                d.line([(S * x - math.cos(a) * r * 1.6, S * y - math.sin(a) * r * 1.6), (S * x + math.cos(a) * r * 1.6, S * y + math.sin(a) * r * 1.6)], fill=col, width=3)
        elif kind == "petal":
            d.ellipse([S * x - r, S * y - r * 0.7, S * x + r, S * y + r * 0.7], fill=(255, 255, 255, 170))
        elif kind == "paw":
            d.ellipse([S * x - r, S * y - r * 0.6, S * x + r, S * y + r * 0.9], fill=(255, 255, 255, 120))
            for dx in (-1.1, 0, 1.1):
                d.ellipse([S * x + dx * r - r * 0.35, S * y - r * 1.4, S * x + dx * r + r * 0.35, S * y - r * 0.7], fill=(255, 255, 255, 120))
        else:
            sparkle(d, S * x, S * y, r * 0.8, (255, 255, 255, 215))
    return img


# ----------------------------------------------------------------- roster
# id, nom affiché, paramètres du personnage, couleurs de l'icône, motif
ROSTER = [
    dict(id="sakura", icon="Icon-Sakura", title="Sakura", fam="fleurs",
         girl=dict(name="Sakura", hair=(247, 150, 190), eye=(214, 76, 130), style="twin", bangs="side", acc="ribbon", acc_color=(236, 64, 100),
                   outfit="sailor", o1=(52, 62, 120), o2=(255, 255, 255), o3=(236, 64, 100)),
         bg=((255, 214, 232), (240, 110, 160)), deco="petal"),
    dict(id="sora", icon="Icon-Sora", title="Sora", fam="fleurs",
         girl=dict(name="Sora", hair=(116, 186, 240), eye=(54, 120, 218), style="long", bangs="parted", acc="clip", acc_color=(255, 255, 255),
                   outfit="sailor", o1=(70, 100, 170), o2=(255, 255, 255), o3=(90, 150, 235)),
         bg=((200, 232, 255), (70, 140, 225)), deco="sparkle"),
    dict(id="midori", icon="Icon-Midori", title="Midori", fam="fleurs",
         girl=dict(name="Midori", hair=(104, 198, 126), eye=(36, 146, 88), style="bob", bangs="straight", acc="glasses",
                   outfit="cardigan", o1=(214, 188, 150), o2=(255, 255, 255), o3=(60, 150, 100)),
         bg=((206, 245, 214), (60, 168, 100)), deco="petal"),
    dict(id="akane", icon="Icon-Akane", title="Akane", fam="fleurs",
         girl=dict(name="Akane", hair=(238, 108, 76), eye=(255, 168, 52), style="pony", bangs="side", acc="star", acc_color=(255, 214, 80),
                   outfit="sailor", o1=(160, 40, 50), o2=(255, 255, 255), o3=(255, 200, 70), mouth="open"),
         bg=((255, 214, 186), (232, 84, 70)), deco="sparkle"),
    dict(id="murasaki", icon="Icon-Murasaki", title="Murasaki", fam="fleurs",
         girl=dict(name="Murasaki", hair=(150, 110, 222), eye=(112, 60, 192), style="braid", bangs="parted", acc="flower", acc_color=(255, 170, 214),
                   outfit="cardigan", o1=(190, 170, 235), o2=(255, 255, 255), o3=(120, 80, 200)),
         bg=((228, 214, 255), (128, 88, 212)), deco="petal"),
    dict(id="yuki", icon="Icon-Yuki", title="Yuki", fam="neige",
         girl=dict(name="Yuki", hair=(236, 240, 252), eye=(88, 170, 236), style="wavy", bangs="parted", acc="ribbon", acc_color=(214, 40, 62),
                   skin=(255, 236, 228), outfit="scarf", o1=(40, 52, 96), o2=(255, 255, 255), o3=(214, 40, 62), ink=(110, 120, 170)),
         bg=((218, 232, 255), (92, 124, 206)), deco="snow"),
    dict(id="luna", icon="Icon-Luna", title="Luna", fam="lune",
         girl=dict(name="Luna", hair=(78, 52, 122), eye=(208, 66, 156), style="bob", bangs="side", acc="bunny", acc_color=(255, 110, 180),
                   outfit="cardigan", o1=(52, 36, 84), o2=(255, 255, 255), o3=(255, 100, 170), mouth="smile", ink=(34, 20, 60)),
         bg=((86, 34, 120), (22, 8, 44)), deco="sparkle"),
    dict(id="hikari", icon="Icon-Hikari", title="Hikari", fam="etoile",
         girl=dict(name="Hikari", hair=(255, 206, 92), eye=(54, 186, 200), style="pony", bangs="straight", acc="star", acc_color=(255, 138, 60),
                   outfit="magical", o1=(255, 130, 170), o2=(255, 255, 255), o3=(255, 160, 40), mouth="open"),
         bg=((255, 240, 190), (255, 140, 70)), deco="sparkle"),
    dict(id="nekomi", icon="Icon-Nekomi", title="Nekomi", fam="cafe",
         girl=dict(name="Nekomi", hair=(176, 116, 74), eye=(150, 176, 56), style="bob", bangs="side", acc="cat", acc_color=(240, 150, 170),
                   outfit="apron", o1=(122, 40, 56), o2=(255, 250, 244), o3=(240, 120, 150)),
         bg=((255, 226, 196), (206, 120, 80)), deco="paw"),
]


def write_json(path, obj):
    with open(path, "w") as f: json.dump(obj, f, indent=2)

def imageset(name, filename, img):
    d = os.path.join(OUT, name + ".imageset"); os.makedirs(d, exist_ok=True)
    img.save(os.path.join(d, filename), "PNG", optimize=True)
    write_json(os.path.join(d, "Contents.json"), {"images": [{"filename": filename, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}})

def appiconset(name, img):
    d = os.path.join(OUT, name + ".appiconset"); os.makedirs(d, exist_ok=True)
    img.save(os.path.join(d, "icon.png"), "PNG", optimize=True)
    write_json(os.path.join(d, "Contents.json"), {"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}})


def make_icon(art, r):
    """Icône 1024 : dégradé assorti + motifs + portrait (tête et épaules) du personnage."""
    S = 1024
    bg = gradient(S, r["bg"][0], r["bg"][1]).convert("RGBA")
    bg = decorate(bg, r["deco"], r["girl"].get("acc_color"))
    # portrait : on recadre la tête et les épaules
    crop = art.crop((140 * SS, 56 * SS, 860 * SS, 776 * SS))
    scale = (S * 1.0) / crop.size[0]
    pw, ph = int(crop.size[0] * scale), int(crop.size[1] * scale)
    port = crop.resize((pw, ph), Image.LANCZOS)
    shadow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    sh = Image.new("RGBA", (pw, ph), (0, 0, 0, 0)); sh.putalpha(port.split()[3].point(lambda v: int(v * 0.28)))
    shadow.paste(sh.filter(ImageFilter.GaussianBlur(14)), (0, S - ph + 20), sh.filter(ImageFilter.GaussianBlur(14)))
    bg = Image.alpha_composite(bg, shadow)
    bg.alpha_composite(port, (0, S - ph))
    return bg.convert("RGB")


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]; os.makedirs(preview, exist_ok=True)
    sheet = []
    for r in ROSTER:
        girl = Girl(**r["girl"])
        art = girl.render()                                   # RGBA (W*SS, H*SS)
        bust = art.resize((800, 1040), Image.LANCZOS)
        face = art.crop((220 * SS, 230 * SS, 780 * SS, 790 * SS)).resize((384, 384), Image.LANCZOS)
        icon = make_icon(art, r)
        if preview:
            bust.save(os.path.join(preview, f"bust-{r['id']}.png")); icon.resize((256, 256)).save(os.path.join(preview, f"icon-{r['id']}.png"))
            sheet.append((bust, icon))
            continue
        imageset("Char-" + r["id"], "char.png", bust)
        imageset("CharFace-" + r["id"], "face.png", face)
        appiconset(r["icon"], icon)
        imageset("IconPreview-" + r["id"], "preview.png", icon.resize((256, 256), Image.LANCZOS))
    if preview:
        n = len(sheet)
        S = Image.new("RGB", (n * 300, 400 + 300), (60, 60, 70))
        for i, (b, ic) in enumerate(sheet):
            bb = b.resize((300, 390)); bgc = Image.new("RGB", bb.size, (235, 235, 240)); bgc.paste(bb, (0, 0), bb)
            S.paste(bgc, (i * 300, 0)); S.paste(ic.resize((256, 256)), (i * 300 + 22, 420))
        S.save(os.path.join(preview, "sheet.png"))
    print("ok")

if __name__ == "__main__":
    main()
