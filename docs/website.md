# Website

https://musaamir.github.io/Parrot/

The static site lives in `docs/index.html`, `docs/styles.css`, `docs/app.js`, `docs/voice-demo.js`, and `docs/assets/`. It shares PodsBar’s palette, typography, spacing, and 76/64 px header heights. The browser preview requests the visitor’s microphone only after a button press, records up to 30 seconds, then plays the take back locally. No audio is uploaded, persisted, or sent to analytics. Leaving the tab, clearing, or starting a new take releases the old recording. The microphone stops before playback. Native autoplay restrictions fall back to an explicit Play button.

Preview from the repository root:

```sh
python3 -m http.server 4174 --directory docs
```

Push changes to the site files on `main` to deploy through `.github/workflows/pages.yml`. A manual **Run workflow** is also available in GitHub Actions. Repository Pages settings use **GitHub Actions** as the publishing source. Site JavaScript, HTML, CSS, assets, and preview tests trigger deployment; release documentation changes do not. The Pages workflow runs the preview regression tests before publishing.

The deployment uploads `docs/` as static files. No framework, build step, external font, analytics, paid host, or additional secret is needed. Update version-specific downloads and installation notes with each app release.

The pre-existing untracked `site/` directory is separate and is not part of the published site.

Preview tests: `node --test Tests/Website/*.test.mjs`. `Tests/Website/recorder-smoke.html` uses a generated tone, not the microphone, to exercise the browser’s actual recording and playback APIs. It is not deployed. Browser/OS microphone approval and physical audio input still need a visitor’s own trial.
