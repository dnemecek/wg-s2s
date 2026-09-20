# Runbook: WireGuard S2S mezi UCG a pfSense

Postup zprovoznění jednoho tunelu od instalace skriptu po ověření provozu.
Hodnoty v `< >` doplň podle konkrétní lokality.

## Architektura

```
┌─────────────────────┐         WireGuard          ┌─────────────────────┐
│   UCG (lokalita)    │◄──────────────────────────►│   pfSense           │
│   <ucg_lan>/24      │      <tunnel_net>/29       │   <remote_lan>/24   │
│   Tunnel: .3 / .4   │                            │   Tunnel: .1        │
└─────────────────────┘                            └─────────────────────┘
```

UCG je initiator (`PersistentKeepalive = 25`), pfSense listener. Tunelový
subnet je /29, pfSense drží .1, každá UCG dostane vlastní adresu v rozsahu.

## 1. Instalace skriptu na UCG

Z pracovní stanice:

```bash
./deploy.sh <ucg_ip>
```

Nebo ručně:

```bash
scp wg-s2s.sh wg-s2s@.service install.sh root@<ucg_ip>:/root/
ssh root@<ucg_ip> 'cd /root && chmod +x install.sh && ./install.sh'
```

Prerekvizity: UCG-Max/Ultra s SSH, WireGuard modul a `wireguard-tools` jsou
součástí firmware. Výsledná struktura:

```
/root/wg-s2s/
├── wg-s2s.sh
├── tunnels/<nazev>.conf
└── keys/<nazev>.{key,pub,psk}
```

## 2. Tunel na pfSense (jednou)

**VPN → WireGuard → Tunnels → Add**

| Parametr | Hodnota |
|---|---|
| Enable | ano |
| Description | WG VPN |
| Listen Port | 51820 |
| Interface Keys | Generate |

Na WAN povol UDP 51820. Veřejný klíč tunelu použiješ v kroku 3.

## 3. Vytvoření tunelu na UCG

```bash
wg-s2s new <nazev> \
  --endpoint <pfsense_wan_ip>:51820 \
  --remote-pubkey "<pfsense_public_key>" \
  --tunnel-ip <ucg_tunnel_ip>/29 \
  --remote-subnets "<remote_lan>/24" \
  --psk-gen
```

Skript vygeneruje klíče, zapíše konfiguraci, tunel nastartuje, povolí
autostart přes `wg-s2s@<nazev>` a vypíše **Public Key** a **PSK** pro peer
na pfSense.

## 4. Peer na pfSense

**VPN → WireGuard → Peers → Add**

| Parametr | Hodnota |
|---|---|
| Tunnel | tun_wg0 |
| Description | UCG <lokalita> |
| Public Key | z výstupu `wg-s2s new` |
| Pre-shared Key | z výstupu `wg-s2s new` |
| Allowed IPs | `<ucg_tunnel_ip>/32, <ucg_lan>/24` |
| Dynamic Endpoint | ano |

**Interfaces → Assignments**: přidej `tun_wg0`, pojmenuj `WG_VPN`, Enable,
IPv4 Configuration Type: None.

**System → Routing → Gateways → Add**

| Parametr | Hodnota |
|---|---|
| Interface | WG_VPN |
| Name | WG_<LOKALITA>_GW |
| Gateway | `<ucg_tunnel_ip>` |
| Disable Gateway Monitoring | ano |

**System → Routing → Static Routes → Add**

| Parametr | Hodnota |
|---|---|
| Destination Network | `<ucg_lan>/24` |
| Gateway | WG_<LOKALITA>_GW |

**Firewall → Rules → WG_VPN**: Pass, Any, Source `<ucg_lan>` net, Destination Any.

## 5. AllowedIPs, nejčastější zdroj problémů

`AllowedIPs` není jen routing. Pro WireGuard kernel je to obousměrný
cryptokey routing filtr:

| Směr | Význam |
|---|---|
| Outbound | Pro tyto destinace zabal paket a pošli přes tento tunel. |
| Inbound | Z tohoto peeru přijmi pouze pakety se source IP v seznamu. Ostatní tiše zahoď. |

Pokud na UCG chybí v `AllowedIPs` síť, ze které může přes tunel přijít
paket, kernel ho zahodí bez logu a bez ICMP odpovědi.

Do UCG `AllowedIPs` patří každý subnet, který se má dostat do LAN za UCG:

| Typ subnetu | Proč |
|---|---|
| Remote LAN za pfSense | servery, které komunikují s LAN za UCG |
| Další LAN za pfSense | pokud pfSense routuje další interní sítě |
| OpenVPN client pool | OVPN klienti připojení do pfSense |
| WG tunnel subnet | ostatní WG peeři na stejném tunelu (remote access) |
| Další S2S subnety za pfSense | pokud pfSense propojuje další lokality |

Při přidání nové sítě nebo služby:

1. UCG `AllowedIPs`: zdrojový subnet (uprav `tunnels/<nazev>.conf`, pak `wg-s2s restart <nazev>`)
2. pfSense peer Allowed IPs: destinační subnet
3. Routing (gateway, static route)
4. Firewall na obou stranách

## 6. Správa tunelů

```bash
wg-s2s list
wg-s2s status            # všechny, tabulka s handshake
wg-s2s status <nazev>    # detail: interface, wg show, routes
wg-s2s start|stop|restart <nazev>|all
wg-s2s delete <nazev>    # zastaví, zakáže autostart, smaže config i klíče
```

Autostart přes systemd: `systemctl enable|disable|status wg-s2s@<nazev>`.

## 7. Ověření a troubleshooting

Na UCG:

```bash
wg-s2s status
wg show <nazev>
ping <remote_lan_ip>
tcpdump -i <nazev> -n
```

Na pfSense:

```bash
wg show tun_wg0
netstat -rn | grep <ucg_lan>
tcpdump -i tun_wg0 -n icmp
```

V `tcpdump` na pfSense musí být vidět původní source IP z LAN za UCG,
ne tunelová adresa. Pokud je vidět tunelová, běží NAT (typicky UniFi GUI
klient místo ručního tunelu).

| Problém | Příčina | Řešení |
|---|---|---|
| Handshake timeout | firewall blokuje UDP | povolit UDP 51820 na WAN pfSense |
| Ping z UCG OK, z LAN ne | chybí static route na pfSense | přidat route pro `<ucg_lan>` |
| Ping tam OK, odpověď nechodí | chybí source subnet v UCG `AllowedIPs` | viz kapitola 5 |
| Source IP je tunnel IP | NAT/masquerade | použít ruční tunel, ne UniFi GUI |
