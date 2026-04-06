# Simply Markdown Reader

A native macOS app for reading `.md` files. No Electron, no npm, no bloat — just Swift + WKWebView in under 2 MB.

Warm, Claude-inspired light/dark themes with serif body text and clean heading typography. Opens instantly, renders everything from GFM tables to Mermaid diagrams.

![Demo](https://github.com/gspain89/simply-markdown-reader/releases/download/v1.0.0/simply-markdown-reader-demo.gif)

## Installation

### Download (recommended)

1. Grab `MarkdownReader-1.0.0.dmg` from the [Releases](../../releases) page
2. Open the DMG and drag **Markdown Reader** to Applications
3. To set as default: right-click any `.md` file → Get Info → Open with → **Markdown Reader** → **Change All**

### Build from source

Requires macOS 13+ and Xcode Command Line Tools.

```bash
git clone https://github.com/gspain89/simply-markdown-reader.git
cd simply-markdown-reader

bash scripts/setup.sh    # download vendor JS (marked, highlight.js, mermaid, KaTeX)
bash scripts/build.sh    # build .app bundle → dist/Markdown Reader.app

cp -r "dist/Markdown Reader.app" /Applications/
```

## Features

### Rendering
- GitHub Flavored Markdown — tables, task lists, strikethrough, autolinks
- Syntax-highlighted code blocks (180+ languages, one-click copy)
- Mermaid diagrams rendered inline
- KaTeX math (`$inline$` and `$$display$$`)
- YAML frontmatter displayed as metadata badges
- Local images with click-to-zoom

### Navigation
- Table of Contents sidebar with scroll-position tracking
- In-app search with match highlighting and count (Cmd+F)
- Breadcrumb path bar — click directories to browse siblings
- Folder tree sidebar (recursive, up to 4 levels)
- Bookmarks with star icon in toolbar (Cmd+D)
- Back / Forward between linked documents

### Reading
- Light / Dark / Auto theme
- Serif body (New York), sans-serif headings, monospace code
- Font size control in toolbar (12–28 px)
- Content width: Narrow / Standard / Wide / Full
- Reading progress bar
- Word count and estimated reading time
- Scroll position memory across sessions

### PDF Export
- Proper A4 pagination — text never cuts at page boundaries
- 40 pt margins for print-safe output
- Always exports in light theme regardless of current mode
- Progress overlay during export

### macOS Integration
- Finder double-click, drag and drop
- Native tabbed windows
- Auto-reload on file changes
- Standard shortcuts (Cmd+O, Cmd+F, Cmd+P, Cmd+W, etc.)
- Share sheet

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+O | Open file |
| Cmd+F | Find in document |
| Cmd+D | Toggle bookmark |
| Cmd+Shift+T | Toggle TOC sidebar |
| Cmd+U | Toggle source view |
| Cmd+Shift+E | Export as PDF |
| Cmd+P | Print |
| Cmd+/Cmd- | Zoom in/out |
| Cmd+0 | Reset zoom |
| Cmd+\\ | Cycle content width |
| Cmd+[/Cmd+] | Back/Forward |
| Cmd+, | Settings |

## Architecture

```
macOS Native Shell (Swift / AppKit)
├── NSWindow (tabs) + DropView (drag & drop)
├── WKWebView
│   ├── Sidebar: TOC, Bookmarks, Folder Tree
│   └── Content: marked.js + highlight.js + mermaid + KaTeX
├── Settings (in-app modal, UserDefaults)
└── FileWatcher (DispatchSource)
```

- **Swift layer** — window management, menus, file I/O, bookmarks, PDF export, file change detection
- **Web layer** — all rendering via WKWebView with custom HTML/CSS/JS, communicating through `WKScriptMessageHandler`
- **Zero runtime dependencies** — vendor JS libraries are bundled into the `.app`

## License

[MIT](LICENSE)
