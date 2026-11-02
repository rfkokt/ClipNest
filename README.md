# ClipNest

Clipboard manager menu bar untuk macOS, pengganti CopyClip dengan fitur tambahan.

- Popup **⇧⌘V** dengan tab Semua / Teks / Gambar / File / Pin / Snippet
- Pencarian fuzzy, termasuk teks di dalam gambar (OCR)
- Klik item untuk langsung paste; ↩ paste, ⇧↩ teks polos, ⌘1–9 paste cepat, ⌘P pin, ⌘⌫ hapus
- Ubah teks sebelum paste (UPPER/lower, rapikan JSON, URL/Base64, dll.)
- Privasi: abaikan password manager & data rahasia, jeda perekaman, kecualikan app, hapus otomatis
- Paste gambar ke terminal (Ghostty, iTerm2, dll.) memakai Ctrl+V agar terbaca oleh Claude Code

## Build

Butuh Swift toolchain (Command Line Tools cukup), macOS 13+.

```bash
./build.sh   # build, tanda tangan, pasang ke ~/Applications/ClipNest.app
```

Auto-paste butuh izin Aksesibilitas (System Settings → Privacy & Security → Accessibility).
