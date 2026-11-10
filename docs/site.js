// Shared by every page: copy button, scroll reveal, the home page's layout switcher.
function copyCmd(b) { navigator.clipboard.writeText(document.getElementById('cmd').textContent).then(() => { b.textContent = 'Copied'; setTimeout(() => b.textContent = 'Copy', 1500); }); }

// Scroll reveal, once per element. Without JS (or IntersectionObserver) everything is simply visible.
if ('IntersectionObserver' in window) {
  document.documentElement.classList.add('js');
  document.querySelectorAll('section h2, section .center, .card, table, details, .kinds, .cta .icon, .cta .btn').forEach(el => el.classList.add('reveal'));
  document.querySelectorAll('.grid, .faq').forEach(g => [...g.children].forEach((el, i) => el.style.setProperty('--i', i % 4)));
  const seen = new IntersectionObserver(entries => entries.forEach(e => { if (e.isIntersecting) { e.target.dataset.visible = ''; seen.unobserve(e.target); } }), { rootMargin: '0px 0px -80px 0px' });
  document.querySelectorAll('.reveal, .wipe').forEach(el => seen.observe(el));
}

// Home: click a tab to see that layout. It plays through by itself until you touch it.
(() => {
  const tabs = [...document.querySelectorAll('.switch .tabs button')], shots = [...document.querySelectorAll('.stage img')], cap = document.getElementById('cap');
  if (!tabs.length) return;
  let current = 0;
  const show = i => { current = i; tabs.forEach((t, k) => t.setAttribute('aria-selected', k === i)); shots.forEach((im, k) => im.classList.toggle('on', k === i)); cap.textContent = tabs[i].dataset.cap; };
  let auto = matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : setInterval(() => show((current + 1) % tabs.length), 4000);
  const stop = () => { clearInterval(auto); auto = 0; };
  tabs.forEach((t, i) => t.addEventListener('click', () => { stop(); show(i); }));
  document.querySelector('.stage').addEventListener('pointerenter', stop);
})();
