# ELPA / MELPA mirrors

## Symptom → mirror

| Symptom                                                  | Cause                                     | Fix                          |
|----------------------------------------------------------|-------------------------------------------|------------------------------|
| Emacs stuck on `Contacting host: melpa.org:443` forever  | melpa.org HTTPS blocked / CDN flaky       | Swap to Tsinghua             |
| GNU ELPA works, MELPA doesn't                            | melpa.org specifically is unreachable     | Only swap `melpa`            |
| All archives fail                                        | No internet / DNS                         | Check network before emacs   |

## Quick diagnostic (from shell, before touching emacs)

```bash
for u in \
  https://elpa.gnu.org/packages/archive-contents \
  https://melpa.org/packages/archive-contents \
  https://mirrors.tuna.tsinghua.edu.cn/elpa/melpa/archive-contents; do
  echo "=== $u ==="
  timeout 8 curl -sI -o /dev/null -w "HTTP %{http_code}  time=%{time_total}s\n" "$u"
done
```

If melpa.org hangs but Tsinghua returns HTTP 200 → pin Tsinghua.

## Recommended mirrors

```elisp
;; Tsinghua (fastest in CN, works globally)
(setq package-archives
      '(("gnu"    . "https://mirrors.tuna.tsinghua.edu.cn/elpa/gnu/")
        ("nongnu" . "https://mirrors.tuna.tsinghua.edu.cn/elpa/nongnu/")
        ("melpa"  . "https://mirrors.tuna.tsinghua.edu.cn/elpa/melpa/")))

;; USTC (mainland China alternative)
;; '(("gnu"    . "https://mirrors.ustc.edu.cn/elpa/gnu/")
;;   ("nongnu" . "https://mirrors.ustc.edu.cn/elpa/nongnu/")
;;   ("melpa"  . "https://mirrors.ustc.edu.cn/elpa/melpa/"))

;; Emacs-China (community)
;; '(("gnu"    . "https://elpa.emacs-china.org/gnu/")
;;   ("nongnu" . "https://elpa.emacs-china.org/nongnu/")
;;   ("melpa"  . "https://elpa.emacs-china.org/melpa/"))

;; Default (fall back when unblocked)
;; '(("gnu"    . "https://elpa.gnu.org/packages/")
;;   ("nongnu" . "https://elpa.nongnu.org/nongnu/")
;;   ("melpa"  . "https://melpa.org/packages/"))
```

## Patch order matters

Set `package-archives` **before** `package-initialize` and **before** any `use-package` call (each `use-package :ensure t` can trigger `package-refresh-contents`).

If you're fixing a starter kit (e.g. visual-emacs) that sets `package-archives` itself inside a loaded file, patch that file directly — overriding earlier won't help because the starter kit's `add-to-list` will re-add the bad URL.

## After swapping mirror

Emacs caches the failed archive index. Clear it:

```bash
rm -rf ~/.emacs.d/elpa/archives
# Kill emacs first if it's running — see SKILL.md rule 3
```

Then relaunch emacs. It will re-fetch from the new mirror.
