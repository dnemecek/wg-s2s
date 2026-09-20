# Roadmap

- [ ] `start`/`stop` přes `systemctl`, pokud existuje unit `wg-s2s@<nazev>`, aby stav systemd a skriptu nedivergoval
- [ ] Validace názvu tunelu (max 15 znaků, jen `[A-Za-z0-9_-]`), název je zároveň jméno interface
- [ ] `--psk-file` jako alternativa k `--psk` v argumentu
- [ ] Příkaz `wg-s2s version`
- [ ] Ověřit chování po upgradu firmware UCG (přežití `/root/wg-s2s` a systemd unit)
