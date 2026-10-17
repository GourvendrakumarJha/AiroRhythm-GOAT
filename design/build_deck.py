#!/usr/bin/env python3
"""Rebuild the AiroRhythm one-pager deck with larger, more readable type.

Original deck: 3 x A4 pages, Helvetica, ~8.0-8.4 pt body copy.
This rebuild keeps the same visual language (colours, cards, layout)
but sets body copy at ~10 pt and scales headings to match.
"""

import os
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.pdfbase.pdfmetrics import stringWidth

W, H = 595.2756, 841.8898
CAP = 0.717  # Helvetica cap height

# ---------------------------------------------------------------- palette
INK        = HexColor("#111827")
BODY       = HexColor("#263449")
MUTED      = HexColor("#627188")
CYAN       = HexColor("#24B7F2")
PURPLE     = HexColor("#8D4DF2")
BG         = HexColor("#F5F8FC")
DARK       = HexColor("#05060A")
HERO_SUB   = HexColor("#E1E7F0")
HERO_TAG   = HexColor("#B9C4D5")
BLUE_CARD  = HexColor("#E9F8FD")
BLUE_BORD  = HexColor("#C9EAF7")
PURP_CARD  = HexColor("#F4EDFF")
PURP_BORD  = HexColor("#E1D5FA")
SAFE_CARD  = HexColor("#EEF4FB")
SAFE_BORD  = HexColor("#D6E4F1")
BORDER     = HexColor("#DCE5EF")
ALT_ROW    = HexColor("#F0F4F9")
TABLE_HEAD = HexColor("#111827")
WHITE      = HexColor("#FFFFFF")
TEAM_RULE  = HexColor("#323847")
TEAM_ROLE  = HexColor("#AEB9C9")
BRAND_BLUE = HexColor("#33BFF0")
DARK_CARD  = HexColor("#05060A")
DARK_BODY  = HexColor("#E5EAF2")
PILL_BG    = HexColor("#171A26")

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
MARK = os.path.join(ASSETS, "logo_mark.png")
WORD = os.path.join(ASSETS, "wordmark.png")

ML, MR = 42.0, 42.0
CONTENT = W - ML - MR
FOOT_RULE_Y = 798.9

# ---------------------------------------------------------------- sizes
SZ = dict(
    hero_eyebrow=9.0,
    hero_title=30.0,
    hero_sub=13.0,
    hero_tag=10.5,
    brand=9.0,
    page_eyebrow=9.0,
    page_title=21.0,
    kicker=13.0,
    card_title=10.8,
    body=10.8, body_lh=15.0,
    small=9.9, small_lh=13.6,
    tiny=9.2, tiny_lh=12.9,
    footer=8.8,
)


class Deck:
    def __init__(self, path):
        self.c = canvas.Canvas(path, pagesize=(W, H))
        self.c.setTitle("AiroRhythm | Atomberg challenge")
        self.c.setAuthor("Team AiroRhythm")
        self.c.setSubject("AtomQuest 2026 by Atomberg - Smart ventilation concept deck")
        self.n = 0

    # ---------------------------------------------------------- helpers
    def new_page(self):
        if self.n:
            self.c.showPage()
        self.n += 1
        self.c.setFillColor(BG)
        self.c.rect(0, 0, W, H, stroke=0, fill=1)

    def rrect(self, x, top, w, h, fill=None, stroke=None, r=9, lw=0.8):
        if fill is not None:
            self.c.setFillColor(fill)
        if stroke is not None:
            self.c.setStrokeColor(stroke)
            self.c.setLineWidth(lw)
        self.c.roundRect(x, H - top - h, w, h, r,
                         stroke=1 if stroke is not None else 0,
                         fill=1 if fill is not None else 0)

    def rect(self, x, top, w, h, fill):
        self.c.setFillColor(fill)
        self.c.rect(x, H - top - h, w, h, stroke=0, fill=1)

    def line(self, x1, y1, x2, y2, color, lw=0.8):
        self.c.setStrokeColor(color)
        self.c.setLineWidth(lw)
        self.c.line(x1, H - y1, x2, H - y2)

    def wrap(self, text, font, size, maxw):
        lines = []
        for chunk in str(text).split("\n"):
            words, cur = chunk.split(" "), ""
            for word in words:
                trial = word if not cur else cur + " " + word
                if stringWidth(trial, font, size) <= maxw or not cur:
                    cur = trial
                else:
                    lines.append(cur)
                    cur = word
            lines.append(cur)
        return lines

    def text(self, s, x, top, size, color, font="Helvetica", leading=None,
             maxw=None, align="left", cap=CAP):
        """Draw text with its glyph-top at `top`. Returns block height."""
        leading = leading or size * 1.32
        lines = self.wrap(s, font, size, maxw) if maxw else [s]
        self.c.setFillColor(color)
        self.c.setFont(font, size)
        for i, ln in enumerate(lines):
            bx = x
            if align == "right":
                bx = x - stringWidth(ln, font, size)
            elif align == "center":
                bx = x - stringWidth(ln, font, size) / 2.0
            self.c.drawString(bx, H - (top + i * leading + cap * size), ln)
        return len(lines) * leading

    def paragraph_height(self, s, font, size, leading, maxw):
        return len(self.wrap(s, font, size, maxw)) * leading

    def img(self, path, x, top, w=None, h=None):
        from reportlab.lib.utils import ImageReader
        ir = ImageReader(path)
        iw, ih = ir.getSize()
        if w is None and h is not None:
            w = h * iw / ih
        elif h is None and w is not None:
            h = w * ih / iw
        self.c.drawImage(path, x, H - top - h, w, h, mask="auto")
        return h

    def label(self, s, x, top, color, size=None):
        """Accent bar + small bold label. Returns height."""
        size = size or SZ["card_title"]
        bar_h = 13.0
        self.c.setFillColor(color)
        self.c.roundRect(x, H - top - bar_h, 3.8, bar_h, 1.6, stroke=0, fill=1)
        self.text(s, x + 11.5, top + (bar_h - CAP * size) / 2 + 0.4, size, INK,
                  "Helvetica-Bold")
        return bar_h

    def hline(self, x1, x2, y, color=BORDER, lw=0.7):
        self.line(x1, y, x2, y, color, lw)

    # ---------------------------------------------------------- chrome
    def hero(self):
        self.rect(0, 0, W, 196.0, DARK)
        # logo lock-up (mark + wordmark)
        self.img(MARK, 76.0, 61.0, w=104.0)
        self.img(WORD, 76.0, 132.0, w=104.0)
        # top-right wordmark note
        self.text("atomQUEST 2026", W - 42.0, 35.5, SZ["brand"], BRAND_BLUE,
                  "Helvetica-Bold", align="right")
        # copy column (explicit glyph tops keep the leading generous)
        x = 245.0
        self.text("ATOMBERG  |  ATOMQUEST 2026", x, 35.5, SZ["hero_eyebrow"],
                  CYAN, "Helvetica-Bold")
        self.text("Air, Reimagined", x, 50.5, SZ["hero_title"], WHITE,
                  "Helvetica-Bold")
        self.text("Smart ventilation for exhaust fans", x, 88.5, SZ["hero_sub"],
                  HERO_SUB)
        self.text("Sense locally. Show clearly.", x, 111.5, SZ["hero_tag"],
                  HERO_TAG)
        # "team" pill
        pill_w, pill_h = 132.0, 24.0
        self.rrect(x, 138.0, pill_w, pill_h, fill=PILL_BG, r=4)
        self.text("team", x + 11, 146.0, 7.8, HERO_SUB)
        self.img(WORD, x + 40, 144.9, w=82.0)
        # progress bar
        self.rect(0, 193.0, 333.4, 3.0, CYAN)
        self.rect(333.4, 193.0, W - 333.4, 3.0, PURPLE)

    def page_head(self, eyebrow, title):
        self.rect(0, 0, W, 73.0, DARK)
        self.rect(0, 70.0, 345.3, 3.0, CYAN)
        self.rect(345.3, 70.0, W - 345.3, 3.0, PURPLE)
        self.text(eyebrow, ML, 15.0, SZ["page_eyebrow"], CYAN, "Helvetica-Bold")
        self.text(title, ML, 28.0, SZ["page_title"], WHITE, "Helvetica-Bold")
        wm_w = 78.0
        wm_h = self.img(WORD, W - MR - wm_w, 22.9, w=wm_w)
        self.c.setFillColor(PURPLE)
        self.c.circle(W - MR - 6.0, H - 49.0, 3.5, stroke=0, fill=1)

    def footer(self):
        self.hline(ML, W - MR, FOOT_RULE_Y, BORDER, 0.7)
        self.text("AiroRhythm | Atomberg challenge", ML, 803.0, SZ["footer"], MUTED)
        self.text(f"{self.n:02d} / 03", W - MR, 803.0, SZ["footer"], MUTED,
                  align="right")

    def save(self):
        self.c.showPage()
        self.c.save()


# ---------------------------------------------------------------- sections
def content_card(d, x, y, w, title, body, fill, stroke, accent, body_size=None,
                 body_lh=None, pad=16.0, label_size=None):
    """Card with accent-bar label + body copy. Returns height."""
    body_size = body_size or SZ["body"]
    body_lh = body_lh or SZ["body_lh"]
    label_size = label_size or SZ["card_title"]
    bw = w - 2 * pad
    body_h = d.paragraph_height(body, "Helvetica", body_size, body_lh, bw)
    h = pad + 13.0 + 10.0 + body_h + pad - 2.0
    d.rrect(x, y, w, h, fill=fill, stroke=stroke, r=9)
    d.label(title, x + pad, y + pad, accent, label_size)
    d.text(body, x + pad, y + pad + 13.0 + 10.0, body_size, BODY, leading=body_lh,
           maxw=bw)
    return h


def arrow_right(d, x1, x2, y, color, lw=1.3):
    d.line(x1, y, x2 - 5.2, y, color, lw)
    d.c.setFillColor(color)
    p = d.c.beginPath()
    p.moveTo(x2 - 5.6, H - (y - 3.1))
    p.lineTo(x2 - 0.2, H - y)
    p.lineTo(x2 - 5.6, H - (y + 3.1))
    p.close()
    d.c.drawPath(p, stroke=0, fill=1)


def page_one(d):
    d.new_page()
    d.hero()

    y = 220.0
    d.text("01  |  PROBLEM", ML, y, 9.6, CYAN, "Helvetica-Bold")
    y += 16.0
    d.text("Ventilation should respond to the room.", ML, y, 19.0, INK,
           "Helvetica-Bold")
    y += 19.0 * CAP + 19.0

    # --- gap / proposal cards -------------------------------------------
    gap_w = (CONTENT - 15.0) / 2
    items = [
        ("THE GAP",
         "Moisture, smoke-like events and motor drag can go unseen, leaving "
         "ventilation and maintenance to manual attention.",
         WHITE, BORDER, CYAN),
        ("THE PROPOSAL",
         "AiroRhythm adds ESP32 sensing and control to a compatible Atomberg "
         "exhaust fan, linking humidity automation, smoke alerts and "
         "motor-load monitoring to one app.",
         BLUE_CARD, BLUE_BORD, PURPLE),
    ]
    heights = []
    for i, (t, b, f, s, a) in enumerate(items):
        bw = gap_w - 32
        heights.append(16 + 13 + 10
                       + d.paragraph_height(b, "Helvetica", SZ["body"], SZ["body_lh"], bw)
                       + 14)
    ch = max(heights)
    for i, (t, b, f, s, a) in enumerate(items):
        x = ML + i * (gap_w + 15)
        d.rrect(x, y, gap_w, ch, fill=f, stroke=s, r=9)
        d.label(t, x + 16, y + 16, a)
        d.text(b, x + 16, y + 16 + 23, SZ["body"], BODY, leading=SZ["body_lh"],
               maxw=gap_w - 32)
    y += ch + 36

    # --- from signal to service ------------------------------------------
    d.text("FROM SIGNAL TO SERVICE", ML, y, SZ["kicker"] - 0.6, INK,
           "Helvetica-Bold")
    d.text("The real fan stays central", W - MR, y + 2.6, 8.6, MUTED, align="right")
    y += 26.0

    steps = [
        ("1", "SENSE", "Humidity / smoke / motor load", CYAN),
        ("2", "DECIDE", "ESP32 filters signals; applies local rules", PURPLE),
        ("3", "VENTILATE", "Safe commands reach the actual fan", CYAN),
        ("4", "INFORM", "App status, alerts and controls", PURPLE),
    ]
    sw = (CONTENT - 3 * 10.0) / 4
    sh = 0
    for num, name, body, col in steps:
        bh = d.paragraph_height(body, "Helvetica", SZ["small"], SZ["small_lh"], sw - 28)
        sh = max(sh, 14 + 16 + 9 + bh + 13)
    for i, (num, name, body, col) in enumerate(steps):
        x = ML + i * (sw + 10)
        d.rrect(x, y, sw, sh, fill=WHITE, stroke=BORDER, r=9)
        cy = y + 14 + 8
        d.c.setFillColor(col)
        d.c.circle(x + 14 + 8, H - cy, 8.0, stroke=0, fill=1)
        d.text(num, x + 22, cy - 4.4, 7.8, WHITE, "Helvetica-Bold", align="center")
        d.text(name, x + 38, cy - 5.9, 9.2, INK, "Helvetica-Bold")
        d.text(body, x + 14, y + 14 + 16 + 9, SZ["small"], BODY,
               leading=SZ["small_lh"], maxw=sw - 28)
        if i < 3:
            arrow_right(d, x + sw + 1.6, x + sw + 9.0, y + sh / 2, CYAN)
    y += sh + 24

    # --- local-first / human-in-control strip ----------------------------
    half = CONTENT / 2
    bw = half - 28 - 8
    left_b = d.paragraph_height("Humidity rules can run without cloud access.",
                                "Helvetica", SZ["body"], SZ["body_lh"], bw)
    right_b = d.paragraph_height("Keep the physical switch and fan protections.",
                                 "Helvetica", SZ["body"], SZ["body_lh"], bw)
    strip_h = 14 + 13 + 9 + max(left_b, right_b) + 13
    d.rrect(ML, y, CONTENT, strip_h, fill=WHITE, stroke=BORDER, r=9)
    d.line(ML + half, y + 12, ML + half, y + strip_h - 12, BORDER, 0.8)
    d.label("LOCAL-FIRST", ML + 15, y + 14, CYAN, 9.4)
    d.text("Humidity rules can run without cloud access.", ML + 15, y + 14 + 22,
           SZ["body"], BODY, leading=SZ["body_lh"], maxw=half - 30)
    d.label("HUMAN-IN-CONTROL", ML + half + 15, y + 14, PURPLE, 9.4)
    d.text("Keep the physical switch and fan protections.", ML + half + 15,
           y + 14 + 22, SZ["body"], BODY, leading=SZ["body_lh"], maxw=half - 30)
    y += strip_h + 22

    # --- prototype scope --------------------------------------------------
    scope = ("The Flutter prototype simulates readings and fan state. Its virtual "
             "fan is status-only; the real exhaust fan ventilates. Hardware "
             "integration is future work.")
    bw = CONTENT - 30
    bh = d.paragraph_height(scope, "Helvetica", SZ["body"], SZ["body_lh"], bw)
    h = 16 + 13 + 9 + bh + 15
    d.rrect(ML, y, CONTENT, h, fill=DARK_CARD, stroke=DARK_CARD, r=9)
    d.text("PROTOTYPE SCOPE", ML + 15, y + 17, 9.4, CYAN, "Helvetica-Bold")
    d.text(scope, ML + 15, y + 17 + 22, SZ["body"], DARK_BODY,
           leading=SZ["body_lh"], maxw=bw)
    y += h
    d.footer()
    return y


def page_two(d):
    d.new_page()
    d.page_head("SYSTEM DESIGN", "How the system works")

    y = 88.0
    d.text("Local intelligence connects sensors, app and fan", ML, y, 15.0, INK,
           "Helvetica-Bold")
    y += 15.0 * CAP + 23.0

    # --- signal flow ------------------------------------------------------
    dw = (CONTENT - 3 * 10.0) / 4
    cards = [
        ("ROOM SIGNALS", "Humidity / smoke / current + RPM", WHITE, BORDER, CYAN),
        ("ESP32", "Filter readings; run thresholds and hysteresis", PURP_CARD,
         PURP_BORD, PURPLE),
        ("ISOLATED DRIVE", "Model-specific ON/OFF; speed if supported", WHITE,
         BORDER, CYAN),
        ("REAL EXHAUST FAN", "The physical ventilation device", WHITE, BORDER,
         PURPLE),
    ]
    dh = 0.0
    for t, b, f, s, a in cards:
        bh = d.paragraph_height(b, "Helvetica", SZ["small"], SZ["small_lh"], dw - 28)
        dh = max(dh, 13 + 13 + 8 + bh + 14)
    for i, (t, b, f, s, a) in enumerate(cards):
        x = ML + i * (dw + 10)
        d.rrect(x, y, dw, dh, fill=f, stroke=s, r=9)
        d.label(t, x + 14, y + 13, a, 9.2)
        d.text(b, x + 14, y + 13 + 21, SZ["small"], BODY, leading=SZ["small_lh"],
               maxw=dw - 28)
        if i < 3:
            arrow_right(d, x + dw + 1.4, x + dw + 9.2, y + dh / 2, CYAN)
    # app node under ESP32
    esp_x = ML + dw + 10
    app_w, app_h = 178.0, 52.0
    app_x = esp_x + dw / 2 - app_w / 2
    ay = y + dh
    # double-headed vertical connector
    cx = esp_x + dw / 2
    d.line(cx, ay + 3.0, cx, ay + 26.0, PURPLE, 1.15)
    for yy, flip in ((ay + 2.6, 1), (ay + 26.4, -1)):
        d.c.setFillColor(PURPLE)
        p = d.c.beginPath()
        p.moveTo(cx - 3.6, H - (yy + flip * 3.4))
        p.lineTo(cx, H - yy)
        p.lineTo(cx + 3.6, H - (yy + flip * 3.4))
        p.close()
        d.c.drawPath(p, stroke=0, fill=1)
    ay += 28.0
    d.rrect(app_x, ay, app_w, app_h, fill=BLUE_CARD, stroke=BLUE_BORD, r=9)
    d.text("AIRO RHYTHM APP", app_x + app_w / 2, ay + 12, 9.2, INK,
           "Helvetica-Bold", align="center")
    d.text("Wi-Fi telemetry / remote commands", app_x + app_w / 2, ay + 27, 9.6,
           BODY, align="center")
    y = ay + app_h + 24

    # --- two app modes ----------------------------------------------------
    d.text("TWO APP MODES", ML, y, SZ["kicker"] - 0.6, INK, "Helvetica-Bold")
    y += 25.0
    gap_w = (CONTENT - 15.0) / 2
    modes = [
        ("DISPLAY  |  MONITOR",
         "Live humidity, smoke, load, fan status, last update and events; "
         "graphic mirrors reported state.", WHITE, BORDER, CYAN),
        ("REMOTE  |  CONTROL + AUTOMATE",
         "Manual ON/OFF, speed if supported, thresholds and schedules; confirm "
         "commands and override automation.", PURP_CARD, PURP_BORD, PURPLE),
    ]
    mh = 0.0
    for t, b, f, s, a in modes:
        bh = d.paragraph_height(b, "Helvetica", SZ["body"], SZ["body_lh"], gap_w - 32)
        mh = max(mh, 16 + 13 + 9 + bh + 14)
    for i, (t, b, f, s, a) in enumerate(modes):
        x = ML + i * (gap_w + 15)
        d.rrect(x, y, gap_w, mh, fill=f, stroke=s, r=9)
        d.label(t, x + 16, y + 16, a, 9.4)
        d.text(b, x + 16, y + 16 + 22, SZ["body"], BODY, leading=SZ["body_lh"],
               maxw=gap_w - 32)
    y += mh + 26

    # --- sensor-to-action table -------------------------------------------
    d.text("SENSOR-TO-ACTION GUIDE", ML, y, SZ["kicker"] - 0.6, INK,
           "Helvetica-Bold")
    y += 25.0
    cols = [116.0, 151.0, CONTENT - 116.0 - 151.0]
    xs = [ML, ML + 116.0, ML + 116.0 + 151.0]
    head_h = 30.0
    rows = [
        ("Humidity sensor", "Moisture crosses a set point.",
         "Start fan; a lower OFF threshold and minimum runtime prevent cycling."),
        ("Smoke / air-quality sensor", "Smoke-like reading.",
         "Alert locally and in app; configurable response, not a certified alarm."),
        ("Rotation-load proxy", "Motor current/RPM versus clean baseline.",
         "Current rise or RPM loss prompts inspection; indicator, not diagnosis."),
    ]
    row_h = []
    for a, b, c in rows:
        n = max(
            len(d.wrap(a, "Helvetica", SZ["small"], cols[0] - 20)),
            len(d.wrap(b, "Helvetica", SZ["small"], cols[1] - 20)),
            len(d.wrap(c, "Helvetica", SZ["small"], cols[2] - 20)),
        )
        row_h.append(n * SZ["small_lh"] + 17)
    total_h = head_h + sum(row_h)
    # body background
    d.rrect(ML, y, CONTENT, total_h, fill=WHITE, stroke=None, r=9)
    # alternating row fills
    ry = y + head_h
    for i, rh in enumerate(row_h):
        if i % 2 == 1:
            d.rect(ML + 0.5, ry, CONTENT - 1.0, rh, ALT_ROW)
        ry += rh
    # header (rounded top only)
    d.rrect(ML, y, CONTENT, 2 * 9, fill=TABLE_HEAD, stroke=None, r=9)
    d.rect(ML, y + 9, CONTENT, head_h - 9, TABLE_HEAD)
    for i, hr in enumerate(["SIGNAL", "WHAT IT MEANS", "SYSTEM RESPONSE"]):
        d.text(hr, xs[i] + 10, y + (head_h - CAP * 9.0) / 2 + 0.6, 9.0, WHITE,
               "Helvetica-Bold")
    # row rules + text
    ry = y + head_h
    for i, ((a, b, c), rh) in enumerate(zip(rows, row_h)):
        for j, txt in enumerate((a, b, c)):
            d.text(txt, xs[j] + 10, ry + 9.0, SZ["small"], BODY,
                   leading=SZ["small_lh"], maxw=cols[j] - 20)
        ry += rh
        d.hline(ML, W - MR, ry, BORDER, 0.5)
    for xsep in (xs[1], xs[2]):
        d.line(xsep, y + head_h, xsep, y + total_h, BORDER, 0.5)
    d.rrect(ML, y, CONTENT, total_h, fill=None, stroke=BORDER, r=9)
    y += total_h + 20

    # --- safety -----------------------------------------------------------
    safety = ("Use isolated, model-specific control; retain the wall switch and "
              "protections. Stale readings disable dependent rules and alert. "
              "Humidity runs locally; smoke sensing is not life-safety protection.")
    bw = CONTENT - 30
    bh = d.paragraph_height(safety, "Helvetica", SZ["body"], SZ["body_lh"], bw)
    h = 16 + 13 + 9 + bh + 14
    d.rrect(ML, y, CONTENT, h, fill=SAFE_CARD, stroke=SAFE_BORD, r=9)
    d.text("SAFETY AND RESILIENCE", ML + 15, y + 16, 9.4, PURPLE, "Helvetica-Bold")
    d.text(safety, ML + 15, y + 16 + 21, SZ["body"], BODY, leading=SZ["body_lh"],
           maxw=bw)
    y += h
    d.footer()
    return y


def page_three(d):
    d.new_page()
    d.page_head("FEASIBILITY, VALUE AND TEAM", "From concept to a measurable pilot")

    y = 86.0
    d.text("Build in stages; prove safety and value before scaling.", ML, y, 9.6,
           MUTED)
    y += 9.6 * CAP + 19.0

    # --- feasibility / viability -----------------------------------------
    gap_w = (CONTENT - 15.0) / 2
    items = [
        ("FEASIBILITY",
         "ESP32, humidity/smoke sensors and the Flutter app form a practical "
         "stack. Compare current and RPM to flag drag. Validate placement, "
         "calibration, isolated actuation and electrical safety.",
         WHITE, BORDER, CYAN),
        ("VIABILITY",
         "A retrofit or integrated model could automate without changing daily "
         "use. Local rules limit cloud dependence; the app supports setup and "
         "service prompts. Validate cost, installation, reliability, false "
         "alerts, energy use and demand before productization.",
         PURP_CARD, PURP_BORD, PURPLE),
    ]
    fh = 0.0
    for t, b, f, s, a in items:
        bh = d.paragraph_height(b, "Helvetica", SZ["body"], SZ["body_lh"], gap_w - 32)
        fh = max(fh, 16 + 13 + 9 + bh + 14)
    for i, (t, b, f, s, a) in enumerate(items):
        x = ML + i * (gap_w + 15)
        d.rrect(x, y, gap_w, fh, fill=f, stroke=s, r=9)
        d.label(t, x + 16, y + 16, a, 9.4)
        d.text(b, x + 16, y + 16 + 22, SZ["body"], BODY, leading=SZ["body_lh"],
               maxw=gap_w - 32)
    y += fh + 21

    # --- benefits ---------------------------------------------------------
    d.text("POTENTIAL BENEFITS  |  TO BE MEASURED", ML, y, SZ["kicker"] - 0.6, INK,
           "Helvetica-Bold")
    y += 22.0
    benefits = [
        ("COMFORT", "Humidity-led ventilation.", BLUE_CARD, BORDER, CYAN),
        ("AWARENESS", "Smoke alerts and live fan status.", WHITE, BORDER, PURPLE),
        ("CARE", "Early prompt for inspection or cleaning.", BLUE_CARD, BORDER, CYAN),
        ("EFFICIENCY", "Hysteresis limits cycling; verify energy impact.", WHITE,
         BORDER, PURPLE),
    ]
    bwid = (CONTENT - 15.0) / 2
    bh_card = 11 + 12 + 7 + SZ["tiny_lh"] + 11
    for i, (t, b, f, s, a) in enumerate(benefits):
        col, row = i % 2, i // 2
        x = ML + col * (bwid + 15)
        yy = y + row * (bh_card + 10)
        d.rrect(x, yy, bwid, bh_card, fill=f, stroke=s, r=8)
        d.label(t, x + 13, yy + 11, a, 9.4)
        d.text(b, x + 13, yy + 11 + 19, 9.6, BODY, leading=SZ["tiny_lh"],
               maxw=bwid - 26)
    y += 2 * bh_card + 9 + 21

    # --- prototype path ---------------------------------------------------
    d.text("PROTOTYPE PATH", ML, y, SZ["kicker"] - 0.6, INK, "Helvetica-Bold")
    y += 22.0
    pw = (CONTENT - 2 * 10.0) / 3
    path = [
        ("NOW  |  SOFTWARE",
         "Flutter simulates readings and fan state; no hardware yet.", WHITE,
         BORDER, CYAN),
        ("NEXT  |  BENCH",
         "Add ESP32 and calibrated sensors; test stale data, override and "
         "isolated control.", PURP_CARD, PURP_BORD, PURPLE),
        ("PILOT  |  VALIDATE",
         "Compare alerts, humidity response, drag flags and runtime against "
         "references.", WHITE, BORDER, CYAN),
    ]
    ph = 0.0
    for t, b, f, s, a in path:
        bh = d.paragraph_height(b, "Helvetica", SZ["small"], SZ["small_lh"], pw - 28)
        ph = max(ph, 14 + 13 + 9 + bh + 13)
    for i, (t, b, f, s, a) in enumerate(path):
        x = ML + i * (pw + 10)
        d.rrect(x, y, pw, ph, fill=f, stroke=s, r=9)
        d.label(t, x + 14, y + 14, a, 9.2)
        d.text(b, x + 14, y + 14 + 22, SZ["small"], BODY, leading=SZ["small_lh"],
               maxw=pw - 28)
        if i < 2:
            arrow_right(d, x + pw + 1.4, x + pw + 9.2, y + ph / 2, PURPLE)
    y += ph + 14

    # --- pilot scorecard ---------------------------------------------------
    score = ("Trigger accuracy / false alerts / response / drag agreement / "
             "command acknowledgement / runtime")
    note = "Energy savings remain unclaimed until measured."
    bw = CONTENT - 30
    sh = d.paragraph_height(score, "Helvetica", 9.6, SZ["small_lh"], bw)
    h = 13 + 14.5 + 7 + sh + 11
    d.rrect(ML, y, CONTENT, h, fill=BLUE_CARD, stroke=BLUE_BORD, r=9)
    d.text("PILOT SCORECARD", ML + 15, y + 13, 9.4, CYAN, "Helvetica-Bold")
    d.text(note, W - MR - 15, y + 14, 9.0, MUTED, "Helvetica-Oblique",
           align="right")
    d.text(score, ML + 15, y + 13 + 14.5 + 7, 9.6, BODY,
           leading=SZ["small_lh"], maxw=bw)
    y += h + 15

    # --- team --------------------------------------------------------------
    team = [("Gourvendra Kumar Jha", "TEAM LEAD  |  Mathematics and Computing", CYAN),
            ("Mayuri Kumari", "Computer Science and Engineering", PURPLE),
            ("Ashutosh Sharma", "Mathematics and Computing", PURPLE),
            ("Nitin Kumar", "Mathematics and Computing", PURPLE),
            ("Ravi Bhaskar Jha", "Computer Science and Engineering", PURPLE)]
    row_h = 31.0
    head_h = 42.0
    cols_x = [ML + 28, ML + 281]
    rows_per_col = 3
    th = head_h + rows_per_col * row_h + 7
    d.rrect(ML, y, CONTENT, th, fill=DARK_CARD, stroke=DARK_CARD, r=9)
    d.text("TEAM AIRO RHYTHM", ML + 15, y + 15, 10.0, CYAN, "Helvetica-Bold")
    d.text("SUPAUL COLLEGE OF ENGINEERING", W - MR - 15, y + 16, 8.8,
           HexColor("#D7DEEA"), "Helvetica-Bold", align="right")
    d.hline(ML + 15, W - MR - 15, y + 32.0, TEAM_RULE, 0.8)
    order = [0, 3, 1, 4, 2]  # row-major reading order (left, right, left, ...)
    for pos, idx in enumerate(order):
        name, role, col = team[idx]
        cx = cols_x[idx // rows_per_col]
        ry = y + head_h + (pos // 2) * row_h
        d.c.setFillColor(col)
        d.c.circle(cx - 10.5, H - (ry + 4.4), 2.6, stroke=0, fill=1)
        d.text(name, cx, ry, 9.6, WHITE, "Helvetica-Bold")
        d.text(role, cx, ry + 12.6, 8.8, TEAM_ROLE)
    y += th
    d.footer()
    return y


def main(out):
    d = Deck(out)
    b1 = page_one(d)
    b2 = page_two(d)
    b3 = page_three(d)
    d.save()
    print(f"page1 bottom={b1:.1f}  page2 bottom={b2:.1f}  page3 bottom={b3:.1f}")
    print("footer rule at", FOOT_RULE_Y)


if __name__ == "__main__":
    import sys
    main(sys.argv[1] if len(sys.argv) > 1 else "/home/user/AiroRhythm.pdf")
