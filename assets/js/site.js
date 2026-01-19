document.documentElement.classList.add('js');

// Reading progress bar
const progressBar = document.getElementById('reading-progress');
if (progressBar) {
  window.addEventListener('scroll', () => {
    const docHeight = document.documentElement.scrollHeight - window.innerHeight;
    const scrolled = window.scrollY;
    const percent = docHeight > 0 ? (scrolled / docHeight) * 100 : 0;
    progressBar.style.width = percent + '%';
  });
}

// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', function (e) {
    const target = document.querySelector(this.getAttribute('href'));
    if (target) {
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth' });
    }
  });
});

// Mermaid rendering from fenced code blocks
const mermaidCodeBlocks = document.querySelectorAll('pre > code.language-mermaid, pre > code.mermaid');
if (mermaidCodeBlocks.length && window.mermaid) {
  mermaidCodeBlocks.forEach(code => {
    const pre = code.parentElement;
    const container = document.createElement('div');
    container.className = 'mermaid';
    container.textContent = code.textContent;
    if (pre && pre.parentElement) {
      pre.parentElement.replaceChild(container, pre);
    }
  });

  try {
    if (typeof window.mermaid.initialize === 'function') {
      window.mermaid.initialize({ startOnLoad: false, theme: 'default' });
    }
    if (typeof window.mermaid.run === 'function') {
      window.mermaid.run({ nodes: document.querySelectorAll('.mermaid') });
    }
  } catch (error) {
    console.warn('Mermaid rendering failed:', error);
  }
}

// Copy code button for pre blocks (skip Mermaid blocks)
document.querySelectorAll('.markdown-content pre').forEach(pre => {
  const code = pre.querySelector('code');
  if (code && (code.classList.contains('language-mermaid') || code.classList.contains('mermaid'))) {
    return;
  }

  const btn = document.createElement('button');
  btn.className = 'copy-btn';
  btn.textContent = 'Copy';
  btn.addEventListener('click', () => {
    const codeBlock = pre.querySelector('code');
    if (codeBlock) {
      navigator.clipboard.writeText(codeBlock.textContent).then(() => {
        btn.textContent = 'Copied!';
        setTimeout(() => (btn.textContent = 'Copy'), 2000);
      });
    }
  });
  pre.style.position = 'relative';
  pre.appendChild(btn);
});
