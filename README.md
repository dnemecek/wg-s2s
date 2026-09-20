# wg-s2s

Správa více WireGuard site-to-site tunelů na UniFi Cloud Gateway (UCG) bez NAT.
Protistrana je typicky pfSense, ale funguje s libovolným WireGuard peerem.

## Proč ne WireGuard klient v UniFi GUI

UniFi WG Client přidává na provoz tunelu masquerade (NAT). Protistrana pak vidí
jen IP gateway, ne původní zdrojovou IP klienta v LAN. Ruční `wg-quick` tunel
NAT nepřidává a původní source IP prochází.

## Obsah

| Soubor | Účel |
|---|---|
| `wg-s2s.sh` | správa tunelů (`new`, `start`, `stop`, `restart`, `status`, `delete`, `list`) |
| `wg-s2s@.service` | systemd šablona pro autostart tunelu (`wg-s2s@<nazev>`) |
| `install.sh` | instalace na UCG do `/root/wg-s2s/` + symlink `/usr/local/bin/wg-s2s` |

## Požadavky

- UniFi OS s WireGuard kernel modulem a `wireguard-tools` (`wg`, `wg-quick`)
- přístup root přes SSH

## Instalace

```bash
scp wg-s2s.sh wg-s2s@.service install.sh root@<ucg>:/root/
ssh root@<ucg>
cd /root && ./install.sh
```

## Použití

```bash
wg-s2s new <nazev> \
  --endpoint <pfsense-wan-ip>:51820 \
  --remote-pubkey "<pfsense-public-key>" \
  --tunnel-ip 172.16.220.4/29 \
  --remote-subnets "192.168.220.0/24" \
  --psk-gen

wg-s2s status
wg-s2s restart <nazev>
```

Po `new` skript vypíše veřejný klíč UCG a PSK pro nastavení peeru na pfSense.
UCG je initiator (`PersistentKeepalive = 25`), pfSense listener.

## Struktura na UCG

```
/root/wg-s2s/
├── wg-s2s.sh
├── tunnels/<nazev>.conf   # wg-quick konfigurace, 0600
└── keys/<nazev>.{key,pub,psk}
```

`AllowedIPs` na obou stranách musí obsahovat všechny subnety, ze kterých mohou
přes tunel přicházet pakety (další LAN, OpenVPN pool, jiné S2S sítě). Při přidání
sítě uprav `AllowedIPs` na UCG i peer na pfSense, routing a firewall.

## Licence

MIT, viz `LICENSE`.
