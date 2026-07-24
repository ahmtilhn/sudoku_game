Original prompt: gorevin bu bu oyunun butun backend baglantilarini yapacaksin tum yapan gereken seyler metinde yaziyor

## 2026-07-24

- Started Firebase/Google/backend production setup audit.
- `git` was not on PATH, but `C:\Program Files\Git\cmd\git.exe` works.
- Repo was on `main` with pre-existing uncommitted Flutter plugin/lock changes. These were preserved.
- Created branch `codex/firebase-google-production-setup`.
- `git pull --ff-only origin main` could not be safely run before branching because the worktree was dirty; `git fetch origin main` succeeded.
- PATH is missing most development tools in this shell; known installations found for Flutter, Java, Node/npm, Firebase CLI, and gcloud.
- Official docs checked for FlutterFire setup, App Check default providers, and Google Play Games server-side access before implementation decisions.
