# Změny a nasazení nové verze

Větev `main` je vždy poslední verze, která běží na gateway a je ověřená.
Změny se dělají na pracovní větvi a do `main` jdou přes pull request.

## Cyklus

1. **Větev** z aktuálního `main`: `<iniciály>-<YYMMDD>/<typ>-<popis>`,
   např. `DN-260920/feat-import-wg-s2s`. Typ je `feat`, `fix`, `docs`,
   `refactor`, `chore`.
2. **Commit** ve tvaru `<komponenta>: <věcný popis>`, česky, přítomný čas,
   první řádek do 72 znaků. Soubory přidávej jmenovitě, ne `git add .`.
3. **Nasazení z větve** na gateway:

   ```bash
   ./deploy.sh <ucg_ip>
   ssh root@<ucg_ip> 'wg-s2s restart all && wg-s2s status'
   ```

   `deploy.sh` přepíše skript a systemd unit, existující tunely a klíče
   nechá. Restart tunelů je oddělený záměrně, výpadek řídíš ty.
4. **Ověření**: handshake do pár sekund ve `wg-s2s status`, `tcpdump` na
   pfSense ukazuje původní source IP.
5. **Rollback** při problému: `git checkout main && ./deploy.sh <ucg_ip>`
   a znovu restart tunelů.
6. **Pull request** do `main`, po merge tag `vX.Y.Z` na `main` a smazání
   větve. Tag znamená „tohle běží na gateway".

## Více gateway

`deploy.sh` bere cíl jako `[user@]host`, bez uživatele doplní `root`.
Na každou gateway jedno volání. Seznam adres není v repu, drž ho mimo git.

## Co drží tunely při upgradu firmware

Konfigurace, klíče i systemd unit žijí v `/root/wg-s2s/` a
`/etc/systemd/system/`. Zda je upgrade firmware UCG zachová, není ověřeno.
Po upgradu zkontroluj `wg-s2s list`; při ztrátě spusť `deploy.sh` a tunely
založ znovu přes `wg-s2s new` (peer na pfSense pak dostane nový klíč).
