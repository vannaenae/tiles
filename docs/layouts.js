// The layout playground: real app windows arranged with the same maths as the app
// (Sources/TilesCore/Layout.swift and Scrolling.swift).
const cols=(r,n,g)=>{let u=r.w-g*(n-1),o=[],c=r.x;for(let i=0;i<n;i++){let e=r.x+Math.round(u*(i+1)/n)+g*i;o.push({x:c,y:r.y,w:e-c,h:r.h});c=e+g}return o};
const rows=(r,n,g)=>{let u=r.h-g*(n-1),o=[],c=r.y;for(let i=0;i<n;i++){let e=r.y+Math.round(u*(i+1)/n)+g*i;o.push({x:r.x,y:c,w:r.w,h:e-c});c=e+g}return o};
const sc=(r,t,g)=>{let u=r.w-g,l=Math.round(u*t);return[{x:r.x,y:r.y,w:l,h:r.h},{x:r.x+l+g,y:r.y,w:u-l,h:r.h}]};
const sr=(r,t,g)=>{let u=r.h-g,l=Math.round(u*t);return[{x:r.x,y:r.y,w:r.w,h:l},{x:r.x,y:r.y+l+g,w:r.w,h:u-l}]};
function frames(kind,n,W,H){const g=Math.round(W/180),a={x:g,y:g,w:W-2*g,h:H-2*g},t=.55;
 if(n==1&&a.w/a.h>=2&&kind!='monocle'){const w=Math.min(Math.round(a.w*.6),2600);return[{x:a.x+(a.w-w)/2,y:a.y,w,h:a.h}]}
 switch(kind){
 case'dwindle':{let o=[],rem=a;for(let i=0;i<n;i++){if(i==n-1){o.push(rem);break}let[p,q]=rem.w>=rem.h?sc(rem,i?.5:t,g):sr(rem,i?.5:t,g);o.push(p);rem=q}return o}
 case'master':{if(n<2)return[a];let[l,r]=sc(a,t,g);return[l,...rows(r,n-1,g)]}
 case'centered':{if(n<2)return[a];if(n==2)return sc(a,t,g);let mw=Math.round((a.w-2*g)*t),sw=Math.round((a.w-2*g-mw)/2),L={x:a.x,y:a.y,w:sw,h:a.h},M={x:L.x+sw+g,y:a.y,w:mw,h:a.h},R={x:M.x+mw+g,y:a.y,w:a.x+a.w-M.x-mw-g,h:a.h},s=n-1,rr=rows(R,Math.ceil(s/2),g),ll=rows(L,Math.floor(s/2),g),o=[M];for(let i=0;i<s;i++)o.push(i%2?ll[i>>1]:rr[i>>1]);return o}
 case'columns':return cols(a,n,g);
 case'thirds':{if(n<2)return[a];if(n==2)return sc(a,2/3,g);let c=cols(a,3,g);return[c[0],c[1],...rows(c[2],n-2,g)]}
 case'grid':{let s=Math.ceil(Math.sqrt(n)),rc=a.w>=a.h?Math.ceil(n/s):s,o=[],rem=n;rows(a,rc,g).forEach((r,i)=>{let k=Math.ceil(rem/(rc-i));o.push(...cols(r,k,g));rem-=k});return o}
 case'scrolling':{let w=Math.round(.5*(a.w+g)-g),o=[];for(let i=0;i<n;i++){let x=a.x+i*(w+g);o.push(x+w<=a.x+a.w+1?{x,y:a.y,w,h:a.h}:{x:a.x+a.w-6,y:a.y,w,h:a.h})}return o}
 case'monocle':return Array(n).fill(a);}}
const SCREENS = [['MacBook 14″', 1512, 945], ['27″', 2560, 1415], ['34″ ultrawide', 3440, 1415], ['49″', 5120, 1415]];
const LAYOUTS = [['dwindle', 'Dwindle'], ['master', 'Master & Stack'], ['centered', 'Center Stage'], ['columns', 'Columns'], ['thirds', 'Thirds'], ['grid', 'Grid'], ['scrolling', 'Scrolling'], ['monocle', 'Monocle']];
// Real windows, cut from screenshots: [image, its width in points, background below the screenshot].
const WINDOWS = [['github', 784, '#fff'], ['claude', 714, '#faf9f5'], ['google', 708, '#fff'], ['terminal', 714, '#fff'], ['appstore', 784, '#fff']];
const MENU_BAR = 24;
let screen = 0, layout = 'dwindle', n = 4;
let order = WINDOWS.map((_, i) => i); // order[slot] = which window sits in that tile
let focused = 0, slots = [], tried = false; // tried: the visitor has moved a window, so the hint can go quiet
const desk = document.getElementById('desk'), bar = desk.querySelector('.bar');
const wins = WINDOWS.map(([name, , bg], w) => {
  const d = document.createElement('div');
  d.className = 'win'; d.style.background = bg; d.innerHTML = `<img src="img/win-${name}.jpg" alt="" draggable="false">`;
  d.addEventListener('pointerdown', e => startDrag(e, w));
  d.addEventListener('dblclick', () => { makeMain(w); render(); });
  desk.appendChild(d); return d;
});

function seg(id, items, isOn, pick) {
  const el = document.getElementById(id);
  el.innerHTML = items.map((label, i) => `<button role="tab" aria-selected="${isOn(i)}">${label}</button>`).join('');
  [...el.children].forEach((b, i) => b.onclick = () => { pick(i); render(); });
}
function render() {
  seg('screens', SCREENS.map(s => s[0]), i => i === screen, i => screen = i);
  seg('layouts', LAYOUTS.map(l => l[1]), i => LAYOUTS[i][0] === layout, i => layout = LAYOUTS[i][0]);
  const [, W, H] = SCREENS[screen], width = Math.min(desk.parentElement.clientWidth, 980), s = width / W;
  desk.style.width = width + 'px'; desk.style.height = Math.round(H * s) + 'px'; bar.style.height = MENU_BAR * s + 'px';
  if (order.indexOf(focused) >= n) focused = order[0];
  slots = frames(layout, n, W, H - MENU_BAR).map(r => ({ x: r.x * s, y: (r.y + MENU_BAR) * s, w: r.w * s, h: r.h * s }));
  order.forEach((w, slot) => {
    const d = wins[w];
    d.classList.toggle('focus', w === focused && slot < n);
    d.classList.toggle('nudge', !tried && w === focused && slot < n);
    if (slot >= n) { d.style.opacity = 0; d.style.pointerEvents = 'none'; return; }
    const r = slots[slot];
    d.style.opacity = 1; d.style.pointerEvents = ''; d.style.zIndex = w === focused ? 2 : 1; d.style.borderRadius = Math.max(3, 10 * s) + 'px';
    Object.assign(d.style, { left: r.x + 'px', top: r.y + 'px', width: r.w + 'px', height: r.h + 'px' });
    d.firstChild.style.setProperty('--w', WINDOWS[w][1] * s + 'px');
  });
  document.getElementById('count').textContent = n + (n === 1 ? ' window' : ' windows');
}

// Like the app: drag a window onto another to swap them, click to focus, double-click to make it the main window.
function swap(a, b) { [order[a], order[b]] = [order[b], order[a]]; }
function makeMain(w) { swap(0, order.indexOf(w)); focused = w; }
function slotAt(x, y, except) { return slots.findIndex((r, k) => k !== except && x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h); }
function startDrag(e, w) {
  const d = wins[w], from = order.indexOf(w), x0 = e.clientX, y0 = e.clientY;
  let moved = false, target = -1;
  d.setPointerCapture(e.pointerId);
  const mark = k => wins.forEach((el, i) => el.classList.toggle('drop', k >= 0 && order[k] === i));
  const move = ev => {
    const dx = ev.clientX - x0, dy = ev.clientY - y0;
    if (!moved && Math.hypot(dx, dy) < 5) return;
    moved = true; d.classList.add('drag'); d.style.transform = `translate(${dx}px, ${dy}px)`;
    const box = desk.getBoundingClientRect();
    target = layout === 'monocle' ? -1 : slotAt(ev.clientX - box.left, ev.clientY - box.top, from); mark(target);
  };
  const up = () => {
    d.removeEventListener('pointermove', move); d.removeEventListener('pointerup', up); d.removeEventListener('pointercancel', up);
    d.classList.remove('drag'); d.style.transform = ''; mark(-1);
    tried = true; document.getElementById('hint').classList.add('done');
    if (moved && target >= 0) swap(from, target);
    // In Monocle every window fills the screen, so a click brings the next one forward.
    focused = !moved && layout === 'monocle' ? order[(from + 1) % n] : w;
    render();
  };
  d.addEventListener('pointermove', move); d.addEventListener('pointerup', up); d.addEventListener('pointercancel', up);
}
// Keyboard, once the screen is focused: arrows move between windows, Return makes one the main window, Space changes layout.
desk.addEventListener('keydown', e => {
  const dir = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
  if (dir) {
    const here = slots[order.indexOf(focused)], cx = r => r.x + r.w / 2, cy = r => r.y + r.h / 2;
    const ahead = slots.map((r, k) => [k, (cx(r) - cx(here)) * dir[0] + (cy(r) - cy(here)) * dir[1], Math.hypot(cx(r) - cx(here), cy(r) - cy(here))]).filter(c => c[1] > 1).sort((a, b) => a[2] - b[2])[0];
    if (ahead) focused = order[ahead[0]];
  } else if (e.key === 'Enter') makeMain(focused);
  else if (e.key === ' ') layout = LAYOUTS[(LAYOUTS.findIndex(l => l[0] === layout) + 1) % LAYOUTS.length][0];
  else return;
  e.preventDefault(); render();
});
document.getElementById('add').onclick = () => { n = Math.min(WINDOWS.length, n + 1); render(); };
document.getElementById('remove').onclick = () => { n = Math.max(1, n - 1); render(); };
addEventListener('resize', render); render();
