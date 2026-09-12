# Sicurezza e consenso

1. L'installazione sul PC controllato richiede privilegi amministratore e una
   conferma locale esplicita di autorizzazione.
2. Il manager non conserva la password RustDesk. In
   `%APPDATA%\VargaRemote\devices.json` salva soltanto i dati necessari al
   collegamento: nome, ID RustDesk, nome/IP Windows, MAC Ethernet e, se importato,
   il profilo Smart Wake (rete/router e diagnostica tecnica).
3. Il profilo **VR1** copiato negli appunti non contiene la password RustDesk e
   non contiene credenziali del router/VPN. Puo includere MAC, IP locali, gateway,
   fingerprint del router e IP pubblico rilevato: va quindi condiviso soltanto
   tra dispositivi/personale autorizzato.
4. Smart Wake non usa UPnP per creare port forwarding e non apre automaticamente
   UDP 7/9 sul router.
5. Accesso Esterno 0.6 usa Tailscale e accetta soltanto indirizzi del Tailnet. Non
   pubblicare le porte 47831/47832 su Internet e non creare port forwarding sulla
   Vodafone Station.
6. Il token del PC di controllo viene cifrato con DPAPI per l'utente Windows. Sul
   relay e sul PC controllato deve essere leggibile soltanto da amministratori e
   account di servizio.
7. Il codice automatico **VRE1** contiene il token segreto. Trasferirlo soltanto
   fra i propri PC attraverso un canale affidabile e non pubblicarlo. Dopo
   l'importazione il token viene conservato cifrato con DPAPI.
5. La password permanente deve contenere almeno 12 caratteri alfanumerici.
6. La revoca sostituisce la password con una credenziale casuale e non la
   conserva.
7. Modalita privacy e blocco dell'input locale devono rimanere disabilitati.
8. L'utente locale deve poter vedere/interrompere la sessione dall'interfaccia
   RustDesk.
9. Non esporre un server RustDesk self-hosted senza firewall e non pubblicare la
   chiave privata `id_ed25519`.
10. Per utenti, gruppi, 2FA, log e controllo centralizzato usare un backend
    autenticato/una soluzione server adatta; la beta non sostituisce una
    piattaforma IAM centralizzata.
11. Gli aggiornamenti provengono soltanto dal repository pubblico ufficiale
    `ionut290/VARGA-REMOTO`. Il programma verifica il manifest e la presenza dei
    file obbligatori prima di sostituire l'installazione locale.
12. Prima di ogni aggiornamento viene creata una copia in
    `%LOCALAPPDATA%\VargaRemote\UpdateBackup`. I dati dei dispositivi non sono
    inclusi nei file aggiornati e non vengono sovrascritti.

## Accensione remota

Per l'accensione da Internet, Smart Wake preferisce una VPN terminata sul router
(o su un dispositivo sempre acceso nella LAN). Una VPN installata soltanto sul
PC spento non puo consegnare il Magic Packet quando quel PC e offline.

Il rilevamento di un IP pubblico o di componenti Intel Management Engine non
viene considerato prova sufficiente di Wake-on-WAN o Intel AMT gia configurati.
Varga Remote mostra questi metodi come **da configurare/verificare** fino a quando
non esiste un percorso realmente utilizzabile.

## Modello di autorizzazione

La versione basata su RustDesk usa una password permanente configurata sul PC
controllato. Chi possiede ID e password puo richiedere una connessione.
Condividere la password soltanto con persone autorizzate e revocarla quando non
serve piu.
