# Roadmap Varga Remote

## 0.5 - Aggiornamenti automatici

- repository ufficiale GitHub;
- manifest di versione centralizzato;
- controllo silenzioso all'avvio ogni 6 ore;
- aggiornamento manuale dal pulsante AGGIORNA;
- backup locale prima della sostituzione dei file;
- conservazione di dispositivi e configurazioni personali.

## 0.1 - Base funzionante

- installazione Windows con servizio automatico;
- password permanente;
- manager locale senza salvataggio password;
- revoca immediata;
- server RustDesk OSS opzionale.

## 0.2 - Installazione grafica

- finestra di installazione senza terminale;
- download e configurazione automatica del motore;
- icona Varga Remote sul Desktop;
- file applicativi in LocalAppData;
- blocco del collegamento involontario allo stesso PC.

## 0.3 - Power Beta

- MAC Ethernet per ogni PC;
- rilevamento gateway/router;
- Wake-on-LAN locale;
- Spegni/Riavvia/Annulla;
- nessuna apertura automatica delle porte del router.

## 0.4 - Smart Wake Beta

- diagnostica Ethernet/Wake durante l'installazione;
- rilevamento router piu robusto con SSDP/UPnP e fingerprint HTTP;
- IP WAN/pubblico e rilevamento prudente del CGNAT;
- riconoscimento dei router piu comuni tramite database locale;
- controllo gateway + MAC gateway per evitare falsi "stessa rete";
- rilevamento reale della rotta VPN verso la LAN remota;
- selezione automatica del metodo ACCENDI;
- profilo VR1 copia/incolla per associare rapidamente due PC;
- candidato Intel AMT/vPro indicato senza falsi positivi di provisioning;
- nessun port forwarding UDP automatico.

## 0.5 - Configurazione remota guidata del router

Obiettivo: dopo che Smart Wake identifica il modello, mostrare una procedura
specifica per quel router e poter verificare con un test reale che l'accensione
da Internet funziona. Priorita:

- FRITZ!Box / WireGuard;
- ASUS / WireGuard o OpenVPN;
- OpenWrt / WireGuard;
- MikroTik / WireGuard;
- GL.iNet / WireGuard;
- gestione modem operatore e casi CGNAT.

La configurazione deve restare esplicita: nessuna apertura di porte in background.

## 0.6 - Power control avanzato

- test guidato sospensione/ibernazione/spegnimento;
- verifica del ritorno online dopo ACCENDI;
- memorizzazione dell'ultimo metodo realmente riuscito;
- eventuale integrazione Intel AMT/vPro soltanto su hardware provisionato;
- integrazione opzionale con un piccolo relay sempre acceso per router senza VPN.

## 0.6 - Accesso esterno sicuro

- Varga Relay Wake-on-LAN per reti con Vodafone Station o router senza VPN/WOL;
- collegamento privato tramite Tailscale senza porte pubbliche;
- Power Agent Windows limitato a spegnimento, riavvio e annullamento;
- configurazione per PC dal Manager e token cifrato localmente.

## 0.7 - Configurazione automatica

- installazione guidata Tailscale e Power Agent dal Manager;
- pairing VRE1 dagli appunti senza compilare indirizzi e token;
- rilevamento automatico del relay nella Tailnet;
- indicazione separata delle funzioni realmente pronte.

## 1.0 - Piattaforma centralizzata

- account e autenticazione a due fattori;
- associazione utente-dispositivo con chiavi revocabili;
- stato online in tempo reale;
- registro accessi e avvisi;
- ruoli proprietario, operatore e osservatore;
- autorizzazioni separate per controllo, appunti e file.
