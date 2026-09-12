# OpenAuto: prova Debian 13 ARM64 sul K708

Questa prova compila OpenAuto con `NOPI=ON` e AASDK da commit fissati in
`configs/openauto-proof.sources`. La coppia iniziale usa revisioni dello stesso
periodo; compilazione e prova con il telefono determinano la compatibilità.
Non è una distribuzione né un'immagine da flashare. Non installa servizi.

## Build

Su un host ARM64 con Docker:

```sh
./scripts/build-openauto-proof.sh
```

In alternativa la PR esegue il workflow **OpenAuto ARM64 proof** su un runner
ARM64, all'interno di Debian Trixie. I risultati sono in `build/openauto-proof/`
o nell'artifact del workflow. Sono inclusi archivio binario, sorgenti upstream,
ricetta, checksum e inventario delle dipendenze. Il tag Debian e gli archivi apt
non sono congelati: le revisioni sorgenti sono fissate, la build non è bit-identica.

## Prova sul tablet

Richiede la tua Debian 13 arm64 già funzionante con profilo display, accesso
amministrativo UART/SSH e collegamento USB host da verificare. Trasferire
`k708-openauto-arm64.tar.xz` e `SHA256SUMS` sul tablet. Con entrambi gli archivi
presenti si può eseguire `sha256sum -c SHA256SUMS`; altrimenti verificare la riga
corrispondente all'archivio binario. Estrarre in una directory scelta:

```sh
tar -xf k708-openauto-arm64.tar.xz
sudo apt-get update
xargs -r sudo apt-get install -y < k708-openauto/runtime-packages.txt
sudo systemctl stop rk3326-hwtest.service
```

Se Crankshaft è stato installato, fermarne prima core e UI. Nessun altro programma
può possedere il display DRM. Per questa prima prova diagnostica usare una console
locale libera; dalla UART è possibile aprire tty1 con `openvt`:

```sh
sudo openvt -c 1 -s -w -- "$PWD/k708-openauto/run.sh"
```

Se tty1 è occupato da getty, fermare temporaneamente `getty@tty1.service`.
Il comando sopra esegue la prova come root per evitare che i permessi USB/DRM
confondano il primo test; un servizio con utente dedicato verrà valutato dopo.
La configurazione è salvata nella directory di stato dell'utente che avvia il
programma. `OPENAUTO_STATE_DIR` consente di indicarne una esplicitamente.

La configurazione iniziale richiede 800x480 a 30 fps: nell'enum upstream
`Resolution=1` e `FPS=2`. Touch abilitato, wireless/Bluetooth e canali audio di
uscita disabilitati. Il microfono non è dichiarato disabilitato da queste opzioni:
la gestione audio incompleta può ancora ostacolare l'avvio sul BSP attuale.

Controllare nell'ordine: apertura interfaccia, corrispondenza touch, enumerazione
USB del telefono, handshake Android Auto, immagine, input e riconnessione.
Il ridimensionamento sul pannello 1024x600 e la mappatura touch richiedono una prova.
Panfrost funzionante non dimostra che H.264 sia decodificato dalla VPU.

Per tornare al dashboard, uscire dall'applicazione e dalla UART eseguire:

```sh
sudo systemctl start rk3326-hwtest.service
```

## Cosa non dimostra la build

L'output ELF ARM64 e l'assenza di librerie Broadcom non dimostrano una sessione
Android Auto funzionante. Il fork usa Qt5 Multimedia per il video generico;
fluidità e decoder selezionato devono essere misurati sul K708. Conserva inoltre
richiami a helper Crankshaft per camera, aggiornamenti e funzioni di sistema:
queste funzioni non sono l'obiettivo della prova e non vengono installati i loro
script. L'archivio contiene solo autoapp e le librerie AASDK private, senza
sostituire quelle del sistema.
