# Recto

A paper reader with a facing notebook page, for iPhone (including iPhone Duo) and iPad.
Working name; see the design brief for the open naming question.

- Design brief: https://claude.ai/artifact/95agJiaLTgiouMH6eGhjzk
- Clickable mock: https://claude.ai/artifact/Hk9HNmdDghG5Y35WiBVY9u

## What is here

| Folder | What it is |
| --- | --- |
| `RectoCore/` | The engine, in plain Swift with no screen code: reading text off the page, Columns view, the reading line, the margin notes, the pen rules, undo, the notebook, saving. Fully tested. |
| `App/Recto/` | A first iPhone and iPad app around the engine (SwiftUI, with UIKit for the paper and pen). |
| `project.yml` | Describes the Xcode project. Generate it with XcodeGen. |
| `tools/make_test_paper.py` | Makes the realistic two-column test paper used by the tests and bundled as the sample. |

## Run it (needs a Mac)

1. Install Xcode 27.1 or later (it has the iPhone Duo simulator) and XcodeGen: `brew install xcodegen`.
2. In this folder run `xcodegen`, then open `Recto.xcodeproj`.
3. Pick an iPhone Duo, iPhone or iPad simulator and press Run.
4. Engine tests: open `RectoCore/Package.swift` in Xcode and press Cmd-U, or run `swift test` in `RectoCore/`.

The app opens on a library with a sample paper. Inside a paper:

- A finger scrolls. **Write** turns on writing for the paper: one finger inks, two fingers scroll. A Pencil always inks.
- **Facing** (two pages) or **Notes / Paper** (one page) picks what the other page shows.
- **More** has Swap sides, the closed-phone margin band, a quick Quote, and **Pretend fold**, which fakes the Duo's fold so every layout can be tried in any simulator.

## Engine rules (all covered by tests)

- Layout comes only from the window size and the fold, never from the pose or hinge angle.
  Two pages side by side when the fold runs down the middle or the window is at least 860 points wide;
  paper above notes when the fold runs across (laptop pose, held tall); one page otherwise.
- Columns view below 600 points of paper width, Page view above, unless the reader picked one (kept per paper).
- The reading line is a sentence and line plus how far into the line the top of the pane sits, with a plain
  page place as the fallback (scanned pages, or a PDF that was replaced). It is taken only when the reader scrolls, so folds, resizes and Columns/Page switches never move it.
- Margin ink is stored against the line it sits beside, measured out from the page edge, up to 520 points.
  Each paper keeps a left and a right margin. Swap sides changes which one is in use; notes stay where they were written,
  and ink in the hidden margin shows as an "ink" tab. Ink past the closed-phone band shows a "more" tab. Close tabs merge.
- One pen movement from the paper over the crease onto the facing page is cut at the page edge into two
  parts that share a point, so they join with no gap and undo as one.
- The crease takes ink. Finger strokes starting within 20 points of the screen's real edges are ignored in Write mode
  (the inner edge of a Split View pane is not a screen edge).
- Undo undoes the last action (one eraser pass that took off strokes and a highlight is one undo). Paper and notebook keep separate histories.
- The highlighter snaps to the words it crosses, so it makes the same highlight as the menu.
- Notebook pages are 400 by 560 points everywhere; a narrower pane shows them smaller, never reflowed.
  Quote cards go in the next free slot and never move what is already there.
- Everything for a paper is saved as JSON next to it; the PDF is not touched until export.

## Not done yet

- The Duo's fold is not read from the system yet (`App/Recto/Fold.swift`). Use **Pretend fold** until it is wired up on a Mac.
- The app shell has not been compiled yet: this build was written on a machine without Xcode. Expect a round of small fixes on first build.
- Writing in the whole-margin view (laptop pose, closed Notes), ink on notebook pages, text selection, Same paper,
  Figures and tables, Another paper, export, iPad portrait drawer: per the 12-week plan.
