# Server privato Varga Remote

Requisiti: VPS Linux, Docker Engine, Docker Compose, dominio o IP pubblico.

## Avvio

```bash
cp .env.example .env
# modifica VARGA_REMOTE_HOST nel file .env
docker compose up -d
docker compose ps
```

Aprire nel firewall:

- TCP 21115, 21116, 21117;
- UDP 21116;
- TCP 21118 e 21119 soltanto se si useranno client WebSocket.

La chiave pubblica viene generata al primo avvio:

```bash
cat data/id_ed25519.pub
```

Inserire host e chiave pubblica in RustDesk > Impostazioni > Rete su entrambi i
PC. Non cancellare la cartella `data`: contiene la chiave del server.

## Aggiornamento

```bash
docker compose pull
docker compose up -d
```

Eseguire sempre un backup della cartella `data` prima di aggiornare.

