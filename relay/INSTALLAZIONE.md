# Installazione Varga Relay

Varga Relay deve rimanere acceso nella stessa rete Ethernet/Wi-Fi del PC da
accendere. La soluzione consigliata e un Raspberry Pi Zero 2 W o un altro piccolo
computer Linux. Il relay e il PC di controllo comunicano nella rete cifrata
Tailscale: non aprire porte sulla Vodafone Station.

## Requisiti

- Python 3;
- Tailscale installato e collegato allo stesso account del PC di controllo;
- indirizzo broadcast della LAN (normalmente `192.168.1.255`);
- lo stesso token lungo usato dal Power Agent Windows.

## Installazione Linux

1. Copiare `varga-relay.py` in `/opt/varga-relay/`.
2. Copiare `varga-relay.service` in `/etc/systemd/system/`.
3. Creare `/etc/varga-relay.env` con:

   ```text
   VARGA_RELAY_TOKEN=TOKEN_LUNGO_GENERATO_DAL_POWER_AGENT
   VARGA_RELAY_BROADCAST=192.168.1.255
   VARGA_RELAY_PORT=47831
   ```

4. Proteggere e avviare il servizio:

   ```bash
   sudo chmod 600 /etc/varga-relay.env
   sudo systemctl daemon-reload
   sudo systemctl enable --now varga-relay
   tailscale ip -4
   ```

5. Nel PC di controllo aprire Varga Remote, selezionare il PC e premere
   **CONFIGURA ACCESSO ESTERNO**. Inserire:

   - Relay: `http://IP-TAILSCALE-RELAY:47831`;
   - Power Agent: `http://IP-TAILSCALE-PC:47832`;
   - il token generato durante l'installazione del Power Agent.

Il servizio accetta soltanto richieste provenienti da indirizzi Tailscale e con
token corretto. Il token viene conservato con permessi root sul relay e cifrato
con DPAPI sul PC di controllo.
