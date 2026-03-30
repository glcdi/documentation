# GLCDI Presentations

## Data Sharing Steps

A step-by-step walkthrough of publishing, discovering, negotiating, and transferring data
in the GLCDI dataspace.

| Format | File | How to view |
|--------|------|-------------|
| Markdown | [data-sharing-steps.md](data-sharing-steps.md) | Any text editor or markdown renderer |
| Reveal.js | [data-sharing-steps.html](data-sharing-steps.html) | Open in a browser (loads Reveal.js from CDN) |

### Viewing the Reveal.js presentation

Just open `data-sharing-steps.html` in any modern browser. It loads Reveal.js 5.1 from
a CDN — no local install needed.

```bash
# From this directory
xdg-open data-sharing-steps.html     # Linux
open data-sharing-steps.html         # macOS
```

### Navigation

- Arrow keys or Space to advance
- `Esc` for slide overview
- `S` for speaker notes (none defined yet)
- `F` for fullscreen
- Slide numbers shown bottom-right

### Editing

The HTML file is self-contained. Edit it directly — all styles are inline, no build step.
The markdown file is the canonical reference; keep both in sync if you make changes.

### Exporting to PDF

Open the presentation in Chrome/Chromium with `?print-pdf` appended to the URL:

```
file:///path/to/data-sharing-steps.html?print-pdf
```

Then use `Ctrl+P` (Print) and select "Save as PDF". Set margins to "None" and enable
"Background graphics" for the best result.
