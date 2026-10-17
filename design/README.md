# AiroRhythm one-pager — large-type edition

`AiroRhythm.pdf` is the AtomQuest 2026 submission deck, rebuilt with larger,
more readable type. Layout, colour system and copy are unchanged.

| Element | Original | Rebuilt |
|---|---|---|
| Body copy | 8.0 – 8.4 pt | **10.8 pt** |
| Card / column body | 7.2 – 7.3 pt | **9.9 pt** |
| Card headings | 7.4 – 8.3 pt | **9.2 – 9.4 pt** |
| Section titles | 9.2 pt | **12.4 pt** |
| Page titles | 16.0 – 17.5 pt | **19 – 21 pt** |
| Hero title | 26 pt | **30 pt** |
| Footer | 7.2 pt | **8.8 pt** |

Median text size across the deck goes from **7.4 pt to 9.9 pt** (+34%).
All three pages still fit on A4 with nothing clipped or overlapping.

## Regenerating

```bash
pip install reportlab
python design/build_deck.py design/AiroRhythm.pdf
```

The script is a single vector-drawing source of truth — cards, arrows,
tables and the team panel are drawn with ReportLab primitives, so any
further type or wording change is a one-line edit. Logos are extracted
from the original artwork in `assets/`.
