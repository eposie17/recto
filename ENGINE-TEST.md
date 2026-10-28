# Week 1 engine test: results (26 October 2026)

Goal: prove the reading and margin engine before building screens on it.

**Result: 40 of 40 checks pass** (38 on 26 October, plus 2 added on 28 October) (`swift test` in `RectoCore/`, Swift 6.1 on Linux).

| Area | What was checked | Result |
| --- | --- | --- |
| Reading line | Line stays exactly at the top through closed, open, laptop, Split View, iPad landscape and portrait | Pass |
| Reading line | 300 random folds, resizes, band toggles, side swaps and Columns/Page switches | Pass |
| Columns view | Finds the column gap; title and abstract kept whole; every line shown once | Pass |
| Columns view | A wide figure between column text stays whole in one crop | Pass after a fix |
| Margin | One stroke from paper over the crease to the notes joins with no gap | Pass |
| Margin | Margin notes stay beside their line after a fold | Pass |
| Margin | Swap sides keeps notes in their margin and shows ink tabs; swapping back hides them | Pass |
| Margin | Closed band shows "more" for ink past it; nearby tabs merge | Pass |
| Pen rules | Pencil always inks; finger scrolls unless Write; grip edges ignored; crease inks | Pass |
| Undo | A fold-crossing stroke undoes as one; one eraser pass is one undo; separate paper and notebook histories | Pass after a fix |
| Highlighter | Snaps to the words crossed; misses empty space | Pass |
| Notebook | Quote cards avoid ink and earlier cards, start a new page when full, never move | Pass |
| Reading line | Scanned paper with no text keeps its place by page; a replaced PDF falls back to the page place | Pass (added 28 Oct) |
| Saving | Everything round-trips; a file from a newer app version is refused | Pass |

## What the tests caught and changed

1. **On a two-column page, a scroll distance cannot say which column you were in.** Re-reading the position after
   every layout change made the line jump between columns. The line is now taken only when the reader scrolls.
2. **Wide figures were cut into two halves** when their caption sat in one column. A tall gap with no text in
   either column now gets its own full-width crop.
3. **The short last line of an abstract** was treated as column text and split the page oddly. It now stays with its paragraph.
4. **The eraser missed long straight strokes**, because it only checked the stroke's points, not the line between them.
5. Columns view reads about **2.4 times larger** than the whole printed page on the closed phone (the brief's 1.8 compares
   against the page cropped to its text).

## Limits of this test

- Real arXiv papers could not be downloaded here, so the "real paper" is one made with a real PDF tool
  (`tools/make_test_paper.py`) and read back with a real text extractor. PDFKit's text order on real papers still needs a check on a Mac.
- The app shell around the engine is written but not yet compiled (no Xcode here).
- The Duo fold API is not wired yet; nothing here needs a real Duo.
