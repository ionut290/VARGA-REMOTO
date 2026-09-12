# Varga Remote 0.7.4 Configurazione automatica accesso esterno

Varga Remote e un pannello Windows per controllare PC propri o autorizzati usando
RustDesk come motore di desktop remoto. La versione 0.6 aggiunge **Accesso
esterno sicuro** tramite Tailscale e Varga Relay; Smart Wake continua ad analizzare
automaticamente PC, Ethernet e rete e sceglie il metodo di
accensione piu sicuro che riesce realmente a verificare.

## Novita della 0.7

- un solo pulsante **CONFIGURA AUTOMATICAMENTE ACCESSO ESTERNO**;
- scelta guidata tra **PREPARA QUESTO PC DA CONTROLLARE** e
  **IMPORTA SUL PC DI CONTROLLO**;
- installazione automatica di Tailscale tramite Windows Package Manager;
- apertura automatica dell'accesso Tailscale nel browser e attesa della connessione;
- installazione automatica del Power Agent, firewall e avvio automatico;
- generazione di una configurazione `VRE1` copiata negli appunti;
- importazione senza digitare indirizzo Power Agent o token;
- ricerca automatica di Varga Relay fra i dispositivi Tailscale;
- stato chiaro: spegnimento pronto oppure accesso completo con accensione.

Sul PC da controllare premi il pulsante e scegli il punto 1. Sul PC di controllo
seleziona quel computer, premi lo stesso pulsante e scegli il punto 2. L'unica
operazione esterna richiesta e confermare l'amministratore e accedere a Tailscale
nel browser.

## Novita della 0.6

- pulsante **CONFIGURA ACCESSO ESTERNO** per ogni PC autorizzato;
- accensione da Internet tramite un piccolo Varga Relay sempre acceso nella LAN;
- spegnimento, riavvio e annullamento tramite Power Agent Windows;
- comunicazioni instradate nella rete cifrata Tailscale;
- nessuna porta pubblica aperta sulla Vodafone Station;
- token lungo obbligatorio, protetto con DPAPI sul PC di controllo;
- agente limitato agli indirizzi Tailscale `100.64.0.0/10`;
- conferma e ritardo di 60 secondi mantenuti per spegnimento e riavvio.

RustDesk resta il motore per vedere e controllare lo schermo. Varga Relay gestisce
solo il Magic Packet di accensione; il Power Agent accetta solo i tre comandi di
alimentazione previsti e non offre un terminale remoto.

### Preparazione del PC controllato

1. Installare Tailscale sul PC controllato e sul PC di controllo, usando lo stesso
   account/Tailnet.
2. Sul PC controllato eseguire come amministratore
   `windows/Installa-agente-accesso-esterno.cmd`.
3. Conservare l'indirizzo `http://100.x.x.x:47832` e il token mostrati.
4. Preparare Varga Relay seguendo `relay/INSTALLAZIONE.md`.
5. Sul PC di controllo selezionare il PC in Varga Remote, premere
   **CONFIGURA ACCESSO ESTERNO** e inserire i due indirizzi e il token.

Per l'accensione il PC controllato deve essere collegato via Ethernet e Wake-on-LAN
deve essere abilitato nel BIOS/UEFI e nella scheda di rete.

La versione 0.4 ha aggiunto **Smart Wake**:
l'app analizza automaticamente PC, Ethernet e rete e sceglie il metodo di
accensione piu sicuro che riesce realmente a verificare.

## Novita della 0.5

- controllo automatico degli aggiornamenti all'avvio, al massimo una volta ogni 6 ore;
- download esclusivamente dal repository ufficiale `ionut290/VARGA-REMOTO`;
- verifica del manifest e dei file indispensabili prima dell'installazione;
- backup automatico della versione installata prima di applicare le modifiche;
- pulsante **AGGIORNA** per effettuare immediatamente un controllo manuale;
- dati dei PC in `%APPDATA%\VargaRemote` separati dai file aggiornabili.

Quando una modifica viene pubblicata su `main` insieme a un numero superiore in
`windows/version.json`, i PC installati la rilevano automaticamente. Le modifiche
diventano completamente attive al successivo avvio di Varga Remote.

## Cosa fa la 0.4

- installazione grafica: non serve usare il terminale;
- installazione/configurazione del servizio RustDesk dalla stessa finestra;
- accesso permanente che sopravvive a riavvio e logout;
- icona **Varga Remote** sul Desktop;
- rilevamento automatico della scheda Ethernet e del MAC usato per Wake-on-LAN;
- tentativo di abilitazione di **Wake on Magic Packet** in Windows durante
  l'installazione (quando il driver lo consente);
- rilevamento gateway e MAC del router, SSDP/UPnP, modello/fingerprint del router,
  IP WAN quando esposto, IP pubblico e possibile CGNAT;
- rilevamento di possibili componenti Intel Management Engine/vPro senza
  dichiarare AMT remoto pronto finche non e realmente provisionato;
- database iniziale di router AVM, ASUS, GL.iNet, OpenWrt, MikroTik, Keenetic,
  Ubiquiti, Synology, TP-Link, NETGEAR e modem dei principali operatori;
- profilo di associazione **VR1**: copia ID, nome PC, MAC e diagnostica rete senza
  includere la password RustDesk;
- pulsante **ACCENDI** con selezione automatica tra LAN e rotta VPN verificata;
- pulsanti **SPEGNI**, **RIAVVIA** e **ANNULLA**;
- nessuna apertura automatica di porte nel router.

## Come Smart Wake decide

Quando premi **ACCENDI**, Varga Remote non si limita a inviare un pacchetto a
caso. Controlla prima la situazione corrente.

1. **Stessa LAN verificata**: confronta anche il MAC del gateway. Questo evita di
   confondere due reti diverse che usano entrambe, per esempio, `192.168.1.1`.
   Se la LAN coincide, invia il Magic Packet alla scheda Ethernet.
2. **VPN con rotta verso la LAN remota**: non basta che un programma VPN sia
   installato. Windows deve realmente instradare l'IP locale del PC remoto
   attraverso un adattatore VPN; soltanto allora Varga Remote usa quella rotta.
3. **Wake-on-WAN**: non viene abilitato automaticamente. Una futura/configurazione
   esplicitamente verificata potra marcarlo come utilizzabile. La 0.4 non apre
   UDP 7/9 via UPnP.
4. Se nessun percorso remoto e verificato, l'app non finge di aver acceso il PC:
   mostra la soluzione consigliata e indica la configurazione necessaria.

Per un PC che deve essere acceso da molto lontano mentre nella sede rimane acceso
soltanto il router, la soluzione preferita e in genere:

**PC Ethernet + Wake-on-LAN + VPN server sul router.**

Una volta collegato il PC di controllo alla VPN del router remoto, il pulsante
**ACCENDI** rileva la rotta VPN e invia automaticamente il Magic Packet.

## Installazione grafica

1. Estrai tutto lo ZIP in una cartella.
2. Fai doppio clic su **Installa Varga Remote.vbs**.
3. Accetta la richiesta amministratore di Windows.
4. Inserisci il nome del PC, la password permanente e conferma l'autorizzazione.
5. Premi **INSTALLA VARGA REMOTE**.
6. L'installer scarica/configura RustDesk, configura Smart Wake e crea l'icona
   **Varga Remote** sul Desktop.
7. Al termine viene mostrato il metodo Smart Wake consigliato.

Il vecchio `Installazione-PC-controllato.cmd` apre la stessa interfaccia grafica.

## Collegare due PC senza copiare tutti i dati a mano

Sul PC che vuoi controllare:

1. apri **Varga Remote**;
2. premi **COPIA PROFILO**;
3. trasferisci il testo copiato al PC di controllo con un canale appropriato.

Sul PC di controllo:

1. apri **Varga Remote**;
2. premi **Aggiungi PC**;
3. premi **INCOLLA PROFILO VARGA**;
4. salva.

Il profilo contiene ID RustDesk, nome Windows, MAC Ethernet e diagnostica Smart
Wake. **Non contiene la password RustDesk.**

## Pulsante SMART WAKE

Seleziona un PC e premi **SMART WAKE** per vedere:

- metodo consigliato;
- stato remoto (`LOCAL_ONLY`, `SETUP_REQUIRED`, ecc.);
- scheda e MAC Ethernet;
- stato Wake on Magic Packet;
- gateway e MAC gateway;
- router rilevato;
- IP WAN/pubblico e possibile CGNAT;
- eventuale candidato Intel AMT/vPro;
- azione consigliata per rendere possibile l'accensione da Internet.

## Spegni e riavvia

**SPEGNI**, **RIAVVIA** e **ANNULLA** usano il comando remoto di Windows e
richiedono connettivita IP verso il PC (stessa LAN o VPN) e i relativi permessi
Windows. Il comando di spegnimento/riavvio ha una conferma e un ritardo di 60
secondi per ridurre gli errori involontari.

## Trasparenza della sessione remota

Sul PC controllato, in RustDesk > Impostazioni > Sicurezza, verificare:

- approvazione: **Password o clic locale**;
- password: **Password permanente**;
- tastiera e mouse: abilitati;
- modalita privacy: disabilitata;
- blocco dell'input locale: disabilitato;
- terminale remoto: disabilitato;
- trasferimento file e appunti: abilitarli soltanto quando servono.

La persona davanti al PC deve poter vedere la connessione e interromperla.

## Revocare l'accesso permanente

Sul PC controllato esegui come amministratore `Revoca-accesso.cmd`. Lo script
sostituisce la vecchia password permanente con una credenziale casuale non
conservata e riavvia il servizio RustDesk.

## Server RustDesk OSS opzionale

La cartella `server` contiene una configurazione Docker Compose per un server
RustDesk OSS self-hosted. E separata da Smart Wake: il relay RustDesk permette il
controllo quando Windows e acceso, ma non sostituisce un router/VPN capace di
consegnare il Magic Packet quando il PC e spento.

## Limiti importanti della beta

- Varga Remote non puo trasformare automaticamente un router incompatibile in un
  dispositivo Wake-on-LAN remoto.
- Una VPN installata soltanto sul PC che deve essere acceso non basta, perche quel
  PC e spento. Per il caso "rimane acceso solo il router", la VPN deve essere sul
  router oppure deve esserci un altro dispositivo sempre acceso nella LAN.
- Il supporto Wake-on-LAN dopo spegnimento completo dipende anche da BIOS/UEFI,
  scheda di rete, driver e alimentazione della porta Ethernet.
- Il rilevamento Intel Management Engine non equivale a AMT/vPro remoto gia
  configurato.
- Wake-on-WAN via UDP pubblico e volutamente conservativo e non viene configurato
  in automatico.

## Uso autorizzato

Usare soltanto su PC propri o con autorizzazione chiara del proprietario. Su PC
aziendali occorre rispettare anche privacy, policy interne e norme applicabili al
controllo a distanza. Varga Remote non deve essere modificato per funzionare in
modo nascosto.
