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

// Colour and light/dark picker in the nav. The choice is remembered on this device.
(() => {
  const COLORS = { pink: '#C8347A', orange: '#C2410C', blue: '#1D5FD0', green: '#15803D', purple: '#6D3FD6' };
  const root = document.documentElement, nav = document.querySelector('nav');
  const saved = k => { try { return localStorage.getItem('tiles-' + k); } catch { return null; } };
  const state = { color: COLORS[saved('color')] ? saved('color') : 'pink', theme: saved('theme') === 'dark' ? 'dark' : 'light' };
  const pick = document.createElement('div'); pick.className = 'pick';
  pick.innerHTML = Object.entries(COLORS).map(([name, hex]) => `<button data-color="${name}" style="--d:${hex}" aria-label="${name} colour"></button>`).join('') + '<button class="mode"></button>';
  const apply = () => {
    root.style.setProperty('--c', COLORS[state.color]); root.dataset.theme = state.theme;
    pick.querySelectorAll('[data-color]').forEach(b => b.setAttribute('aria-pressed', b.dataset.color === state.color));
    pick.lastChild.textContent = state.theme === 'dark' ? 'Light' : 'Dark';
    try { localStorage.setItem('tiles-color', state.color); localStorage.setItem('tiles-theme', state.theme); } catch {}
  };
  pick.onclick = e => { const b = e.target.closest('button'); if (!b) return; if (b.dataset.color) state.color = b.dataset.color; else state.theme = state.theme === 'dark' ? 'light' : 'dark'; apply(); };
  apply(); if (nav) nav.appendChild(pick);
})();
