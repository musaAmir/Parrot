import { VoiceDemo } from './voice-demo.js';

const preview = document.querySelector('#voice-preview');
const button = document.querySelector('#try-demo');
const clearButton = document.querySelector('#clear-demo');
const playButton = document.querySelector('#play-demo');
const replayButton = document.querySelector('#replay-demo');
const time = document.querySelector('.demo-time');
const status = document.querySelector('#demo-status');
const progress = document.querySelector('.play-track');
const fill = progress.querySelector('i');
const instruction = document.querySelector('#voice-instruction');
const bars = Array.from({ length: 18 }, () => {
  const bar = document.createElement('i');
  bar.style.setProperty('--bar-height', '4px');
  document.querySelector('.wave-bars').append(bar);
  return bar;
});
const labels = {
  idle: 'Record your voice', requesting: 'Cancel', recording: 'Stop & listen',
  processing: 'Finishing…', playing: 'Record again', paused: 'Record again',
  ready: 'Record again', error: 'Try again', unsupported: 'Recording unavailable'
};
const instructions = {
  idle: 'A thought. A sentence.\nA little better the next time.',
  requesting: 'Your microphone.\nOnly with your permission.',
  recording: 'Go on. Say something.\nPress again to hear it back.',
  processing: 'A moment for your voice.',
  playing: 'Sound familiar?\nThat’s you.',
  paused: 'Take your time.\nYour voice is right here.',
  ready: 'A little clearer.\nTry it once more?',
  error: 'Let’s try that again.',
  unsupported: 'A little practice,\nright on your Mac.'
};
function render({ state, message, elapsed, progress: value, levels, hasClip }) {
  preview.dataset.state = state;
  const label = labels[state];
  if (button.textContent !== label) button.textContent = label;
  button.disabled = state === 'processing' || state === 'unsupported';
  button.setAttribute('aria-pressed', String(state === 'recording'));
  clearButton.hidden = !hasClip && state !== 'recording';
  clearButton.textContent = state === 'recording' ? 'Discard take' : 'Clear recording';
  playButton.disabled = replayButton.disabled = !hasClip;
  playButton.setAttribute('aria-label', state === 'playing' ? 'Pause recording' : 'Play recording');
  playButton.querySelector('span').textContent = state === 'playing' ? 'Ⅱ' : '▶';
  const seconds = Math.floor(elapsed);
  time.textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  if (status.textContent !== message) status.textContent = message;
  if (instruction.textContent !== instructions[state]) instruction.textContent = instructions[state];
  fill.style.width = `${value * 100}%`;
  progress.setAttribute('aria-valuenow', String(Math.round(value * 100)));
  levels.forEach((level, index) => bars[index].style.setProperty('--bar-height', `${4 + level * 43}px`));
}
const demo = new VoiceDemo({ onChange: render });
button.addEventListener('click', () => {
  if (demo.state === 'requesting') demo.cancel('Preview cancelled. Dismiss any open permission prompt, then try again.');
  else if (demo.state === 'recording') demo.stop();
  else void demo.start();
});
clearButton.addEventListener('click', () => demo.cancel());
playButton.addEventListener('click', () => {
  if (demo.state === 'playing') demo.pause();
  else void demo.play();
});
replayButton.addEventListener('click', () => { void demo.play(true); });
function leavePreview() {
  if (demo.state !== 'idle' && demo.state !== 'unsupported') demo.cancel('Preview cleared when you left the tab. Press record to try again.');
}
document.addEventListener('visibilitychange', () => { if (document.hidden) leavePreview(); });
window.addEventListener('pagehide', leavePreview);
document.querySelectorAll('a[href="#install-note"]').forEach(link => link.addEventListener('click', () => { document.querySelector('#install-note').open = true; }));
function openLinkedNote() { if (location.hash === '#install-note') document.querySelector('#install-note').open = true; }
window.addEventListener('hashchange', openLinkedNote);
openLinkedNote();
