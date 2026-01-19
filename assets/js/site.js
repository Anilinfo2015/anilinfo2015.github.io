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

// Copy code button for pre blocks
document.querySelectorAll('.markdown-content pre').forEach(pre => {
  const btn = document.createElement('button');
  btn.className = 'copy-btn';
  btn.textContent = 'Copy';
  btn.addEventListener('click', () => {
    const code = pre.querySelector('code');
    if (code) {
      navigator.clipboard.writeText(code.textContent).then(() => {
        btn.textContent = 'Copied!';
        setTimeout(() => (btn.textContent = 'Copy'), 2000);
      });
    }
  });
  pre.style.position = 'relative';
  pre.appendChild(btn);
});
