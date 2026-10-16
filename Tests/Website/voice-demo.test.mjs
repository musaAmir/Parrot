import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
// Load the standalone browser ES module without adding a Node package or dependencies.
const source = await readFile(new URL('../../docs/voice-demo.js', import.meta.url), 'utf8');
const { VoiceDemo } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const flush = async () => { await Promise.resolve(); await Promise.resolve(); await Promise.resolve(); };
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
function stream() {
  const track = { readyState: 'live', onended: null, stops: 0, stop() { if (this.readyState === 'live') this.stops++; this.readyState = 'ended'; } };
  return { track, getTracks: () => [track] };
}
function harness(options = {}) {
  let clock = 0, timerID = 0;
  const timers = new Map(), streams = [], recorders = [], audios = [], urls = [], revoked = [], meters = [], changes = [];
  let requests = 0;
  const platform = {
    supported: options.supported ?? true,
    requestStream() {
      requests++;
      if (options.requestError) return Promise.reject(options.requestError);
      if (options.permission) return options.permission.promise;
      const next = stream(); streams.push(next); return Promise.resolve(next);
    },
    createRecorder(input) {
      if (options.recorderError) throw new Error('Recorder unavailable');
      const recorder = {
        state: 'inactive', mimeType: 'audio/webm', stream: input,
        start() { this.state = 'recording'; },
        stop() {
          this.state = 'inactive';
          const data = this.ondataavailable, stop = this.onstop;
          queueMicrotask(() => { data?.({ data: options.blob ?? new Blob(['recorded audio'], { type: 'audio/webm' }) }); stop?.(); });
        }
      };
      recorders.push(recorder); return recorder;
    },
    createMeter() {
      if (options.meterError) throw new Error('Web Audio unavailable');
      const meter = { closed: 0, read: () => 0.4, close() { this.closed++; } };
      meters.push(meter); return meter;
    },
    createAudio(url) {
      const audio = {
        src: url, currentTime: 0, duration: 2, plays: 0, pauses: 0, loads: 0, error: options.playError,
        play() { this.plays++; return this.error ? Promise.reject(this.error) : options.playPromise?.promise ?? Promise.resolve(); },
        pause() { this.pauses++; }, removeAttribute() { this.src = ''; }, load() { this.loads++; }
      };
      audios.push(audio); return audio;
    },
    createURL(blob) { const url = `blob:take-${urls.length}`; urls.push({ url, blob }); return url; },
    revokeURL(url) { revoked.push(url); }, now: () => clock,
    setInterval(fn, ms) { const id = ++timerID; timers.set(id, { fn, at: clock + ms, interval: ms }); return id; },
    clearInterval(id) { timers.delete(id); },
    setTimeout(fn, ms) { const id = ++timerID; timers.set(id, { fn, at: clock + ms }); return id; },
    clearTimeout(id) { timers.delete(id); }
  };
  const demo = new VoiceDemo({ platform, onChange: state => changes.push(state), ...options.limits });
  function advance(ms) {
    const end = clock + ms;
    while (true) {
      const next = [...timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!next) break;
      const [id, timer] = next; clock = timer.at;
      if (timer.interval) timer.at += timer.interval; else timers.delete(id);
      timer.fn();
    }
    clock = end;
  }
  return { demo, platform, options, streams, recorders, audios, urls, revoked, meters, timers, changes, advance, get requests() { return requests; } };
}
async function take(h) { await h.demo.start(); h.advance(500); h.demo.stop(); await flush(); }

test('does not request microphone access or allocate timers on page load', () => {
  const h = harness(); assert.equal(h.requests, 0); assert.equal(h.timers.size, 0); assert.equal(h.demo.state, 'idle');
});
test('record, stop, and playback use the captured blob, with mic released before playback', async () => {
  const h = harness(); await h.demo.start(); h.advance(600);
  assert.equal(h.demo.state, 'recording'); assert.equal(h.streams[0].track.readyState, 'live');
  h.demo.stop(); assert.equal(h.streams[0].track.readyState, 'ended'); assert.equal(h.timers.size, 0);
  await flush(); assert.equal(h.demo.state, 'playing'); assert.equal(h.audios[0].plays, 1);
  assert.equal(await h.urls[0].blob.text(), 'recorded audio');
  assert.equal(h.meters[0].closed, 1);
  h.audios[0].onended(); assert.equal(h.demo.state, 'ready'); assert.equal(h.demo.progress, 1); assert.equal(h.timers.size, 0);
});
test('permission denial provides an actionable error and can be retried', async () => {
  const h = harness({ requestError: { name: 'NotAllowedError' } }); await h.demo.start();
  assert.equal(h.demo.state, 'error'); assert.match(h.demo.message, /site settings/); assert.equal(h.timers.size, 0);
  h.options.requestError = null; await h.demo.start(); assert.equal(h.demo.state, 'recording'); h.demo.cancel();
});
test('a microphone granted after cancellation is immediately stopped', async () => {
  const permission = deferred(), h = harness({ permission });
  const starting = h.demo.start(); assert.equal(h.demo.state, 'requesting'); h.demo.cancel();
  const late = stream(); permission.resolve(late); await starting;
  assert.equal(late.track.readyState, 'ended'); assert.equal(h.recorders.length, 0); assert.equal(h.demo.state, 'idle');
});
test('leaving or cancelling during final encoding cannot start stale playback', async () => {
  const h = harness(); await h.demo.start(); h.demo.stop(); h.demo.cancel(); await flush();
  assert.equal(h.demo.state, 'idle'); assert.equal(h.audios.length, 0); assert.equal(h.timers.size, 0);
});
test('clear during recording discards encoder callbacks and releases every capture resource', async () => {
  const h = harness(); await h.demo.start(); h.demo.cancel(); await flush();
  assert.equal(h.streams[0].track.stops, 1); assert.equal(h.meters[0].closed, 1); assert.equal(h.urls.length, 0); assert.equal(h.timers.size, 0);
});
test('record again removes the previous audio and revokes its blob URL', async () => {
  const h = harness(); await take(h); const oldAudio = h.audios[0]; await h.demo.start();
  assert.equal(oldAudio.src, ''); assert.equal(oldAudio.loads, 1); assert.ok(oldAudio.pauses > 0);
  assert.deepEqual(h.revoked, ['blob:take-0']); assert.equal(h.demo.state, 'recording'); h.demo.cancel();
});
test('clear during playback forgets the take and leaves no running resources', async () => {
  const h = harness(); await take(h); h.demo.cancel();
  assert.equal(h.demo.audio, null); assert.equal(h.demo.url, null); assert.deepEqual(h.revoked, ['blob:take-0']); assert.equal(h.timers.size, 0);
});
test('blocked automatic playback preserves the clip for an explicit Play press', async () => {
  const h = harness({ playError: { name: 'NotAllowedError' } }); await take(h);
  assert.equal(h.demo.state, 'ready'); assert.match(h.demo.message, /Press Play/); assert.ok(h.demo.audio);
  h.audios[0].error = null; await h.demo.play(); assert.equal(h.demo.state, 'playing');
});
test('a late playback rejection cannot overwrite cancellation state', async () => {
  const playPromise = deferred(), h = harness({ playPromise }); await take(h); h.demo.cancel();
  playPromise.reject({ name: 'NotAllowedError' }); await flush(); assert.equal(h.demo.state, 'idle'); assert.equal(h.demo.audio, null);
});
test('a late playback resolution cannot restart a cleared take', async () => {
  const playPromise = deferred(), h = harness({ playPromise }); await take(h); h.demo.cancel();
  playPromise.resolve(); await flush(); assert.ok(h.audios[0].pauses >= 2); assert.equal(h.demo.state, 'idle');
});
test('pause and replay keep the microphone off and replay starts at zero', async () => {
  const h = harness(); await take(h); h.audios[0].currentTime = 1; h.demo.pause();
  assert.equal(h.demo.state, 'paused'); await h.demo.play(); assert.equal(h.audios[0].currentTime, 1);
  await h.demo.play(true); assert.equal(h.audios[0].currentTime, 0); assert.equal(h.streams[0].track.readyState, 'ended');
});
test('duration cap stops recording and plays the bounded take', async () => {
  const h = harness(); await h.demo.start(); h.advance(30000); await flush();
  assert.equal(h.demo.state, 'playing'); assert.equal(h.streams[0].track.readyState, 'ended'); assert.equal(h.timers.size, 0);
});
test('size cap discards excessive data and turns off the microphone', async () => {
  const h = harness({ limits: { maxBytes: 4 } }); await h.demo.start();
  h.recorders[0].ondataavailable({ data: new Blob(['12345']) }); await flush();
  assert.equal(h.demo.state, 'error'); assert.equal(h.streams[0].track.readyState, 'ended'); assert.equal(h.urls.length, 0); assert.equal(h.timers.size, 0);
});
test('empty recordings recover without creating an audio URL', async () => {
  const h = harness({ blob: new Blob([]) }); await take(h);
  assert.equal(h.demo.state, 'error'); assert.match(h.demo.message, /No audio/); assert.equal(h.urls.length, 0);
});
test('recorder construction failure releases an already granted microphone', async () => {
  const h = harness({ recorderError: true }); await h.demo.start();
  assert.equal(h.demo.state, 'error'); assert.equal(h.streams[0].track.readyState, 'ended'); assert.equal(h.timers.size, 0);
});
test('recording errors cannot cause automatic playback', async () => {
  const h = harness(); await h.demo.start(); h.recorders[0].onerror(); await flush();
  assert.equal(h.demo.state, 'error'); assert.equal(h.audios.length, 0); assert.equal(h.streams[0].track.readyState, 'ended');
});
test('recording remains usable when the optional live meter cannot start', async () => {
  const h = harness({ meterError: true }); await take(h); assert.equal(h.demo.state, 'playing'); assert.equal(h.streams[0].track.readyState, 'ended');
});
test('a disconnected microphone produces a playable take without unexpected autoplay', async () => {
  const h = harness(); await h.demo.start(); h.streams[0].track.onended(); await flush();
  assert.equal(h.demo.state, 'ready'); assert.equal(h.audios[0].plays, 0); assert.match(h.demo.message, /disconnected/);
});
test('unsupported browsers never request a microphone', async () => {
  const h = harness({ supported: false }); await h.demo.start(); assert.equal(h.demo.state, 'unsupported'); assert.equal(h.requests, 0);
});
test('progress stays finite for recordings whose browser duration is Infinity', async () => {
  const h = harness(); await take(h); h.audios[0].duration = Infinity; h.audios[0].currentTime = 0.25; h.audios[0].ontimeupdate();
  assert.equal(h.demo.progress, 0.5);
});

test('an older play promise cannot pause a newer resume of the same take', async () => {
  const first = deferred(), second = deferred(), h = harness({ playPromise: first });
  await take(h); h.demo.pause();
  const paused = h.audios[0].pauses;
  h.audios[0].play = () => second.promise;
  const resumed = h.demo.play();
  first.resolve(); await flush(); assert.equal(h.audios[0].pauses, paused);
  second.resolve(); await resumed; assert.equal(h.demo.state, 'playing');
});
