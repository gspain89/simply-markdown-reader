/* ============================================================
   Markdown Reader — Application JavaScript
   Handles rendering, TOC, navigation, and Swift bridge
   ============================================================ */

// --- Application State ---
const state = {
    filePath: '',
    baseDir: '',
    rawMarkdown: '',
    isSourceView: false,
    siblingFiles: [],
    siblingDir: ''
};

// --- Font presets ---
const fontPresets = {
    serif:  "'New York', 'Iowan Old Style', Georgia, 'AppleMyungjo', 'Noto Serif KR', serif",
    sans:   "-apple-system, BlinkMacSystemFont, 'Apple SD Gothic Neo', 'Pretendard', sans-serif",
    system: "-apple-system, BlinkMacSystemFont, 'Apple SD Gothic Neo', sans-serif",
    mono:   "'SF Mono', Menlo, Consolas, 'JetBrains Mono', monospace"
};

// --- Width presets (px or 'none') ---
const widthPresets = { narrow: '600px', standard: '720px', wide: '900px', full: 'none' };

// --- Marked.js configuration ---
function initMarked() {
    if (typeof marked === 'undefined') return;

    const renderer = {
        heading({ tokens, depth }) {
            const text = this.parser.parseInline(tokens);
            const plain = text.replace(/<[^>]*>/g, '');
            const id = plain.toLowerCase()
                .replace(/[^\w\u3131-\uD79D]+/g, '-')
                .replace(/(^-|-$)/g, '');
            return '<h' + depth + ' id="' + id + '">'
                + '<a class="heading-anchor" href="#' + id + '">\u00B6</a>'
                + text + '</h' + depth + '>\n';
        },

        code({ text, lang }) {
            let highlighted = escapeHtml(text);
            const langClass = lang || '';
            if (lang && typeof hljs !== 'undefined') {
                try {
                    const result = hljs.getLanguage(lang)
                        ? hljs.highlight(text, { language: lang, ignoreIllegals: true })
                        : hljs.highlightAuto(text);
                    highlighted = result.value;
                } catch (e) { /* fallback to escaped */ }
            }
            return '<div class="code-block">'
                + '<div class="code-header">'
                + '<span class="code-lang">' + escapeHtml(langClass) + '</span>'
                + '<button class="code-copy-btn" onclick="copyCode(this)">Copy</button>'
                + '</div>'
                + '<pre><code class="hljs language-' + escapeHtml(langClass) + '">'
                + highlighted + '</code></pre></div>\n';
        },

        image({ href, title, text }) {
            let src = href || '';
            if (src && !/^(https?:\/\/|file:\/\/|data:)/.test(src)) {
                src = 'file://' + state.baseDir + '/' + src;
            }
            const t = title ? ' title="' + escapeHtml(title) + '"' : '';
            return '<img src="' + src + '" alt="' + escapeHtml(text || '') + '"'
                + t + ' class="zoomable" onclick="zoomImage(this)">';
        },

        listitem({ text, task, checked }) {
            if (task) {
                const c = checked ? ' checked' : '';
                return '<li class="task-item"><input type="checkbox"' + c + ' disabled> ' + text + '</li>\n';
            }
            return '<li>' + text + '</li>\n';
        }
    };

    marked.use({
        renderer: renderer,
        gfm: true,
        breaks: false
    });
}

// --- Initialize on load ---
initMarked();

// ============================================================
// Core rendering
// ============================================================

function render(markdown, filePath, baseDir) {
    state.rawMarkdown = markdown;
    state.filePath = filePath;
    state.baseDir = baseDir;
    state.isSourceView = false;

    // Parse frontmatter before stripping
    var meta = parseFrontmatter(markdown);
    var fmHtml = renderFrontmatter(meta);

    // Strip YAML frontmatter
    const content = markdown.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, '');

    const html = marked.parse(content);
    document.getElementById('content').innerHTML = fmHtml + html;

    generateTOC();
    updateBreadcrumb(filePath);
    updateWordCount(content);
    processMermaid();
    processKatex();
    setupScrollTracking();
}

// Called on file-change auto-reload (preserves scroll position)
function reloadContent(markdown) {
    state.rawMarkdown = markdown;
    if (state.isSourceView) return;

    const scrollY = window.scrollY;
    var meta = parseFrontmatter(markdown);
    var fmHtml = renderFrontmatter(meta);
    const content = markdown.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, '');
    document.getElementById('content').innerHTML = fmHtml + marked.parse(content);

    generateTOC();
    updateWordCount(content);
    processMermaid();
    processKatex();

    window.scrollTo(0, scrollY);
}

// ============================================================
// Table of Contents
// ============================================================

function generateTOC() {
    const headings = document.querySelectorAll('#content h1, #content h2, #content h3, #content h4, #content h5, #content h6');
    const tocList = document.getElementById('toc-list');
    tocList.innerHTML = '';

    headings.forEach(function(h) {
        const level = parseInt(h.tagName.charAt(1));
        const a = document.createElement('a');
        a.className = 'toc-h' + level;
        a.textContent = h.textContent.replace('\u00B6', '').trim();
        a.href = '#' + h.id;
        a.onclick = function(e) {
            e.preventDefault();
            h.scrollIntoView({ behavior: 'smooth', block: 'start' });
        };
        tocList.appendChild(a);
    });
}

function updateActiveTOC() {
    const headings = document.querySelectorAll('#content h1, #content h2, #content h3, #content h4, #content h5, #content h6');
    const links = document.querySelectorAll('#toc-list a');
    if (links.length === 0) return;

    let current = 0;
    const offset = 80;
    headings.forEach(function(h, i) {
        if (h.getBoundingClientRect().top <= offset) current = i;
    });

    links.forEach(function(link, i) {
        link.classList.toggle('active', i === current);
    });

    // Scroll active item into view in sidebar
    const activeLink = links[current];
    if (activeLink) {
        const sidebar = document.getElementById('toc-sidebar');
        const linkRect = activeLink.getBoundingClientRect();
        const sidebarRect = sidebar.getBoundingClientRect();
        if (linkRect.top < sidebarRect.top || linkRect.bottom > sidebarRect.bottom) {
            activeLink.scrollIntoView({ block: 'center', behavior: 'smooth' });
        }
    }
}

// ============================================================
// Sibling files
// ============================================================

function setSiblingFiles(files, dir) {
    state.siblingFiles = files;
    state.siblingDir = dir;

    const section = document.getElementById('file-list-section');
    const list = document.getElementById('file-list');
    list.innerHTML = '';

    if (files.length === 0) { section.style.display = 'none'; return; }
    section.style.display = '';

    files.forEach(function(f) {
        const a = document.createElement('a');
        a.textContent = f;
        const fullPath = dir + '/' + f;
        if (state.filePath === fullPath) a.className = 'current-file';
        a.onclick = function(e) {
            e.preventDefault();
            sendToSwift('openFile', { path: fullPath });
        };
        list.appendChild(a);
    });
}

// ============================================================
// Breadcrumb
// ============================================================

function updateBreadcrumb(filePath) {
    const bc = document.getElementById('breadcrumb');
    if (!filePath) { bc.innerHTML = ''; return; }

    const parts = filePath.split('/').filter(Boolean);
    const fileName = parts.pop();

    // Show last 3 directory components
    const dirs = parts.slice(-3);
    let html = '';

    if (parts.length > 3) {
        html += '<span class="breadcrumb-item">\u2026</span><span class="separator">/</span>';
    }

    dirs.forEach(function(dir, i) {
        const fullDir = '/' + parts.slice(0, parts.length - dirs.length + i + 1).join('/');
        html += '<a class="breadcrumb-item" onclick="sendToSwift(\'browseDirectory\',{path:\'' + escapeAttr(fullDir) + '\'})">'
            + escapeHtml(dir) + '</a><span class="separator">/</span>';
    });

    html += '<span class="breadcrumb-item current">' + escapeHtml(fileName) + '</span>';
    bc.innerHTML = html;
}

// ============================================================
// Word count & reading time
// ============================================================

function updateWordCount(text) {
    const clean = text.replace(/```[\s\S]*?```/g, '').replace(/[#*_\[\]()>`~|\\-]/g, '');
    // Count Korean characters as "words" too
    const koreanChars = (clean.match(/[\u3131-\uD79D]/g) || []).length;
    const latinWords = clean.trim().split(/\s+/).filter(function(w) { return w.length > 0; }).length;
    const totalWords = latinWords + Math.ceil(koreanChars / 3);
    const minutes = Math.max(1, Math.ceil(totalWords / 200));

    const el = document.getElementById('word-count');
    if (el) el.textContent = totalWords.toLocaleString() + ' words \u00B7 ' + minutes + ' min read';
}

// ============================================================
// Scroll tracking & progress bar
// ============================================================

let scrollDebounceTimer = null;

function setupScrollTracking() {
    window.removeEventListener('scroll', onScroll);
    window.addEventListener('scroll', onScroll, { passive: true });
}

function onScroll() {
    // Progress bar
    const docHeight = document.documentElement.scrollHeight - window.innerHeight;
    const pct = docHeight > 0 ? (window.scrollY / docHeight) * 100 : 0;
    const bar = document.getElementById('progress-bar');
    if (bar) bar.style.width = Math.min(pct, 100) + '%';

    // Active TOC
    updateActiveTOC();

    // Save scroll position (debounced)
    clearTimeout(scrollDebounceTimer);
    scrollDebounceTimer = setTimeout(function() {
        if (state.filePath) {
            const pos = document.documentElement.scrollHeight > 0
                ? window.scrollY / document.documentElement.scrollHeight : 0;
            sendToSwift('saveScrollPosition', { position: pos });
        }
    }, 500);
}

function setScrollPosition(pos) {
    const target = pos * document.documentElement.scrollHeight;
    window.scrollTo(0, target);
}

// ============================================================
// Source view toggle
// ============================================================

function toggleSource() {
    state.isSourceView = !state.isSourceView;
    const contentEl = document.getElementById('content');

    if (state.isSourceView) {
        contentEl.innerHTML = '<pre class="source-view"><code>' + escapeHtml(state.rawMarkdown) + '</code></pre>';
    } else {
        const content = state.rawMarkdown.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, '');
        contentEl.innerHTML = marked.parse(content);
        generateTOC();
        processMermaid();
        processKatex();
    }
}

// ============================================================
// Code copy
// ============================================================

function copyCode(btn) {
    var codeEl = btn.closest('.code-block').querySelector('code');
    var text = codeEl.textContent;
    sendToSwift('copyToClipboard', { text: text });

    btn.textContent = 'Copied!';
    btn.classList.add('copied');
    setTimeout(function() {
        btn.textContent = 'Copy';
        btn.classList.remove('copied');
    }, 2000);
}

// ============================================================
// Image zoom
// ============================================================

function zoomImage(img) {
    var overlay = document.getElementById('image-overlay');
    var overlayImg = overlay.querySelector('img');
    overlayImg.src = img.src;
    overlay.classList.add('visible');
}

function closeImageOverlay() {
    document.getElementById('image-overlay').classList.remove('visible');
}

// ============================================================
// Mermaid
// ============================================================

function processMermaid() {
    if (typeof mermaid === 'undefined') return;

    var blocks = document.querySelectorAll('.code-block');
    var hasMermaid = false;

    blocks.forEach(function(block) {
        var langSpan = block.querySelector('.code-lang');
        if (langSpan && langSpan.textContent.trim().toLowerCase() === 'mermaid') {
            var code = block.querySelector('code').textContent;
            var div = document.createElement('div');
            div.className = 'mermaid';
            div.textContent = code;
            block.replaceWith(div);
            hasMermaid = true;
        }
    });

    if (hasMermaid) {
        try {
            mermaid.initialize({
                startOnLoad: false,
                theme: document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'default'
            });
            mermaid.run();
        } catch (e) { console.error('Mermaid error:', e); }
    }
}

// ============================================================
// KaTeX
// ============================================================

function processKatex() {
    if (typeof renderMathInElement === 'undefined') return;

    try {
        renderMathInElement(document.getElementById('content'), {
            delimiters: [
                { left: '$$', right: '$$', display: true },
                { left: '$', right: '$', display: false },
                { left: '\\(', right: '\\)', display: false },
                { left: '\\[', right: '\\]', display: true }
            ],
            throwOnError: false
        });
    } catch (e) { console.error('KaTeX error:', e); }
}

// ============================================================
// Settings application
// ============================================================

function applySettings(s) {
    var root = document.documentElement;

    // Theme
    if (s.theme === 'auto') {
        root.removeAttribute('data-theme');
    } else {
        root.setAttribute('data-theme', s.theme);
    }

    // Highlight.js theme
    var isDark = s.theme === 'dark' ||
        (s.theme === 'auto' && window.matchMedia('(prefers-color-scheme: dark)').matches);
    var lightCSS = document.getElementById('hljs-light-theme');
    var darkCSS = document.getElementById('hljs-dark-theme');
    if (lightCSS) lightCSS.disabled = isDark;
    if (darkCSS) darkCSS.disabled = !isDark;

    // Font
    if (s.fontFamily && fontPresets[s.fontFamily]) {
        root.style.setProperty('--font-family', fontPresets[s.fontFamily]);
    }

    // Font size
    if (s.fontSize) {
        root.style.setProperty('--font-size', s.fontSize + 'px');
    }

    // Content width
    if (s.contentWidth && widthPresets[s.contentWidth]) {
        root.style.setProperty('--content-width', widthPresets[s.contentWidth]);
    }

    // TOC sidebar
    var sidebar = document.getElementById('toc-sidebar');
    var body = document.body;
    if (s.showTOC) {
        sidebar.classList.add('visible');
        body.classList.add('toc-visible');
    } else {
        sidebar.classList.remove('visible');
        body.classList.remove('toc-visible');
    }

    // Breadcrumb
    var bc = document.getElementById('breadcrumb');
    if (bc) bc.style.display = s.showBreadcrumb ? '' : 'none';

    // Word count
    var sb = document.getElementById('status-bar');
    if (sb) sb.style.display = s.showWordCount ? '' : 'none';

    // Progress bar
    var pb = document.getElementById('progress-bar');
    if (pb) pb.style.display = s.showProgress ? '' : 'none';
}

// ============================================================
// Welcome screen
// ============================================================

function showWelcome(recentFiles) {
    var contentEl = document.getElementById('content');
    var recentHTML = '';

    if (recentFiles && recentFiles.length > 0) {
        recentHTML = '<div class="welcome-recent"><h3>Recent Files</h3><ul>';
        recentFiles.forEach(function(f) {
            var parts = f.split('/');
            var name = parts.pop();
            var dir = parts.slice(-3).join('/');
            recentHTML += '<li><a onclick="sendToSwift(\'openFile\',{path:\''
                + escapeAttr(f) + '\'})">' + escapeHtml(name)
                + '<span class="file-path">' + escapeHtml(dir) + '</span></a></li>';
        });
        recentHTML += '</ul></div>';
    }

    contentEl.innerHTML = '<div class="welcome">'
        + '<div class="welcome-icon">MD</div>'
        + '<h1>Markdown Reader</h1>'
        + '<p>Open a Markdown file to get started</p>'
        + '<p class="welcome-hint">Double-click a .md file in Finder, or use File \u2192 Open (\u2318O)</p>'
        + recentHTML
        + '</div>';
}

// ============================================================
// Link click handling
// ============================================================

document.addEventListener('click', function(e) {
    var link = e.target.closest('a');
    if (!link) return;

    var href = link.getAttribute('href');
    if (!href) return;

    // Heading anchor — copy link
    if (link.classList.contains('heading-anchor')) {
        e.preventDefault();
        sendToSwift('copyToClipboard', { text: href });
        return;
    }

    // In-page anchor
    if (href.startsWith('#')) {
        e.preventDefault();
        var target = document.getElementById(href.substring(1));
        if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        return;
    }

    // External URL
    if (/^https?:\/\//.test(href)) {
        e.preventDefault();
        sendToSwift('openExternal', { url: href });
        return;
    }

    // Internal .md link
    if (/\.(md|markdown|mdown|mkd|mdx)$/i.test(href)) {
        e.preventDefault();
        var absPath = href.startsWith('/') ? href : state.baseDir + '/' + href;
        sendToSwift('openFile', { path: absPath });
        return;
    }
});

// ============================================================
// Keyboard shortcuts
// ============================================================

/* Escape key handled in search section below */

// ============================================================
// System dark mode change listener
// ============================================================

if (window.matchMedia) {
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function() {
        // Re-apply highlight.js theme
        var theme = document.documentElement.getAttribute('data-theme');
        if (!theme || theme === 'auto') {
            var isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
            var lightCSS = document.getElementById('hljs-light-theme');
            var darkCSS = document.getElementById('hljs-dark-theme');
            if (lightCSS) lightCSS.disabled = isDark;
            if (darkCSS) darkCSS.disabled = !isDark;
        }
    });
}

// ============================================================
// Helpers
// ============================================================

function escapeHtml(text) {
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(text));
    return div.innerHTML;
}

function escapeAttr(text) {
    return text.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function sendToSwift(type, data) {
    try {
        var msg = Object.assign({ type: type }, data || {});
        window.webkit.messageHandlers.app.postMessage(msg);
    } catch (e) {
        console.log('Swift bridge unavailable:', type, data);
    }
}

// ============================================================
// Toolbar actions
// ============================================================

function toggleTOCFromToolbar() {
    sendToSwift('toggleTOC');
}

// ============================================================
// Export popover
// ============================================================

function toggleExportPopover(event) {
    var pop = document.getElementById('export-popover');
    if (pop.style.display !== 'none') { pop.style.display = 'none'; return; }

    var btn = document.getElementById('btn-export');
    var r = btn.getBoundingClientRect();
    pop.style.display = '';
    pop.style.top = (r.bottom + 6) + 'px';
    pop.style.right = (window.innerWidth - r.right) + 'px';
    pop.style.left = 'auto';

    // Close on outside click
    setTimeout(function() {
        document.addEventListener('click', closeExportOnOutside, { once: true });
    }, 0);
}
function closeExportOnOutside(e) {
    var pop = document.getElementById('export-popover');
    if (!pop.contains(e.target) && e.target.id !== 'btn-export') {
        pop.style.display = 'none';
    }
}
function doExportPDF() {
    document.getElementById('export-popover').style.display = 'none';
    sendToSwift('exportPDF');
}
function doCopyHTML() {
    document.getElementById('export-popover').style.display = 'none';
    var html = document.getElementById('content').innerHTML;
    sendToSwift('copyToClipboard', { text: html });
}
function doShare() {
    document.getElementById('export-popover').style.display = 'none';
    sendToSwift('share');
}

// ============================================================
// Settings panel — build & manage
// ============================================================

var currentSettings = {};

function buildSettingsHTML(s) {
    var fonts = [
        { key: 'serif', name: 'Default (Serif)',
          en: "'New York', 'Iowan Old Style', Georgia, serif",
          kr: "'AppleMyungjo', serif",
          meta: 'New York \u00B7 AppleMyungjo' },
        { key: 'sans', name: 'Sans',
          en: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif",
          kr: "'Apple SD Gothic Neo', sans-serif",
          meta: 'SF Pro \u00B7 Apple SD Gothic Neo' },
        { key: 'system', name: 'System',
          en: "-apple-system, BlinkMacSystemFont, sans-serif",
          kr: "-apple-system, BlinkMacSystemFont, sans-serif",
          meta: 'System Default' },
        { key: 'mono', name: 'Monospace',
          en: "'SF Mono', Menlo, Consolas, monospace",
          kr: "'SF Mono', Menlo, monospace",
          meta: 'SF Mono \u00B7 Menlo' }
    ];

    var widths = [
        { key: 'narrow', label: 'Narrow', value: '600px', barW: '30%', pageW: '28px' },
        { key: 'standard', label: 'Standard', value: '720px', barW: '50%', pageW: '32px' },
        { key: 'wide', label: 'Wide', value: '900px', barW: '70%', pageW: '36px' },
        { key: 'full', label: 'Full', value: '\u221E', barW: '90%', pageW: '40px' }
    ];

    var toggles = [
        { key: 'autoReload', label: 'Auto-reload on file change' },
        { key: 'rememberScroll', label: 'Remember scroll position' },
        { key: 'showTOC', label: 'Show table of contents' },
        { key: 'showBreadcrumb', label: 'Show breadcrumb path' },
        { key: 'showWordCount', label: 'Show word count' },
        { key: 'showProgress', label: 'Show reading progress' },
        { key: 'enableHighlight', label: 'Syntax highlighting' },
        { key: 'enableMermaid', label: 'Mermaid diagrams' },
        { key: 'enableKatex', label: 'KaTeX math rendering' }
    ];

    var h = '';

    // ── Theme ──
    h += '<div class="s-section"><div class="s-label">Appearance</div><div class="theme-picker">';
    ['light','dark','auto'].forEach(function(t) {
        var sel = s.theme === t ? ' selected' : '';
        var label = t === 'light' ? 'Light' : t === 'dark' ? 'Dark' : 'Auto';
        h += '<div class="theme-card' + sel + '" data-theme="' + t + '" onclick="pickTheme(\'' + t + '\')">';
        h += '<div class="theme-swatch theme-swatch-' + t + '">';
        if (t !== 'auto') {
            h += '<div class="sw-line sw-heading" style="width:40%;height:4px;border-radius:2px"></div>';
            h += '<div class="sw-line" style="width:70%;height:3px;border-radius:2px"></div>';
            h += '<div class="sw-line" style="width:55%;height:3px;border-radius:2px"></div>';
        }
        h += '</div><div class="theme-card-label">' + label + '</div></div>';
    });
    h += '</div></div>';

    // ── Fonts ──
    h += '<div class="s-section"><div class="s-label">Typography</div><div class="font-picker">';
    fonts.forEach(function(f) {
        var sel = s.fontFamily === f.key ? ' selected' : '';
        h += '<div class="font-card' + sel + '" data-font="' + f.key + '" onclick="pickFont(\'' + f.key + '\')">';
        h += '<div class="font-card-name"><span class="dot"></span> ' + escapeHtml(f.name) + '</div>';
        h += '<div class="font-card-sample" style="font-family:' + f.en + '">Reading makes a full man, writing an exact man.</div>';
        h += '<div class="font-card-sample-kr" style="font-family:' + f.kr + '">\uAE00\uC744 \uC77D\uB294 \uC990\uAC70\uC6C0\uC740 \uC0C8\uB85C\uC6B4 \uC138\uACC4\uB97C \uC5EC\uB294 \uBB38\uACFC \uAC19\uC2B5\uB2C8\uB2E4.</div>';
        h += '<div class="font-card-meta">' + f.meta + '</div>';
        h += '</div>';
    });
    h += '</div>';

    // Font size
    h += '<div class="size-row"><span class="size-label">Font Size</span>';
    h += '<div class="stepper"><button onclick="changeFontSize(-1)">\u2212</button>';
    h += '<span class="stepper-val" id="sz-val">' + s.fontSize + 'px</span>';
    h += '<button onclick="changeFontSize(1)">+</button></div></div></div>';

    // ── Width ──
    h += '<div class="s-section"><div class="s-label">Content Width</div><div class="width-picker">';
    widths.forEach(function(w) {
        var sel = s.contentWidth === w.key ? ' selected' : '';
        h += '<div class="width-card' + sel + '" data-width="' + w.key + '" onclick="pickWidth(\'' + w.key + '\')">';
        h += '<div class="width-icon"><div class="page" style="width:' + w.pageW + '"><div class="bar" style="width:' + w.barW + '"></div></div></div>';
        h += '<div class="width-card-label">' + w.label + '</div>';
        h += '<div class="width-card-value">' + w.value + '</div></div>';
    });
    h += '</div></div>';

    // ── Toggles ──
    h += '<div class="s-section"><div class="s-label">Features</div><div class="toggle-list">';
    toggles.forEach(function(t) {
        var checked = s[t.key] ? ' checked' : '';
        h += '<div class="toggle-row"><span>' + t.label + '</span>';
        h += '<label class="toggle-switch"><input type="checkbox"' + checked + ' onchange="toggleSetting(\'' + t.key + '\',this.checked)">';
        h += '<span class="toggle-slider"></span></label></div>';
    });
    h += '</div></div>';

    return h;
}

function toggleSettingsPanel() {
    var overlay = document.getElementById('settings-overlay');
    if (overlay.style.display !== 'none') { closeSettingsPanel(); return; }
    overlay.style.display = '';
    document.getElementById('settings-body').innerHTML = buildSettingsHTML(currentSettings);
}

function closeSettingsPanel() {
    document.getElementById('settings-overlay').style.display = 'none';
}

function pickTheme(t) {
    currentSettings.theme = t;
    sendToSwift('updateSetting', { key: 'theme', value: t });
    document.querySelectorAll('.theme-card').forEach(function(c) {
        c.classList.toggle('selected', c.dataset.theme === t);
    });
}

function pickFont(f) {
    currentSettings.fontFamily = f;
    sendToSwift('updateSetting', { key: 'fontFamily', value: f });
    document.querySelectorAll('.font-card').forEach(function(c) {
        c.classList.toggle('selected', c.dataset.font === f);
    });
}

function changeFontSize(delta) {
    var sz = Math.max(12, Math.min(28, (currentSettings.fontSize || 16) + delta));
    currentSettings.fontSize = sz;
    sendToSwift('updateSetting', { key: 'fontSize', value: sz });
    var el = document.getElementById('sz-val');
    if (el) el.textContent = sz + 'px';
}

function pickWidth(w) {
    currentSettings.contentWidth = w;
    sendToSwift('updateSetting', { key: 'contentWidth', value: w });
    document.querySelectorAll('.width-card').forEach(function(c) {
        c.classList.toggle('selected', c.dataset.width === w);
    });
}

function toggleSetting(key, val) {
    currentSettings[key] = val;
    sendToSwift('updateSetting', { key: key, value: val });
}

// Override applySettings to also store currentSettings
var _origApply = applySettings;
applySettings = function(s) {
    currentSettings = Object.assign(currentSettings, s);
    _origApply(s);
    // Update TOC toolbar button state
    var tocBtn = document.getElementById('btn-toc');
    if (tocBtn) tocBtn.classList.toggle('active', !!s.showTOC);
    // Update toolbar font size display
    var tbSz = document.getElementById('tb-font-size');
    if (tbSz && s.fontSize) tbSz.textContent = s.fontSize + 'px';
};

// ============================================================
// Toolbar font size controls
// ============================================================

function changeFontSizeFromToolbar(delta) {
    var sz = Math.max(12, Math.min(28, (currentSettings.fontSize || 16) + delta));
    currentSettings.fontSize = sz;
    sendToSwift('updateSetting', { key: 'fontSize', value: sz });
    var tbSz = document.getElementById('tb-font-size');
    if (tbSz) tbSz.textContent = sz + 'px';
    // Also update settings panel if open
    var el = document.getElementById('sz-val');
    if (el) el.textContent = sz + 'px';
}

// ============================================================
// In-app Search (Cmd+F)
// ============================================================

var searchState = { marks: [], current: -1 };

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        closeImageOverlay();
        closeSearch();
    }
    if ((e.metaKey || e.ctrlKey) && e.key === 'f') {
        e.preventDefault();
        openSearch();
    }
});

function openSearch() {
    var bar = document.getElementById('search-bar');
    bar.style.display = '';
    var input = document.getElementById('search-input');
    input.focus();
    input.select();
}

function closeSearch() {
    document.getElementById('search-bar').style.display = 'none';
    clearHighlights();
    searchState.marks = [];
    searchState.current = -1;
    document.getElementById('search-count').textContent = '';
    document.getElementById('search-input').value = '';
}

function clearHighlights() {
    document.querySelectorAll('mark.search-hl').forEach(function(m) {
        var parent = m.parentNode;
        parent.replaceChild(document.createTextNode(m.textContent), m);
        parent.normalize();
    });
}

function doSearch(query) {
    clearHighlights();
    searchState.marks = [];
    searchState.current = -1;

    if (!query || query.length < 1) {
        document.getElementById('search-count').textContent = '';
        return;
    }

    var contentEl = document.getElementById('content');
    highlightMatches(contentEl, query.toLowerCase());
    searchState.marks = Array.from(document.querySelectorAll('mark.search-hl'));

    var countEl = document.getElementById('search-count');
    if (searchState.marks.length > 0) {
        searchState.current = 0;
        searchState.marks[0].classList.add('current');
        searchState.marks[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
        countEl.textContent = '1 / ' + searchState.marks.length;
    } else {
        countEl.textContent = query.length > 0 ? 'No results' : '';
    }
}

function highlightMatches(node, query) {
    if (node.nodeType === 3) { // Text node
        var text = node.textContent;
        var lower = text.toLowerCase();
        var idx = lower.indexOf(query);
        if (idx === -1) return;

        var frag = document.createDocumentFragment();
        var lastIdx = 0;
        while (idx !== -1) {
            if (idx > lastIdx) frag.appendChild(document.createTextNode(text.substring(lastIdx, idx)));
            var mark = document.createElement('mark');
            mark.className = 'search-hl';
            mark.textContent = text.substring(idx, idx + query.length);
            frag.appendChild(mark);
            lastIdx = idx + query.length;
            idx = lower.indexOf(query, lastIdx);
        }
        if (lastIdx < text.length) frag.appendChild(document.createTextNode(text.substring(lastIdx)));
        node.parentNode.replaceChild(frag, node);
    } else if (node.nodeType === 1 && node.tagName !== 'SCRIPT' && node.tagName !== 'STYLE' && node.tagName !== 'MARK') {
        // Copy childNodes to avoid mutation issues during iteration
        var children = Array.from(node.childNodes);
        for (var i = 0; i < children.length; i++) {
            highlightMatches(children[i], query);
        }
    }
}

function searchNav(dir) {
    if (searchState.marks.length === 0) return;
    searchState.marks[searchState.current].classList.remove('current');
    searchState.current = (searchState.current + dir + searchState.marks.length) % searchState.marks.length;
    searchState.marks[searchState.current].classList.add('current');
    searchState.marks[searchState.current].scrollIntoView({ behavior: 'smooth', block: 'center' });
    document.getElementById('search-count').textContent = (searchState.current + 1) + ' / ' + searchState.marks.length;
}

// Debounced search on input
(function() {
    var timer = null;
    document.addEventListener('input', function(e) {
        if (e.target.id !== 'search-input') return;
        clearTimeout(timer);
        timer = setTimeout(function() { doSearch(e.target.value); }, 200);
    });
    document.addEventListener('keydown', function(e) {
        if (e.target.id !== 'search-input') return;
        if (e.key === 'Enter') {
            e.preventDefault();
            searchNav(e.shiftKey ? -1 : 1);
        }
    });
})();

// ============================================================
// Frontmatter parsing & display
// ============================================================

function parseFrontmatter(markdown) {
    var match = markdown.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
    if (!match) return null;

    var meta = {};
    var lines = match[1].split('\n');
    var currentKey = null;

    lines.forEach(function(line) {
        // Simple YAML key: value parser
        var kv = line.match(/^(\w[\w\s-]*?):\s*(.*)$/);
        if (kv) {
            currentKey = kv[1].trim().toLowerCase();
            var val = kv[2].trim();
            // Array notation: [a, b, c]
            if (val.startsWith('[') && val.endsWith(']')) {
                meta[currentKey] = val.slice(1, -1).split(',').map(function(s) { return s.trim().replace(/^["']|["']$/g, ''); });
            } else if (val) {
                meta[currentKey] = val.replace(/^["']|["']$/g, '');
            }
        } else if (currentKey && line.match(/^\s+-\s+(.+)/)) {
            // YAML list item
            var item = line.match(/^\s+-\s+(.+)/)[1].trim().replace(/^["']|["']$/g, '');
            if (!Array.isArray(meta[currentKey])) meta[currentKey] = [];
            meta[currentKey].push(item);
        }
    });

    return Object.keys(meta).length > 0 ? meta : null;
}

function renderFrontmatter(meta) {
    if (!meta) return '';

    var html = '<div class="frontmatter-bar">';
    var displayed = false;

    if (meta.title) {
        html += '<span class="fm-title">' + escapeHtml(meta.title) + '</span>';
        displayed = true;
    }

    if (meta.date) {
        html += '<span class="fm-meta"><svg viewBox="0 0 16 16" width="12" height="12"><rect x="2" y="3" width="12" height="11" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.3"/><line x1="2" y1="7" x2="14" y2="7" stroke="currentColor" stroke-width="1.3"/><line x1="5" y1="1" x2="5" y2="4" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/><line x1="11" y1="1" x2="11" y2="4" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg> ' + escapeHtml(meta.date) + '</span>';
        displayed = true;
    }

    if (meta.author) {
        var author = Array.isArray(meta.author) ? meta.author.join(', ') : meta.author;
        html += '<span class="fm-meta"><svg viewBox="0 0 16 16" width="12" height="12"><circle cx="8" cy="5" r="3" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M2,14 C2,10 5,9 8,9 C11,9 14,10 14,14" fill="none" stroke="currentColor" stroke-width="1.3"/></svg> ' + escapeHtml(author) + '</span>';
        displayed = true;
    }

    if (meta.tags) {
        var tags = Array.isArray(meta.tags) ? meta.tags : [meta.tags];
        tags.forEach(function(tag) {
            html += '<span class="fm-tag">' + escapeHtml(tag) + '</span>';
        });
        displayed = true;
    }

    if (meta.category) {
        html += '<span class="fm-tag fm-category">' + escapeHtml(meta.category) + '</span>';
        displayed = true;
    }

    if (meta.status) {
        html += '<span class="fm-status">' + escapeHtml(meta.status) + '</span>';
        displayed = true;
    }

    html += '</div>';
    return displayed ? html : '';
}

// ============================================================
// Folder tree sidebar
// ============================================================

var folderTreeState = { root: '', expanded: {} };

function setFolderTree(tree, rootDir) {
    folderTreeState.root = rootDir;

    var section = document.getElementById('file-list-section');
    var list = document.getElementById('file-list');

    // Change header to "Files"
    section.style.display = '';
    list.innerHTML = renderFolderNode(tree, rootDir, 0);
}

function renderFolderNode(node, currentPath, depth) {
    var html = '';
    if (!node) return html;

    // Sort: folders first, then files
    var entries = Object.keys(node).sort(function(a, b) {
        var aIsDir = typeof node[a] === 'object' && node[a] !== null;
        var bIsDir = typeof node[b] === 'object' && node[b] !== null;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.localeCompare(b);
    });

    entries.forEach(function(name) {
        var fullPath = currentPath + '/' + name;
        var value = node[name];
        var indent = depth * 16;

        if (typeof value === 'object' && value !== null) {
            // Directory
            var isExpanded = folderTreeState.expanded[fullPath];
            var arrow = isExpanded ? '\u25BE' : '\u25B8';
            html += '<a class="tree-dir" style="padding-left:' + (16 + indent) + 'px" onclick="toggleFolderNode(\'' + escapeAttr(fullPath) + '\')">';
            html += '<span class="tree-arrow">' + arrow + '</span> ' + escapeHtml(name) + '</a>';
            if (isExpanded) {
                html += renderFolderNode(value, fullPath, depth + 1);
            }
        } else {
            // File
            var isCurrent = state.filePath === fullPath;
            var cls = isCurrent ? 'tree-file current-file' : 'tree-file';
            html += '<a class="' + cls + '" style="padding-left:' + (30 + indent) + 'px" onclick="sendToSwift(\'openFile\',{path:\'' + escapeAttr(fullPath) + '\'})">';
            html += escapeHtml(name) + '</a>';
        }
    });

    return html;
}

function toggleFolderNode(path) {
    folderTreeState.expanded[path] = !folderTreeState.expanded[path];
    sendToSwift('requestFolderTree', { path: folderTreeState.root });
}

// ============================================================
// Bookmarks
// ============================================================

function updateBookmarkState(isBookmarked) {
    var btn = document.getElementById('btn-bookmark');
    if (!btn) return;
    btn.classList.toggle('active', isBookmarked);
    // Fill the bookmark icon when active
    var path = btn.querySelector('path');
    if (path) {
        path.setAttribute('fill', isBookmarked ? 'currentColor' : 'none');
    }
}

function setBookmarks(bookmarks) {
    var section = document.getElementById('bookmark-section');
    var list = document.getElementById('bookmark-list');
    list.innerHTML = '';

    if (!bookmarks || bookmarks.length === 0) {
        section.style.display = 'none';
        return;
    }

    section.style.display = '';
    bookmarks.forEach(function(fullPath) {
        var parts = fullPath.split('/');
        var name = parts.pop();
        var dir = parts.slice(-2).join('/');

        var a = document.createElement('a');
        a.className = state.filePath === fullPath ? 'current-file' : '';
        a.innerHTML = escapeHtml(name) + '<span class="bookmark-path">' + escapeHtml(dir) + '</span>';
        a.onclick = function(e) {
            e.preventDefault();
            sendToSwift('openFile', { path: fullPath });
        };
        list.appendChild(a);
    });
}
