"""Makes a realistic two-column test paper (title, abstract across both columns, a full-width
figure in the middle of page 2, captions, a footnote) and writes its text layer as JSON in the
shape RectoCore's DocumentText takes. Run: python3 make_test_paper.py out.pdf out.json"""
import json, random, sys
import pdfplumber
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer,
                                FrameBreak, NextPageTemplate)
from reportlab.graphics.shapes import Drawing, Rect, Line
from reportlab.platypus.flowables import Flowable

random.seed(7)
W, H = letter
M, G = 54, 18
colw = (W - 2 * M - G) / 2

words = ("the model reads each page and keeps the notes beside the line where they were written so "
         "a reader can fold the phone and find the same sentence results show that readers who keep "
         "margin notes recall more of the method section than readers who take notes elsewhere").split()

def para(n):
    s = " ".join(random.choice(words) for _ in range(n))
    s = s.capitalize() + ". " + " ".join(random.choice(words) for _ in range(n // 2)).capitalize()
    return s + " (see Fig. 2 and Eq. 3)."

body = ParagraphStyle("b", fontName="Times-Roman", fontSize=9.5, leading=11.5)
head = ParagraphStyle("h", fontName="Times-Bold", fontSize=11, leading=14, spaceBefore=6)
title = ParagraphStyle("t", fontName="Times-Bold", fontSize=17, leading=21, alignment=1)
auth = ParagraphStyle("a", fontName="Times-Roman", fontSize=11, leading=14, alignment=1)
cap = ParagraphStyle("c", fontName="Times-Italic", fontSize=8.5, leading=10)

class Figure(Flowable):
    def __init__(self, w, h): super().__init__(); self.width, self.height = w, h
    def draw(self):
        c = self.canv
        c.rect(0, 0, self.width, self.height)
        for i in range(12):
            c.line(10 + i * 40, 10, 30 + i * 40, 10 + random.random() * (self.height - 20))

doc = BaseDocTemplate(sys.argv[1], pagesize=letter)
top = Frame(M, H - M - 190, W - 2 * M, 190, id="top")
l1 = Frame(M, M, colw, H - 2 * M - 190, id="l1")
r1 = Frame(M + colw + G, M, colw, H - 2 * M - 190, id="r1")
l = Frame(M, M, colw, H - 2 * M, id="l")
r = Frame(M + colw + G, M, colw, H - 2 * M, id="r")
# Page 2: columns, then a full-width figure band in the middle, then columns again.
fig_y, fig_h = 330, 170
l2a = Frame(M, fig_y + fig_h, colw, H - M - fig_y - fig_h, id="l2a")
r2a = Frame(M + colw + G, fig_y + fig_h, colw, H - M - fig_y - fig_h, id="r2a")
figf = Frame(M, fig_y, W - 2 * M, fig_h, id="fig")
l2b = Frame(M, M, colw, fig_y - M, id="l2b")
r2b = Frame(M + colw + G, M, colw, fig_y - M, id="r2b")
doc.addPageTemplates([
    PageTemplate("first", [top, l1, r1]),
    PageTemplate("mid", [l2a, r2a, figf, l2b, r2b]),
    PageTemplate("rest", [l, r]),
])
story = [Paragraph("Notes Beside the Line: A Study of Facing Pages", title),
         Paragraph("Posi Example and A. N. Other", auth), Spacer(1, 8),
         Paragraph("<b>Abstract.</b> " + para(60), body), NextPageTemplate("mid"), FrameBreak()]
for i in range(1, 4):
    story += [Paragraph(f"{i} Section {i}", head)] + [Paragraph(para(45), body) for _ in range(3)]
story += [FrameBreak()]  # page 2, upper left column
story += [Paragraph(para(28), body), Paragraph(para(28), body), FrameBreak(),
          Paragraph(para(28), body), Paragraph(para(28), body), FrameBreak(),
          Figure(W - 2 * M, fig_h - 28),
          Paragraph("Figure 2: Recall by note place. Readers who wrote in the margin did best.", cap),
          FrameBreak(), NextPageTemplate("rest")]
for _ in range(4): story.append(Paragraph(para(28), body))
for _ in range(16): story.append(Paragraph(para(40), body))
doc.build(story)

# Text layer: words grouped into lines the way a PDF text layer gives them.
pages, sizes = [], []
with pdfplumber.open(sys.argv[1]) as pdf:
    for page in pdf.pages:
        sizes.append([float(page.width), float(page.height)])
        ws = page.extract_words(keep_blank_chars=False, use_text_flow=True)
        lines = []
        for w in ws:
            rect = [float(w["x0"]), float(w["top"]), float(w["x1"] - w["x0"]), float(w["bottom"] - w["top"])]
            if lines and abs(lines[-1][-1]["r"][1] - rect[1]) < 2 and 0 <= rect[0] - (lines[-1][-1]["r"][0] + lines[-1][-1]["r"][2]) < 12:
                lines[-1].append({"t": w["text"], "r": rect})
            else:
                lines.append([{"t": w["text"], "r": rect}])
        pages.append(lines)
json.dump({"sizes": sizes, "pages": pages}, open(sys.argv[2], "w"))
print(len(pages), "pages", sum(len(p) for p in pages), "lines")
