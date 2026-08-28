# Da Android/ADB a una distro Debian riproducibile

Questa guida descrive come acquisire da un tablet Rockchip ancora avviabile le
informazioni e le risorse necessarie per costruire una distro Linux separata.
Il percorso principale usa ADB; le sezioni finali coprono recovery, UART,
Rockchip Loader/Maskrom e i casi in cui Android non offre accesso root.

Gli esempi specifici di layout si riferiscono al tablet K708/RK3326 studiato in
questo repository. Su un'altra scheda devono essere considerati **evidenza da
verificare**, non valori universali.

## Obiettivo e limiti

L'acquisizione deve produrre quattro gruppi distinti:

1. inventario testuale di Android e dell'hardware;
2. boot chain privata e immagini delle partizioni utili;
3. DTB, configurazione kernel, firmware e parametri hardware;
4. sorgenti pubblicabili che descrivano e ricostruiscano il sistema.

Non è necessario copiare Android dentro Debian. Android viene usato come
strumento di misura: mostra il layout di memoria, il Device Tree, i driver
attivi, i GPIO, i regolatori, il firmware e il comportamento dell'hardware.

La procedura è destinata esclusivamente a hardware posseduto o per il quale si
ha autorizzazione. Le immagini possono contenere chiavi, identificativi,
account, dati personali o firmware non redistribuibile.

## Regole di sicurezza

- Durante l'acquisizione usare soltanto letture da eMMC.
- Non eseguire `dd of=/dev/block/...`, `fastboot flash`, `rkdeveloptool wl`,
  `rkdeveloptool ef`, `rkdeveloptool gpt`, `rkdeveloptool prm` o
  `rkdeveloptool ul`.
- Non assumere che eMMC sia `mmcblk0`: su questo tablet è comparsa anche come
  `mmcblk2`. Risolvere sempre il dispositivo reale.
- Non assumere un settore logico da 512 byte: verificarlo prima di usare LBA.
- Eseguire due letture indipendenti dei blocchi critici e confrontarle.
- Conservare almeno una copia offline dei dump originali, senza modificarla.
- Non pubblicare bootloader, trust, security, dati utente o firmware prima di
  averne controllato licenza e contenuto.
- Se il layout rilevato non coincide con quello atteso, fermarsi. Non adattare
  gli offset per tentativi.

Caricare la batteria, usare un cavo USB affidabile e disabilitare la
sospensione automatica del computer host. La lettura delle partizioni di boot
è sicura anche con Android avviato; un'immagine completa di `userdata` o di un
filesystem montato, invece, non è uno snapshot coerente.

## 1. Preparare il computer host

Su Debian o Ubuntu:

```sh
sudo apt update
sudo apt install \
  android-sdk-platform-tools-common adb device-tree-compiler gdisk git \
  gzip openssl xz-utils
```

Strumenti utili ma non indispensabili sono `unpack_bootimg`, `avbtool`,
`binwalk`, `lz4`, `simg2img` ed `extract-dtb`. La disponibilità e il nome dei
pacchetti cambiano tra distribuzioni: non installare eseguibili casuali trovati
in archivi non verificati.

Creare una directory privata:

```sh
umask 077
mkdir -p rk3326-extract/{inventory,logs,dt,firmware,raw/pass1,raw/pass2,raw/partitions}
cd rk3326-extract
```

Non lavorare direttamente dentro il repository Git. I dump originali devono
restare fuori dalla cronologia.

## 2. Collegare ADB e registrare l'identità del dispositivo

Abilitare `Opzioni sviluppatore` e `Debug USB`, collegare il tablet e accettare
la chiave RSA mostrata da Android:

```sh
adb kill-server
adb start-server
adb devices -l
```

Se è collegato un solo dispositivo:

```sh
adb wait-for-device
adb get-state
adb shell id
adb shell getprop ro.product.model
adb shell getprop ro.build.fingerprint
```

Con più dispositivi usare sempre `adb -s SERIAL ...` in ogni comando.

Salvare immediatamente le informazioni disponibili senza root:

```sh
adb shell getprop > inventory/getprop.txt
adb shell cat /proc/cmdline > inventory/cmdline.txt
adb shell cat /proc/partitions > inventory/proc-partitions.txt
adb shell cat /proc/mounts > inventory/proc-mounts.txt
adb shell mount > inventory/mount.txt
adb shell ls -l /dev/block/by-name > inventory/by-name.txt 2>&1
adb shell ls -l /dev/block/platform > inventory/block-platform.txt 2>&1
adb shell dumpsys input > inventory/dumpsys-input.txt 2>&1
adb shell dumpsys battery > inventory/dumpsys-battery.txt 2>&1
adb shell ip address > inventory/ip-address.txt 2>&1
adb shell uname -a > inventory/uname.txt
```

Annotare anche data, seriale fisico della scheda, foto della PCB e sigle dei
componenti. Non pubblicare il seriale del dispositivo.

## 3. Determinare quale accesso root è disponibile

Provare prima il metodo ufficiale delle build `eng` o `userdebug`:

```sh
adb root
adb wait-for-device
adb shell id
```

Su una build Android `user` la risposta normale è che `adbd` non può essere
eseguito come root. In tal caso verificare se il tablet possiede già `su`:

```sh
adb shell 'command -v su || true'
adb shell su -c id
```

Un gestore root potrebbe chiedere conferma sullo schermo. Non installare un
exploit o modificare `boot` soltanto per ottenere i dump: si rischia di perdere
proprio la baseline che si vuole conservare.

Negli esempi seguenti è usata una funzione host `root_exec`. Definirne **una
sola**, in base al risultato precedente:

```sh
# Caso A: adbd è già root.
root_exec() { adb exec-out sh -c "$1"; }
```

oppure:

```sh
# Caso B: adbd è shell, ma su funziona.
root_exec() { adb exec-out su -c "$1"; }
```

Verifica:

```sh
root_exec 'id'
```

Deve comparire `uid=0`. Se compaiono banner, richieste interattive o testo
aggiuntivo, non usare ancora la funzione per dati binari: passare al metodo con
file temporaneo descritto più avanti.

## 4. Inventario privilegiato prima dei dump

```sh
root_exec 'dmesg' > logs/dmesg-android.txt
root_exec 'lsmod' > inventory/lsmod.txt
root_exec 'cat /proc/iomem' > inventory/iomem.txt
root_exec 'for f in /sys/bus/mmc/devices/*/uevent; do
  [ -f "$f" ] || continue; echo "### $f"; cat "$f"
done' \
  > inventory/mmc-uevent.txt
root_exec 'for f in /sys/bus/sdio/devices/*/uevent; do
  [ -f "$f" ] || continue; echo "### $f"; cat "$f"
done' \
  > inventory/sdio-uevent.txt
root_exec 'for f in /sys/bus/i2c/devices/*/name; do
  [ -f "$f" ] || continue; echo "### $f"; cat "$f"
done' \
  > inventory/i2c-devices.txt
root_exec 'for supply in /sys/class/power_supply/*; do
  [ -d "$supply" ] || continue; echo "### $supply"
  for f in "$supply"/*; do
    [ -f "$f" ] || continue; echo "-- $f"; cat "$f" 2>/dev/null
  done
done' \
  > inventory/power-supply.txt
```

Alcuni `find` di Android/Toybox non implementano tutte le opzioni. Se un
comando fallisce, elencare prima la directory e acquisire i file uno per uno;
non è un motivo per cambiare il sistema.

Individuare tutte le viste `by-name`:

```sh
root_exec 'find /dev/block -type d -name by-name -print 2>/dev/null'
root_exec 'for d in /dev/block/by-name /dev/block/platform/*/by-name; do
  [ -d "$d" ] || continue
  echo "### $d"
  ls -l "$d"
done' > inventory/all-by-name.txt
```

## 5. Identificare l'eMMC senza supposizioni

Risolvere una partizione riconoscibile, per esempio `uboot_a`, `boot` o
`system`:

```sh
root_exec 'readlink -f /dev/block/by-name/uboot_a'
root_exec 'readlink -f /dev/block/by-name/boot 2>/dev/null || true'
```

Un risultato come `/dev/block/mmcblk2p2` indica che il dispositivo padre è
`/dev/block/mmcblk2`. Verificare capacità e dimensione del settore sostituendo
il percorso con quello realmente osservato:

```sh
root_exec 'blockdev --getsize64 /dev/block/mmcblk2'
root_exec 'blockdev --getsz /dev/block/mmcblk2'
root_exec 'cat /sys/class/block/mmcblk2/queue/logical_block_size'
```

Per questo progetto l'ultima risposta deve essere `512`. Se non lo è, gli LBA
seguenti non possono essere usati senza conversione e nuova validazione.

Impostare sul computer host soltanto dopo la verifica:

```sh
emmc=/dev/block/mmcblk2
```

La variabile deve contenere un percorso completo e letterale. Non ricavarla da
output ambiguo e non usare glob.

## 6. Salvare GPT e prima regione del disco

La prima regione contiene GPT primaria, IDB e boot chain. Acquisirla due volte:

```sh
root_exec "dd if='$emmc' bs=512 count=65536 2>/dev/null" \
  > raw/pass1/first-32MiB.img
root_exec "dd if='$emmc' bs=512 count=65536 2>/dev/null" \
  > raw/pass2/first-32MiB.img

cmp raw/pass1/first-32MiB.img raw/pass2/first-32MiB.img
sha256sum raw/pass1/first-32MiB.img raw/pass2/first-32MiB.img
```

Gli hash devono essere identici. Esaminare la copia, mai l'originale:

```sh
fdisk -l raw/pass1/first-32MiB.img
sgdisk --print raw/pass1/first-32MiB.img
```

`sgdisk` può avvisare che manca la GPT secondaria: è normale in un dump
parziale. Le posizioni devono comunque coincidere con `by-name` e con i dati
del kernel prima di essere accettate.

## 7. Estrarre i sette blob richiesti da questo BSP

Nel K708 verificato il layout usa settori da 512 byte:

| File | LBA iniziale | Settori | Dimensione |
|---|---:|---:|---:|
| `idb-area-lba64-8191.img` | 64 | 8128 | 4.161.536 byte |
| `security.img` | 8192 | 8192 | 4.194.304 byte |
| `uboot_a.img` | 16384 | 8192 | 4.194.304 byte |
| `uboot_b.img` | 24576 | 8192 | 4.194.304 byte |
| `trust_a.img` | 32768 | 8192 | 4.194.304 byte |
| `trust_b.img` | 40960 | 8192 | 4.194.304 byte |
| `misc.img` | 49152 | 8192 | 4.194.304 byte |

Questi valori devono risultare dalla scheda in esame. Se una partizione inizia
altrove, non usare questa tabella e non tentare di forzare il builder.

Definire una funzione di sola lettura:

```sh
dump_lba()
{
  pass=$1
  start=$2
  count=$3
  name=$4
  root_exec "dd if='$emmc' bs=512 skip=$start count=$count 2>/dev/null" \
    > "raw/$pass/$name"
}
```

Prima lettura:

```sh
dump_lba pass1 64 8128 idb-area-lba64-8191.img
dump_lba pass1 8192 8192 security.img
dump_lba pass1 16384 8192 uboot_a.img
dump_lba pass1 24576 8192 uboot_b.img
dump_lba pass1 32768 8192 trust_a.img
dump_lba pass1 40960 8192 trust_b.img
dump_lba pass1 49152 8192 misc.img
```

Ripetere cambiando `pass1` in `pass2`, poi verificare:

```sh
for file in \
  idb-area-lba64-8191.img security.img uboot_a.img uboot_b.img \
  trust_a.img trust_b.img misc.img
do
  cmp "raw/pass1/$file" "raw/pass2/$file"
done

stat -c '%n %s' raw/pass1/*.img
sha256sum raw/pass1/*.img | tee raw/boot-chain.sha256
```

Per il tablet già supportato, gli hash devono coincidere anche con
`blobs/manifest.sha256`. Per una nuova revisione, conservare i nuovi hash in un
rapporto separato: non sostituire il manifest del K708 finché la nuova boot
chain non è stata verificata con un profilo distinto.

### Piano B per uno stream ADB binario non affidabile

Se `su` stampa banner o la connessione interrompe `exec-out`, creare il file in
`/data/local/tmp`, calcolarne l'hash sul tablet, scaricarlo e cancellarlo:

```sh
adb shell su -c \
  'dd if=/dev/block/mmcblk2 of=/data/local/tmp/security.img bs=512 skip=8192 count=8192'
adb shell su -c 'sha256sum /data/local/tmp/security.img'
adb pull /data/local/tmp/security.img raw/pass1/security.img
sha256sum raw/pass1/security.img
adb shell su -c 'rm -f /data/local/tmp/security.img'
```

Usare il percorso eMMC realmente verificato. Lo spazio temporaneo risiede su
`userdata`: controllare prima che sia sufficiente e non lasciarvi copie.

## 8. Salvare le partizioni Android utili

La boot chain minima non basta a ricostruire l'hardware. Se presenti,
acquisire separatamente:

- `boot`/`boot_a` e `boot_b`;
- `recovery`;
- `resource`;
- `dtbo`;
- `vendor_boot`;
- `vbmeta`;
- `parameter`, se esposto dal layout Rockchip.

Usare i link `by-name`, così la dimensione è quella della partizione:

```sh
root_exec 'blockdev --getsize64 /dev/block/by-name/boot_a'
root_exec 'dd if=/dev/block/by-name/boot_a bs=4M 2>/dev/null' \
  > raw/partitions/boot_a.img
```

Ripetere due volte anche queste immagini. Non è necessario acquisire
`userdata` per costruire Debian. Se serve un backup forense completo, eseguirlo
da recovery con i filesystem smontati e custodirlo cifrato; il dump da Android
in esecuzione non garantisce coerenza applicativa.

Analisi host iniziale:

```sh
file raw/partitions/*.img
sha256sum raw/partitions/*.img > raw/partitions.sha256
```

Per i boot image Android moderni usare `unpack_bootimg`; per AVB usare
`avbtool info_image`. Sui firmware Rockchip più vecchi kernel, ramdisk, DTB e
immagini `resource` possono usare contenitori differenti. Identificare prima
il formato e lavorare su una copia: non aggiungere o rimuovere header a
tentativi.

## 9. Recuperare il Device Tree in esecuzione

Il Device Tree è la fonte principale per GPIO, clock, regolatori, pannello,
PMIC, bus I2C/SDIO e periferiche. Il kernel Linux espone normalmente il FDT in
`/sys/firmware/fdt` e l'albero espanso in `/sys/firmware/devicetree/base` o
`/proc/device-tree`.

Metodo preferito:

```sh
root_exec 'cat /sys/firmware/fdt' > dt/running.dtb
dtc -I dtb -O dts -o dt/running.dts dt/running.dtb
dtc -I dtb -O dtb -o dt/running-roundtrip.dtb dt/running.dtb
```

Verificare che non sia vuoto e che `dtc` lo accetti:

```sh
stat -c '%n %s' dt/running.dtb
fdtget dt/running.dtb / model
sha256sum dt/running.dtb
```

Fallback dall'albero espanso:

```sh
root_exec 'tar -C /proc/device-tree -cf - .' > dt/proc-device-tree.tar
mkdir dt/proc-device-tree
tar -xf dt/proc-device-tree.tar -C dt/proc-device-tree
dtc -I fs -O dts -o dt/running-from-fs.dts dt/proc-device-tree
```

Un secondo DTB va estratto da `boot`, `resource` o `dtbo`: quello in esecuzione
mostra la configurazione effettiva, mentre quello nel firmware conserva
talvolta nodi disabilitati e dati non istanziati. Confrontare i due, non
sceglierne automaticamente uno.

Prima di pubblicare il DTS decompilato controllare proprietà come seriali,
indirizzi MAC, chiavi, calibrazioni uniche e dati `nvmem`.

## 10. Recuperare configurazione e informazioni del kernel Android

Se `CONFIG_IKCONFIG_PROC` è attivo:

```sh
root_exec 'cat /proc/config.gz' > inventory/android-kernel.config.gz
gzip -t inventory/android-kernel.config.gz
gzip -dc inventory/android-kernel.config.gz \
  > inventory/android-kernel.config
```

Altrimenti usare lo script `scripts/extract-ikconfig` dell'albero Linux sulla
componente kernel estratta da `boot.img`. Se anche questo fallisce, la
configurazione deve essere ricostruita da driver caricati, simboli e sorgenti
GPL corrispondenti; non dedurla soltanto dal nome commerciale del SoC.

Raccogliere anche:

```sh
root_exec 'cat /proc/version' > inventory/proc-version.txt
root_exec 'cat /proc/modules' > inventory/proc-modules.txt
root_exec 'find /vendor /system -type f -name "*.ko" -exec sha256sum {} \; 2>/dev/null' \
  > inventory/android-modules.sha256
```

I moduli Android non sono in genere riutilizzabili con un kernel Debian
diverso. Servono a identificare driver, opzioni e firmware; il codice va poi
ricompilato per il kernel scelto.

## 11. Firmware e configurazioni periferiche

Salvare, se esistono:

```sh
adb pull /vendor/etc/firmware firmware/vendor-etc-firmware
adb pull /vendor/firmware firmware/vendor-firmware
adb pull /system/etc/firmware firmware/system-etc-firmware
adb pull /vendor/lib/modules firmware/vendor-lib-modules
```

Se i permessi impediscono `adb pull`, usare un archivio tar attraverso
`root_exec` oppure il metodo temporaneo. Conservare percorso originale,
proprietario, hash e licenza di ogni file.

Per ogni periferica annotare almeno:

| Periferica | Evidenza da raccogliere |
|---|---|
| Wi-Fi/BT | ID SDIO/USB/UART, modulo, firmware, MAC, GPIO enable/wake |
| Touch | nome input, indirizzo I2C, IRQ/reset, firmware/config, assi |
| Display | lane DSI, formato, timing, reset/enable, PWM backlight |
| Audio | codec, routing, GPIO amplificatore, mixer Android |
| Batteria | PMIC, tensioni/correnti, capacità, tabella NTC se reale |
| USB | ruolo OTG, VBUS, extcon/type-C, IRQ PHY |
| Sensori | indirizzo bus, `compatible`, orientamento e calibrazione |

Comandi diagnostici utili:

```sh
adb shell dumpsys input > inventory/dumpsys-input-full.txt
root_exec 'cat /proc/bus/input/devices' > inventory/input-devices.txt
root_exec 'for f in /sys/bus/sdio/devices/*/uevent; do echo "### $f"; cat "$f"; done' \
  > inventory/sdio-full.txt
root_exec 'for f in /sys/class/drm/*/status /sys/class/drm/*/modes; do
  [ -f "$f" ] || continue; echo "### $f"; cat "$f"; done' \
  > inventory/drm.txt
```

Nel K708 il firmware/configurazione GSL3673 non era un normale file caricato
da userspace: era incorporato nel driver Android. Il percorso preferibile è
recuperare il sorgente GPL esatto del produttore, verificarne la provenienza e
trasformare soltanto i dati necessari in un override revisionabile. Estrarre
costanti da un binario è l'ultima scelta e richiede una nota di provenienza.

## 12. Verificare e archiviare l'acquisizione

Creare un manifesto dell'intero kit privato:

```sh
find inventory logs dt firmware raw -type f -print0 \
  | sort -z \
  | xargs -0 sha256sum \
  > ACQUISITION-SHA256SUMS

sha256sum -c ACQUISITION-SHA256SUMS
```

Registrare in un file di testo:

- modello e revisione PCB;
- build fingerprint Android;
- data e metodo di acquisizione;
- versione di ADB e degli strumenti host;
- percorso e dimensione dell'eMMC;
- dimensione del settore logico;
- accesso usato: `adbd root`, `su`, recovery, Loader o UMS;
- eventuali errori o letture ripetute.

Creare almeno due copie del kit. Cifrare quella che contiene dump Android o
dati identificativi.

## 13. Separare risorse private e sorgenti pubblicabili

| Materiale | Destinazione | Pubblicazione predefinita |
|---|---|---|
| IDB, security, U-Boot, trust, misc | `blobs/private/` | no |
| Dump boot/recovery/resource originali | archivio privato | no |
| GPT, offset, dimensioni e hash | documentazione/manifest | sì, dopo revisione |
| DTS riscritto e commentato | `dts/` | sì |
| Configurazione kernel | `configs/` | sì |
| Firmware con licenza verificata | rootfs/package | dipende dalla licenza |
| Moduli Android binari | archivio di evidenza | normalmente no |
| Log ripuliti da seriali/MAC | `HARDWARE-NOTES.md` | sì |
| `userdata`, account, chiavi | backup cifrato | mai |

Il repository esclude intenzionalmente `blobs/private/`. Non usare `git add -f`
per aggirare questa protezione.

## 14. Tradurre le prove in un BSP riproducibile

Non iniziare abilitando tutto. Costruire per fasi:

1. boot chain originale e UART;
2. microSD e rootfs minimale;
3. regolatori/PMIC e thermal;
4. display e input;
5. Wi-Fi, GPU e batteria;
6. audio, Bluetooth, USB OTG e suspend;
7. eMMC in scrittura, videocamere e acceleratori solo alla fine.

Ogni correzione provata nel sistema in esecuzione deve diventare uno di:

- modifica DTS;
- opzione kernel;
- firmware con hash e licenza;
- pacchetto/rootfs overlay;
- regola di build o validazione.

Per questo repository:

```sh
git clone https://github.com/ImChrono/K708_rk3326_debian.git
cd K708_rk3326_debian

./scripts/validate-source.sh
./scripts/prepare-blobs.sh /percorso/al/kit-privato
./scripts/fetch-kernel.sh ../rk3326-linux-6.1
./scripts/fetch-rtw88.sh
./scripts/build-kernel.sh ../rk3326-linux-6.1 ../rk3326-linux-6.1-out
```

Costruire poi rootfs e immagine seguendo il README. Iniziare dal profilo
`uart`; usare `display` soltanto dopo un boot seriale affidabile. Il profilo
`charge-test` non è un profilo generale: abilita la politica di carica OEM di
questo tablet e richiede un test sorvegliato.

## 15. Piani B quando ADB non basta

| Stato del tablet | Percorso consigliato | Cosa evitare |
|---|---|---|
| Android avvia, ADB senza root | raccogliere inventario; provare `adb root` e `su`; cercare recovery stock | exploit o patch di `boot` prima del backup |
| Recovery avvia e offre ADB root | ripetere i dump da recovery con partizioni smontate | wipe/factory reset |
| U-Boot risponde su UART | inventario `printenv`, `mmc list`, `part list`; boot di una microSD rescue | `saveenv`, `mmc write`, `mmc erase` |
| U-Boot supporta UMS | esporre eMMC al PC, rendere subito il device host read-only, poi usare `dd` | mount automatico in lettura/scrittura |
| Rockchip Loader visibile | usare `rkdeveloptool` soltanto per inventario e `rl` | tutti i comandi di scrittura/erase |
| Solo Maskrom | caricare in RAM un loader esatto e compatibile, poi leggere | loader casuale di un'altra scheda |
| Nessuna USB/UART | verificare alimentazione e test point; assistenza o lettura hardware professionale | cortocircuitare pad non identificati |

### Piano B1: recovery ADB

```sh
adb reboot recovery
adb wait-for-device
adb shell id
adb shell cat /proc/partitions
```

Molte recovery stock espongono soltanto `adb sideload` e non una shell root.
Se il bootloader permette di avviare temporaneamente una recovery fidata, è
preferibile un boot volatile al flash; non tutti i Rockchip implementano
Fastboot e lo sblocco può cancellare i dati.

### Piano B2: UART e USB Mass Storage di U-Boot

Sul K708 la console provata è UART2 M1 a 1.500.000 baud, livelli logici 3,3 V.
Non collegare mai un adattatore RS-232 o 5 V.

Comandi U-Boot inizialmente non distruttivi:

```text
version
printenv
mmc list
part list mmc 0
part list mmc 1
```

Il numero eMMC varia. Se `ums 0 mmc N` è disponibile, il computer vedrà un
nuovo disco. Identificarlo da modello e dimensione, impedire il mount
automatico e impostarlo read-only prima della copia:

```sh
lsblk -p -o NAME,SIZE,MODEL,SERIAL,TRAN,RM,MOUNTPOINTS
sudo blockdev --setro /dev/sdX
sudo blockdev --getro /dev/sdX
```

`/dev/sdX` è un segnaposto: non copiarlo alla cieca. Se non si riesce a
identificare un solo target certo, scollegare e fermarsi.

### Piano B3: Rockchip Loader o Maskrom

`rkdeveloptool` è lo strumento open source Rockchip per Rockusb. In Loader
mode:

```sh
sudo rkdeveloptool ld
sudo rkdeveloptool rci
sudo rkdeveloptool rfi
sudo rkdeveloptool ppt
```

Acquisizione read-only del layout K708, dopo aver verificato `ppt`:

```sh
sudo rkdeveloptool rl 64 8128 idb-area-lba64-8191.img
sudo rkdeveloptool rl 8192 8192 security.img
sudo rkdeveloptool rl 16384 8192 uboot_a.img
sudo rkdeveloptool rl 24576 8192 uboot_b.img
sudo rkdeveloptool rl 32768 8192 trust_a.img
sudo rkdeveloptool rl 40960 8192 trust_b.img
sudo rkdeveloptool rl 49152 8192 misc.img
```

Nel comando `rl`, inizio e lunghezza sono espressi in settori. Ripetere ogni
lettura in una seconda directory e confrontare gli hash.

In Maskrom può essere necessario `rkdeveloptool db LOADER.bin` per caricare
temporaneamente un loader in RAM e inizializzare DDR/eMMC. Il loader deve
provenire dal firmware esatto del tablet o essere noto compatibile con SoC,
memoria e scheda. Un loader generico RK3326 non è automaticamente sicuro.
Entrare fisicamente in Maskrom dipende dalla PCB: non cortocircuitare clock,
data o test point senza una mappa certa della revisione.

Durante una sessione di acquisizione non usare:

```text
wl  wlx  ul  gpt  prm  ef
```

## 16. Se il tablet non avvia più Android

Seguire questa progressione senza saltare livelli:

1. verificare cavo, alimentazione e enumerazione USB;
2. provare recovery stock senza wipe;
3. acquisire log UART dall'accensione;
4. provare il boot da microSD con una baseline già conosciuta;
5. cercare Loader con `rkdeveloptool ld`;
6. usare Maskrom solo con test point identificati e loader verificato;
7. se eMMC non risponde, fermarsi e valutare lettura hardware professionale.

La presenza di Maskrom non autorizza a riscrivere immediatamente IDB o GPT.
Prima serve una lettura verificata oppure un firmware stock completo e
autentico della stessa revisione. Una procedura di ripristino in scrittura deve
essere preparata separatamente, con target, offset e hash espliciti.

## 17. Condizioni di arresto

Fermarsi e investigare se:

- due dump della stessa regione hanno hash differenti;
- il settore logico non è 512 byte ma si stanno usando gli LBA K708;
- `by-name`, GPT e `/proc/partitions` non concordano;
- `uboot_a` e `uboot_b` sono attesi uguali ma differiscono senza spiegazione;
- i file non hanno le dimensioni previste;
- `dtc` non riconosce il DTB;
- il loader Rockchip richiede un binario di provenienza ignota;
- il computer mostra più dischi candidati al target UMS;
- l'operazione richiede una scrittura sull'eMMC prima di avere un backup.

Il risultato corretto non è soltanto un'immagine che avvia una volta: è un
insieme di prove, sorgenti, hash e procedure che permettono di ricostruire la
stessa distro senza dipendere da modifiche manuali sul tablet.

## Riferimenti primari

- [Android Debug Bridge](https://developer.android.com/tools/adb)
- [Android: flashing e rischio di cancellazione durante lo sblocco](https://source.android.com/docs/setup/test/running)
- [Linux e Device Tree](https://docs.kernel.org/devicetree/usage-model.html)
- [ABI Linux per `/sys/firmware/fdt`](https://docs.kernel.org/admin-guide/abi-testing-files.html)
- [Rockchip `rkdeveloptool`](https://github.com/rockchip-linux/rkdeveloptool)
- [Sintassi `ReadLBA` nel sorgente Rockchip](https://github.com/rockchip-linux/rkdeveloptool/blob/master/main.cpp)
