/** One temporary take. The microphone, timers, audio graph, and blob URL are
 * released on cancellation, replacement, or page exit. No audio leaves here. */
export class VoiceDemo {
  constructor({ platform = createBrowserPlatform(), onChange = () => {}, maxDuration = 30000, maxBytes = 4 * 1024 * 1024 } = {}) {
    this.platform = platform;
    this.onChange = onChange;
    this.maxDuration = maxDuration;
    this.maxBytes = maxBytes;
    this.generation = 0;
    this.playAttempt = 0;
    this.session = null;
    this.audio = null;
    this.url = null;
    this.elapsed = 0;
    this.progress = 0;
    this.levels = Array(18).fill(0);
    this.state = platform.supported ? 'idle' : 'unsupported';
    this.message = platform.supported
      ? 'Press record, allow microphone access, then speak. Press again to listen.'
      : 'Microphone recording isn’t available here. Try a current browser over HTTPS, or download Parrot.';
    this.notify();
  }

  notify() {
    this.onChange({ state: this.state, message: this.message, elapsed: this.elapsed,
      progress: this.progress, levels: [...this.levels], hasClip: Boolean(this.audio) });
  }

  setState(state, message) { this.state = state; this.message = message; this.notify(); }

  async start() {
    if (!this.platform.supported || this.state === 'requesting' || this.state === 'recording' || this.state === 'processing') return;
    this.cancel('', false);
    const generation = this.generation;
    this.setState('requesting', 'Allow microphone access in your browser. You can cancel at any time.');
    try {
      const stream = await this.platform.requestStream();
      if (generation !== this.generation) { stream.getTracks().forEach(track => track.stop()); return; }
      const session = { stream, recorder: null, chunks: [], bytes: 0, startedAt: this.platform.now(), autoPlay: false };
      this.session = session;
      const recorder = this.platform.createRecorder(stream);
      session.recorder = recorder;
      recorder.ondataavailable = event => {
        if (this.session !== session || !event.data?.size) return;
        session.bytes += event.data.size;
        if (session.bytes > this.maxBytes) { this.fail('This take reached the preview’s size limit. Please try a shorter recording.'); return; }
        session.chunks.push(event.data);
      };
      recorder.onerror = () => {
        if (this.session === session) this.fail('Recording was interrupted. Check your microphone, then try again.');
      };
      recorder.onstop = () => this.finish(session);
      stream.getTracks().forEach(track => {
        track.onended = () => {
          if (this.session !== session || this.state !== 'recording') return;
          this.stop(false);
        };
      });
      recorder.start(250);
      // The optional meter never connects the mic to the speakers.
      try { session.meter = this.platform.createMeter(stream); } catch { /* Recording still works without Web Audio. */ }
      session.tick = this.platform.setInterval(() => {
        if (this.session !== session || this.state !== 'recording') return;
        this.elapsed = Math.max(0, this.platform.now() - session.startedAt) / 1000;
        const level = session.meter?.read() ?? 0;
        this.levels.shift();
        this.levels.push(Number.isFinite(level) ? Math.max(0, Math.min(1, level)) : 0);
        this.notify();
        if (this.elapsed * 1000 >= this.maxDuration) this.stop();
      }, 100);
      session.limit = this.platform.setTimeout(() => this.stop(), this.maxDuration);
      this.setState('recording', 'Recording… Speak, then press Stop & listen. Maximum 30 seconds.');
    } catch (error) {
      if (generation !== this.generation) return;
      this.fail(permissionMessage(error));
    }
  }

  stop(autoPlay = true) {
    const session = this.session;
    if (!session || this.state !== 'recording') return;
    session.autoPlay = autoPlay;
    this.elapsed = Math.max(0, this.platform.now() - session.startedAt) / 1000;
    this.setState('processing', 'Finishing your recording…');
    try {
      if (session.recorder.state !== 'inactive') session.recorder.stop();
      // Tracks stop immediately; final encoder data arrives before onstop.
      this.releaseCapture(session);
    } catch { this.fail('The recording couldn’t finish. Please try again.'); }
  }

  finish(session) {
    if (this.session !== session) return;
    this.releaseCapture(session);
    session.recorder.ondataavailable = session.recorder.onstop = session.recorder.onerror = null;
    this.session = null;
    const blob = new Blob(session.chunks, { type: session.recorder.mimeType || session.chunks[0]?.type || '' });
    session.chunks = [];
    if (!blob.size) { this.fail('No audio was captured. Try speaking for a little longer.'); return; }
    try {
      this.url = this.platform.createURL(blob);
      const audio = this.platform.createAudio(this.url);
      this.audio = audio;
      const current = () => this.audio === audio;
      audio.ontimeupdate = () => {
        if (!current()) return;
        const duration = Number.isFinite(audio.duration) && audio.duration > 0 ? audio.duration : this.elapsed;
        this.progress = duration > 0 ? Math.max(0, Math.min(1, audio.currentTime / duration)) : 0;
        this.notify();
      };
      audio.onended = () => {
        if (!current()) return;
        this.playAttempt++;
        this.progress = 1;
        this.setState('ready', 'That’s you. Replay your take, record another, or clear it.');
      };
      audio.onerror = () => {
        if (current()) this.fail('Your browser couldn’t play this take. Please try recording again.');
      };
      this.setState('ready', session.autoPlay ? 'Your recording is ready.' : 'The microphone disconnected. Press Play to hear your take.');
      if (session.autoPlay) void this.play(true);
    } catch { this.fail('Your browser couldn’t prepare playback. Please try again.'); }
  }

  async play(restart = false) {
    const audio = this.audio;
    if (!audio || this.session) return;
    const attempt = ++this.playAttempt;
    if (restart || this.progress >= 1) { audio.currentTime = 0; this.progress = 0; }
    this.setState('playing', 'Playing back your voice. The microphone is off.');
    try {
      await audio.play();
      if (this.audio !== audio) audio.pause();
    } catch (error) {
      if (this.audio !== audio || attempt !== this.playAttempt) return;
      this.setState('ready', error?.name === 'NotAllowedError'
        ? 'Your recording is ready. Press Play to listen.'
        : 'Playback couldn’t start. Press Play to try again, or record another take.');
    }
  }

  pause() {
    if (!this.audio) return;
    this.playAttempt++;
    this.audio.pause();
    this.setState('paused', 'Paused. Press Play to continue, or record another take.');
  }

  releaseCapture(session) {
    this.platform.clearInterval(session.tick);
    this.platform.clearTimeout(session.limit);
    session.meter?.close();
    session.meter = null;
    session.stream.getTracks().forEach(track => { track.onended = null; track.stop(); });
  }

  cancel(message = 'Recording cleared. Press record to try again.', notify = true) {
    this.generation++;
    this.playAttempt++;
    const session = this.session;
    this.session = null;
    if (session) {
      const recorder = session.recorder;
      if (recorder) {
        recorder.ondataavailable = recorder.onstop = recorder.onerror = null;
        try { if (recorder.state !== 'inactive') recorder.stop(); } catch { /* Cleanup still releases tracks. */ }
      }
      this.releaseCapture(session);
      session.chunks = [];
    }
    const audio = this.audio;
    this.audio = null;
    if (audio) {
      audio.ontimeupdate = audio.onended = audio.onerror = null;
      audio.pause();
      audio.removeAttribute('src');
      audio.load();
    }
    if (this.url) { this.platform.revokeURL(this.url); this.url = null; }
    this.elapsed = this.progress = 0;
    this.levels.fill(0);
    this.state = this.platform.supported ? 'idle' : 'unsupported';
    this.message = message;
    if (notify) this.notify();
  }

  fail(message) { this.cancel('', false); this.setState('error', message); }
}

function permissionMessage(error) {
  switch (error?.name) {
    case 'NotAllowedError': case 'SecurityError':
      return 'Microphone access was blocked. Allow it in your browser’s site settings, then try again.';
    case 'NotFoundError': return 'No microphone was found. Connect one and try again.';
    case 'NotReadableError': return 'Your microphone is unavailable. Check whether another app is using it, then try again.';
    default: return 'The microphone couldn’t start. Check your browser permissions and try again.';
  }
}

export function createBrowserPlatform() {
  return {
    supported: Boolean(globalThis.isSecureContext && globalThis.navigator?.mediaDevices?.getUserMedia && globalThis.MediaRecorder),
    requestStream: () => navigator.mediaDevices.getUserMedia({ audio: true, video: false }),
    createRecorder: stream => {
      const types = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/webm', 'audio/ogg;codecs=opus'];
      const mimeType = types.find(type => MediaRecorder.isTypeSupported?.(type));
      return new MediaRecorder(stream, mimeType ? { mimeType, audioBitsPerSecond: 64000 } : undefined);
    },
    createMeter: stream => {
      const AudioContext = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (!AudioContext) return null;
      const context = new AudioContext();
      let source;
      try {
        source = context.createMediaStreamSource(stream);
        const analyser = context.createAnalyser();
        analyser.fftSize = 256;
        source.connect(analyser);
        const data = new Uint8Array(analyser.fftSize);
        void context.resume().catch(() => {});
        return {
          read() {
            analyser.getByteTimeDomainData(data);
            let sum = 0;
            for (const value of data) sum += ((value - 128) / 128) ** 2;
            return Math.min(1, Math.sqrt(sum / data.length) * 4);
          },
          close() { source.disconnect(); if (context.state !== 'closed') void context.close().catch(() => {}); }
        };
      } catch (error) {
        source?.disconnect();
        if (context.state !== 'closed') void context.close().catch(() => {});
        throw error;
      }
    },
    createAudio: url => { const audio = new Audio(url); audio.preload = 'auto'; return audio; },
    createURL: blob => URL.createObjectURL(blob),
    revokeURL: url => URL.revokeObjectURL(url),
    now: () => performance.now(),
    setInterval: (fn, ms) => setInterval(fn, ms), clearInterval: id => clearInterval(id),
    setTimeout: (fn, ms) => setTimeout(fn, ms), clearTimeout: id => clearTimeout(id)
  };
}
