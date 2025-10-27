---
name: Fehlerbericht (Deutsch)
about: Erstelle einen Bericht um uns zu helfen das Projekt zu verbessern
title: '[BUG] '
labels: bug
assignees: ''
---

## Fehlerbeschreibung
Eine klare und präzise Beschreibung des Fehlers.

## Schritte zur Reproduktion
Schritte um das Verhalten zu reproduzieren:
1. Gehe zu '...'
2. Führe Befehl aus '....'
3. Siehe Fehler

## Erwartetes Verhalten
Eine klare und präzise Beschreibung dessen, was Sie erwartet haben.

## Tatsächliches Verhalten
Eine klare und präzise Beschreibung dessen, was tatsächlich passiert ist.

## Umgebung
- Debian Version: [z.B. Debian 12]
- Nextcloud Version: [z.B. 28.0.1]
- Script Version: [Ausgabe von `cat VERSION`]
- Architektur: [z.B. x86_64, aarch64]

## Log-Dateien
**Wichtig:** Das Setup-Script erstellt Log-Dateien mit dem Datum der Ausführung. Bitte hängen Sie relevante Log-Dateien an, aber **stellen Sie sicher, dass sensible Informationen zensiert werden** (Passwörter, Domains, IP-Adressen, etc.), bevor Sie diese hochladen.

### Setup Log
Speicherort: `setup-nextcloud-hpb-YYYY-MM-DDTHH:MM:SSZ.log` (im Script-Ausführungsverzeichnis)

<details>
<summary>Setup Log (zum Erweitern klicken)</summary>

```
Hier zensierten Log-Inhalt einfügen
```

</details>

### System Logs
Falls zutreffend, stellen Sie bitte auch die folgenden Logs zur Verfügung (denken Sie daran, sensible Daten zu zensieren):

<details>
<summary>Nginx Fehler-Logs</summary>

```bash
# Verwendeter Befehl:
$ sudo cat /var/log/nginx/*_error.log

# Ausgabe (zensiert):
Hier zensierte Ausgabe einfügen
```

</details>

<details>
<summary>Service Status</summary>

```bash
# Verwendete Befehle:
$ systemctl status nginx
$ systemctl status nats-server
$ systemctl status nextcloud-spreed-signaling
$ systemctl status janus
$ systemctl status coturn
$ systemctl status collabora

# Ausgabe:
Hier Ausgabe einfügen
```

</details>

## Screenshots
Falls zutreffend, fügen Sie Screenshots hinzu um Ihr Problem zu erklären.

## Zusätzlicher Kontext
Fügen Sie hier weiteren Kontext zum Problem hinzu.

## Checkliste
- [ ] Ich habe bestehende Issues auf Duplikate überprüft
- [ ] Ich habe alle sensiblen Informationen aus Logs und Screenshots zensiert
- [ ] Ich habe die Setup Log-Datei beigefügt
- [ ] Ich habe relevante System-Logs beigefügt
- [ ] Ich habe Screenshots hinzugefügt, wo zutreffend
