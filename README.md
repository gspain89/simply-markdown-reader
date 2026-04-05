# Markdown Reader

A beautiful, native macOS Markdown viewer with warm, Claude-inspired typography and styling.

Built with Swift and WKWebView — no Electron, no bloat. Just a fast, lightweight `.app` that opens `.md` files the way they deserve to be read.

## Why

Every developer reads Markdown daily, yet most tools render it either too plainly or require a heavyweight framework. Markdown Reader gives you a polished reading experience in a native macOS app under 2 MB, with the warm color palette and thoughtful typography inspired by Claude's artifact rendering.

## Features

### Reading Experience
- **Claude-inspired design** — Warm sand-beige light theme and matching dark theme with carefully tuned typography
- **Serif body text** — Uses macOS's New York typeface for comfortable long-form reading (Korean: AppleMyungjo)
- **Sans-serif headings** — Clean heading hierarchy with system font (Korean: Apple SD Gothic Neo)
- **Light / Dark / Auto** — Follows your system appearance or choose manually

### Navigation
- **Table of Contents sidebar** — Auto-generated from headings, highlights your current position as you scroll, click to jump (Cmd+Shift+T)
- **In-app search** — Custom search bar with match highlighting, previous/next navigation, and match count (Cmd+F)
- **Breadcrumb path bar** — See where you are, click directories to browse sibling files
- **Folder tree** — Recursive directory browsing in the sidebar, expanding up to 4 levels deep
- **Bookmarks** — Star icon in toolbar (Cmd+D) to bookmark files, with a dedicated list in the sidebar showing file paths
- **Back / Forward** — Navigate between linked documents (Cmd+[ / Cmd+])
- **Reading progress bar** — Thin accent bar at the top shows scroll progress

### Content Support
- **GitHub Flavored Markdown (GFM)** — Tables, task lists, strikethrough, autolinks
- **Syntax-highlighted code blocks** — 180+ languages via highlight.js, with one-click copy button
- **Mermaid diagrams** — Flowcharts, sequence diagrams, and more rendered inline
- **KaTeX math** — LaTeX math expressions: `$E = mc^2$` inline or `$$..$$` display
- **Local images** — Relative image paths resolved correctly, click to zoom
- **YAML frontmatter** — Parsed and displayed as metadata badges (title, date, author, tags, status)

### Productivity
- **Auto-reload** — File changes are detected and the view refreshes automatically (great for editing in another tool)
- **Export & Share** — Export popover with PDF export, Copy as HTML, and macOS Share sheet
- **Source view toggle** — Switch between rendered and raw Markdown (Cmd+U)
- **Scroll position memory** — Reopen a file and continue where you left off
- **Word count & reading time** — Shown in the status bar
- **Recent files** — Quick access from File menu

### Settings (In-App Modal)
- **Visual theme picker** — Light/Dark/Auto cards with color swatches
- **Font family** — Default Serif, Sans, System, or Monospace with live English/Korean preview
- **Font size** — 12 px to 28 px (toolbar A-/A+ buttons or Cmd+/-)
- **Content width** — Narrow (600 px), Standard (720 px), Wide (900 px), or Full with miniature page icons
- **Toggle features** — iOS-style switches for TOC, breadcrumb, word count, progress bar, Mermaid, KaTeX, syntax highlighting

### macOS Integration
- **Finder double-click** — Set as default app for `.md` files
- **Drag and drop** — Drop `.md` files from Finder onto the window to open
- **Native tabs** — Multiple documents in tabbed windows
- **Standard shortcuts** — Cmd+O, Cmd+P, Cmd+W, Cmd+F, Cmd+D, and more
- **Represented filename** — Cmd+click the title bar to see the file path in Finder
- **Ad-hoc signed** — No Gatekeeper warnings on first launch

## Installation

### From DMG (recommended)

1. Download `MarkdownReader-1.0.0.dmg` from the [Releases](../../releases) page
2. Open the DMG and drag **Markdown Reader** to the Applications folder
3. Right-click any `.md` file → Get Info → Open with → **Markdown Reader** → **Change All**

### Build from source

Requires macOS 13+ and Xcode Command Line Tools.

```bash
git clone https://github.com/gspain89/markdown-reader.git
cd markdown-reader

# Download vendor libraries (marked.js, highlight.js, mermaid.js, KaTeX)
bash scripts/setup.sh

# Build the .app bundle
bash scripts/build.sh

# The app is at dist/Markdown Reader.app
# Copy to Applications:
cp -r "dist/Markdown Reader.app" /Applications/
```

To create a DMG for sharing:

```bash
bash scripts/create-dmg.sh
# Output: dist/MarkdownReader-1.0.0.dmg
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│  macOS Native Shell (Swift / AppKit)            │
│  ┌───────────────────────────────────────────┐  │
│  │  NSWindow (tabs) + DropView (drag&drop)   │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │  WKWebView                          │  │  │
│  │  │  ┌──────────┐ ┌──────────────────┐  │  │  │
│  │  │  │ Sidebar  │ │ Rendered         │  │  │  │
│  │  │  │ ─ TOC    │ │ Markdown         │  │  │  │
│  │  │  │ ─ ★ Fav  │ │                  │  │  │  │
│  │  │  │ ─ Files  │ │ Claude-style CSS │  │  │  │
│  │  │  │          │ │ + highlight.js   │  │  │  │
│  │  │  │ marked.js│ │ + mermaid        │  │  │  │
│  │  │  │ KaTeX    │ │ + KaTeX          │  │  │  │
│  │  │  └──────────┘ └──────────────────┘  │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
│  Settings (in-app modal) │ FileWatcher (GCD)    │
└─────────────────────────────────────────────────┘
```

- **Swift layer** — Window management, menus, file I/O, bookmarks, settings persistence (`UserDefaults`), file change detection (`DispatchSource`), folder tree scanning
- **Web layer** — All rendering via `WKWebView` with custom HTML/CSS/JS. Communication between layers via `WKScriptMessageHandler`
- **Zero pip/npm dependencies** — vendor JS libraries are downloaded once via `setup.sh` and bundled into the `.app`

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+O | Open file |
| Cmd+F | Find in document |
| Cmd+D | Toggle bookmark |
| Cmd+Shift+T | Toggle table of contents |
| Cmd+U | Toggle source view |
| Cmd+Shift+E | Export as PDF |
| Cmd+P | Print |
| Cmd++ | Zoom in |
| Cmd+- | Zoom out |
| Cmd+0 | Reset zoom |
| Cmd+\\ | Cycle content width |
| Cmd+[ | Navigate back |
| Cmd+] | Navigate forward |
| Cmd+, | Settings |
| Cmd+W | Close window/tab |

## Content Width

Body text is capped at a readable width (default 720 px) and centered, following typography best practices (optimal line length: 50–75 characters). Code blocks and tables can extend slightly wider. When the window is wider, margins grow — content doesn't stretch infinitely.

Configurable via Settings or Cmd+\\ to cycle through Narrow → Standard → Wide → Full.

## License

[MIT](LICENSE)
