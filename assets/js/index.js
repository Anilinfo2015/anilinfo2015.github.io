// Navigation toggle
const navToggle = document.querySelector('.nav-toggle');
const body = document.body;

if (navToggle) {
  navToggle.addEventListener('click', () => {
    const isOpen = body.classList.toggle('nav-open');
    navToggle.setAttribute('aria-expanded', isOpen.toString());
  });
}

// Scroll reveal animations
const observerOptions = {
  root: null,
  rootMargin: '0px',
  threshold: 0.1
};

const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('active');
    }
  });
}, observerOptions);

document.querySelectorAll('.reveal, .reveal-left, .reveal-right').forEach(el => {
  revealObserver.observe(el);
});

// Back to top button
const backToTop = document.querySelector('.back-to-top');
if (backToTop) {
  window.addEventListener('scroll', () => {
    if (window.scrollY > 400) {
      backToTop.classList.add('visible');
    } else {
      backToTop.classList.remove('visible');
    }
  });

  backToTop.addEventListener('click', () => {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });
}

// Header shrink on scroll
const header = document.querySelector('.site-header');
if (header) {
  window.addEventListener('scroll', () => {
    if (window.scrollY > 100) {
      header.classList.add('scrolled');
    } else {
      header.classList.remove('scrolled');
    }
  });
}

// Active nav link highlighting
const sections = document.querySelectorAll('section[id]');
const navLinks = document.querySelectorAll('.nav-links a[href^="#"]');

function highlightNavLink() {
  const scrollY = window.scrollY;
  
  sections.forEach(section => {
    const sectionHeight = section.offsetHeight;
    const sectionTop = section.offsetTop - 100;
    const sectionId = section.getAttribute('id');
    
    if (scrollY > sectionTop && scrollY <= sectionTop + sectionHeight) {
      navLinks.forEach(link => {
        link.classList.remove('active');
        if (link.getAttribute('href') === `#${sectionId}`) {
          link.classList.add('active');
        }
      });
    }
  });
}

window.addEventListener('scroll', highlightNavLink);

// Topic filter functionality
const topicChips = document.querySelectorAll('.topic-chip');
const categoryCards = document.querySelectorAll('.category-card');

topicChips.forEach(chip => {
  chip.addEventListener('click', (e) => {
    const href = chip.getAttribute('href');
    
    // If it's a category link, let it scroll to the category
    if (href && href.startsWith('#category-')) {
      // Smooth scroll is handled by CSS scroll-behavior
      return;
    }
    
    e.preventDefault();
    
    // Toggle active state for filtering
    topicChips.forEach(c => c.classList.remove('active'));
    chip.classList.add('active');
  });
});

// Filter buttons functionality
const filterBtns = document.querySelectorAll('.filter-btn');
const articleCards = document.querySelectorAll('.article-card');

filterBtns.forEach(btn => {
  btn.addEventListener('click', () => {
    filterBtns.forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    
    const filter = btn.dataset.filter;
    
    articleCards.forEach(card => {
      if (filter === 'all') {
        card.style.display = '';
      } else {
        const category = card.dataset.category;
        card.style.display = category === filter ? '' : 'none';
      }
    });
  });
});

// View toggle (grid/list)
const viewBtns = document.querySelectorAll('.view-btn');
const articlesGrid = document.querySelector('.articles-grid');

viewBtns.forEach(btn => {
  btn.addEventListener('click', () => {
    viewBtns.forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    
    const view = btn.dataset.view;
    if (articlesGrid) {
      articlesGrid.classList.toggle('list-view', view === 'list');
    }
  });
});

// Search functionality
const searchInput = document.querySelector('.search-input');
const allCards = document.querySelectorAll('.article-card, .recent-card');

if (searchInput) {
  searchInput.addEventListener('input', (e) => {
    const query = e.target.value.toLowerCase().trim();
    
    allCards.forEach(card => {
      const title = card.querySelector('h4')?.textContent.toLowerCase() || '';
      const excerpt = card.querySelector('p')?.textContent.toLowerCase() || '';
      const category = card.querySelector('.article-category, .recent-category')?.textContent.toLowerCase() || '';
      
      const matches = title.includes(query) || excerpt.includes(query) || category.includes(query);
      card.style.display = matches || query === '' ? '' : 'none';
    });
  });
}

// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', function(e) {
    const href = this.getAttribute('href');
    if (href && href.length > 1) {
      const target = document.querySelector(href);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        
        // Close mobile nav if open
        body.classList.remove('nav-open');
        if (navToggle) {
          navToggle.setAttribute('aria-expanded', 'false');
        }
      }
    }
  });
});

// Stagger animation for cards on load
document.addEventListener('DOMContentLoaded', () => {
  const cards = document.querySelectorAll('.recent-card, .recommended-card, .category-card, .featured-item');
  cards.forEach((card, index) => {
    card.style.animationDelay = `${index * 0.1}s`;
  });
});
