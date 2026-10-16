# Website

https://musaamir.github.io/Parrot/

The static site lives in `docs/index.html`, `docs/styles.css`, `docs/app.js`, and `docs/assets/`. It shares PodsBar’s palette, typography, spacing, and 76/64 px header heights. The browser demo is an illustration: it records no microphone input and plays no sound.

Preview from the repository root:

```sh
python3 -m http.server 4174 --directory docs
```

Push changes to the site files on `main` to deploy through `.github/workflows/pages.yml`. A manual **Run workflow** is also available in GitHub Actions. Repository Pages settings use **GitHub Actions** as the publishing source. Only the four site paths above trigger automatic deployment; release documentation changes do not.

The deployment uploads `docs/` as static files. No framework, build step, external font, analytics, paid host, or additional secret is needed. Update version-specific downloads and installation notes with each app release.

The pre-existing untracked `site/` directory is separate and is not part of the published site.
