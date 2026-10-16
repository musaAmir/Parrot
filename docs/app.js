'use strict';
const preview = document.querySelector('#voice-preview');
const button = document.querySelector('#try-demo');
const time = document.querySelector('.demo-time');
const status = document.querySelector('#demo-status');
const heights = [7, 13, 20, 28, 16, 35, 43, 23, 34, 47, 25, 18, 31, 39, 17, 26, 14, 8];
heights.forEach((height, index) => {
  const bar = document.createElement('i');
  bar.style.setProperty('--bar-height', height + 'px');
  bar.style.setProperty('--bar-delay', (index % 5) * -0.12 + 's');
  document.querySelector('.wave-bars').append(bar);
});
let timers = [];
function reset() {
  timers.forEach(clearTimeout); timers = [];
  preview.dataset.state = 'idle';
  time.textContent = '0:00';
  button.disabled = false;
  button.innerHTML = '<span class="demo-button-icon">▶</span> Try the flow';
  status.textContent = 'Preview complete. No audio was recorded.';
}
button.addEventListener('click', () => {
  reset(); button.disabled = true;
  button.textContent = 'Recording preview…';
  preview.dataset.state = 'recording';
  status.textContent = 'Example recording, then playback. No microphone access or sound.';
  timers.push(setTimeout(() => { time.textContent = '0:01'; }, 1000));
  timers.push(setTimeout(() => {
    time.textContent = '0:02'; preview.dataset.state = 'playing';
    button.textContent = 'Playing it back…'; status.textContent = 'Example playback.';
  }, 2000));
  timers.push(setTimeout(reset, 4400));
});
document.addEventListener('visibilitychange', () => { if (document.hidden) reset(); });
document.querySelectorAll('a[href="#install-note"]').forEach(link => link.addEventListener('click', () => { document.querySelector('#install-note').open = true; }));
function openLinkedNote() { if (location.hash === '#install-note') document.querySelector('#install-note').open = true; }
window.addEventListener('hashchange', openLinkedNote);
openLinkedNote();
