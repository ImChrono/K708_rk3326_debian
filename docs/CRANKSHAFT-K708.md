# Crankshaft sul K708: profilo sperimentale

## Obiettivo e stato

Integrare Crankshaft nella Debian 13 arm64 di questo BSP, mantenendo bootloader,
kernel, DTS e layout microSD del tablet. Il profilo prepara una prova USB con
video e touch; non costituisce una certificazione di funzionamento Android Auto.
Audio, microfono e canale Bluetooth sono inizialmente disabilitati perché il BSP
non li documenta ancora come funzionanti. La compatibilità di questa combinazione
minima di canali con il telefono va verificata.

Il profilo è una scelta della **rootfs**, distinta da `BOOT_PROFILE`: usare
`ROOTFS_PROFILE=android-auto` insieme al successivo `BOOT_PROFILE=display`.
Senza la variabile, la rootfs diagnostica conserva il comportamento precedente.
Non vengono modificati DTS, ricarica, eMMC o boot chain.

## Audit dei sorgenti

Revisioni esaminate e riferimento AASDK: `configs/crankshaft-sources.json`.
Questi SHA sono riferimenti dei sorgenti, non una prova dell'origine dei binari.

| Area | Evidenza upstream | Decisione K708 |
|---|---|---|
| Immagine Crankshaft | Builder basato su pi-gen e stadi Raspberry Pi OS | Usare il builder del BSP |
| Core | Qt 6, libusb, AASDK, GStreamer; packaging arm64 | Pacchetti compilati per Debian 13 arm64 |
| UI slim | Qt 6/QML; EGLFS con eglfs_kms | Usare DRM/KMS; niente desktop completo |
| Decoder core | Selezione vaapih264dec, omxh264dec, nvh264dec, poi avdec_h264 | Primo test con fallback software; nessuna accelerazione Rockchip dichiarata |
| Pipeline video | Conversione/scaling a RGBA e copia dei frame | Misurare CPU, latenza e memoria anche dopo aver abilitato la VPU |
| Display setup | Può scegliere VNC se non vede un connettore | Forzare EGLFS nel profilo tablet |
| Servizio UI | After=graphical.target e WantedBy=graphical.target | Rimuovere l'ordinamento circolare nel drop-in |
| Accesso hardware | postinst può ignorare errori di usermod | Creare gruppi e applicare appartenenze esplicitamente |
| Audio runtime | Core usa /run/user/<uid> | Installare PipeWire/WirePlumber e abilitare linger |
| WebSocket | WebSocketServer.cpp usa QHostAddress::Any | Il campo host JSON non limita il bind nella revisione esaminata; testare su rete fidata |

Riferimenti:
- https://github.com/opencardev/crankshaft/tree/develop/image_builder
- https://github.com/opencardev/crankshaft-core/blob/af2650f6bcfd0ca3608d12edb8b5cf9bd45f1ccf/src/hal/multimedia/GStreamerVideoDecoder.cpp
- https://github.com/opencardev/crankshaft-core/blob/af2650f6bcfd0ca3608d12edb8b5cf9bd45f1ccf/src/services/websocket/WebSocketServer.cpp
- https://github.com/opencardev/crankshaft-ui-slim/blob/1fdf68e8d9f22e5faa979eead500426e3a9d51bc/src/packaging/ui-slim/crankshaft-ui-slim.service

## Preparazione dei pacchetti

Usare una macchina/container Debian 13 **arm64** con toolchain nativa, oppure
un ambiente arm64 emulato. Compilare AASDK prima del core, poi la UI. Consultare
i build.sh e i manifest deps delle revisioni indicate; non usare pacchetti
Raspberry Pi OS o Ubuntu come sostituti automatici. Core e UI espongono
`BUILD_PACKAGE=ON ./build.sh --clean` e `./build.sh --install-deps`.
Quest'ultimo può aggiungere il repository apt OpenCarDev: eseguirlo solo nel
builder dedicato. Verificare la provenienza/versione di AASDK separatamente.

Per ogni repository, fare checkout del commit completo presente nel manifest
prima della build. Raccogliere i .deb runtime in una directory dedicata, per
esempio `build/crankshaft-debs/`. Devono esserci i pacchetti:

- `libaasdk`;
- `crankshaft-core`;
- `crankshaft-ui-slim`.

Includere eventuali ulteriori dipendenze non disponibili negli archivi Debian.
La procedura non aggiunge repository apt di terzi alla rootfs; apt risolve le
altre dipendenze dagli archivi Debian configurati e fallisce se non soddisfatte.
Il packaging core esaminato cita esplicitamente libprotobuf32/libprotobuf32t64:
verificare che il .deb prodotto abbia dipendenze compatibili con Trixie. Se non
lo sono, correggere il packaging upstream e ricostruire; non forzare dpkg.

Da dentro la directory dei pacchetti:

```sh
sha256sum *.deb > SHA256SUMS
```

Il manifest deve elencare esattamente tutti i .deb con nomi semplici, senza
percorsi. Il validatore rifiuta checksum errati, symlink, pacchetti mancanti,
duplicati e architetture diverse da arm64/all. I checksum fissano i file
selezionati, ma non autenticano il produttore né verificano il commit sorgente.

## Costruzione

Dalla radice del BSP, con i pacchetti preparati:

```sh
python3 scripts/check-crankshaft-packages.py build/crankshaft-debs
sudo env ROOTFS_PROFILE=android-auto \
  CRANKSHAFT_DEB_DIR="$PWD/build/crankshaft-debs" \
  ./scripts/build-rootfs.sh "$PWD/build/debian-android-auto.tar.xz"
```

L'account root resta bloccato se ROOT_PASSWORD_HASH è omesso, come nel builder
esistente. Predisporre l'accesso amministrativo prima del test, seguendo README.
Il rootfs installer blocca gli avvii tramite policy-rc.d durante apt; usarlo
soltanto attraverso build-rootfs.sh su una rootfs nuova e non sul sistema host.

Dopo aver preparato blob privati e kernel come nel README:

```sh
sudo env BOOT_PROFILE=display IMAGE_SIZE_MIB=6144 \
  ./scripts/build-image.sh \
  /percorso/kernel /percorso/kernel-out \
  "$PWD/build/debian-android-auto.tar.xz" \
  "$PWD/build/k708-android-auto.img"
sudo ./scripts/validate-image.sh "$PWD/build/k708-android-auto.img"
```

6144 MiB è un punto di partenza, da verificare in base ai pacchetti prodotti.
Il validatore immagine controlla il BSP e, per questo profilo, file, canali e
collegamenti systemd di Crankshaft; non dimostra il funzionamento della sessione. Questa fase necessita dei blob privati del tablet.

## Comportamento al boot

- Target grafico con core, display setup e UI upstream.
- UI sul tty1, EGLFS/KMS; il dashboard hwtest viene disabilitato e getty@tty1 mascherato.
- UART2, SSH e raccolta hwprobe rimangono disponibili.
- Canali video/input/sensori abilitati; audio/microfono/Bluetooth disabilitati.
- La UI ha un limite iniziale di 512 MiB e nessun CPUQuota: misurare prima di ottimizzare.
- SHA256SUMS e riferimenti sorgenti sono conservati in /usr/share/rk3326-android-auto/.

La rotazione/calibrazione touch resta da validare: il controller espone un range
800x1280 mentre il pannello è 1024x600. Non viene inventata una matrice di
trasformazione senza misure reali.

## Prove sul tablet, nell'ordine

1. Verificare che EGLFS apra il display e che i tocchi corrispondano ai punti visualizzati.
2. Collegare il telefono in USB host e controllare enumerazione e alimentazione VBUS.
   Gli IRQ USB già osservati non provano la modalità host né la ricarica simultanea.
3. Avviare Android Auto: handshake, immagine, touch, scollegamento e riconnessione.
4. Misurare carico CPU, memoria, temperatura del SoC e fluidità con avdec_h264.
5. Abilitare e provare VPU/driver/plugin prima di modificare la selezione decoder.
   La semplice presenza di v4l2slh264dec o mppvideodec non prova la decodifica.
6. Completare codec RK817, uscita audio e microfono; poi riabilitare i relativi canali.
7. Affrontare Bluetooth/wireless e alimentazione continua come prove separate.

Comandi di raccolta iniziale:

```sh
systemctl status crankshaft-core crankshaft-ui-slim --no-pager
journalctl -b -u crankshaft-core -u crankshaft-ui-slim --no-pager
lsusb -t
ls -l /dev/dri
libinput list-devices
gst-inspect-1.0 avdec_h264
gst-inspect-1.0 v4l2slh264dec
gst-inspect-1.0 mppvideodec
aplay -l
arecord -l
```

Gli ultimi due decoder possono risultare assenti: è un risultato diagnostico.
Per tornare temporaneamente al dashboard, dalla UART:

```sh
systemctl stop crankshaft-ui-slim crankshaft-core
systemctl start rk3326-hwtest
```

## Limiti della verifica effettuata

Questa modifica fornisce integrazione rootfs, controllo pacchetti e configurazione
iniziale. Non sono state eseguite build dei binari ARM64, build completa rootfs,
boot sul K708 o sessioni con un telefono. Non è inclusa un'immagine flashabile.
La disponibilità e compatibilità dei .deb è un prerequisito, non un risultato
assunto. I test automatici del validatore usano piccoli pacchetti di prova.
