const navToggle = document.querySelector('.nav-toggle');
const body = document.body;

if (navToggle) {
  navToggle.addEventListener('click', () => {
    const isOpen = body.classList.toggle('nav-open');
    navToggle.setAttribute('aria-expanded', isOpen.toString());
  });
}
