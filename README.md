<p align="center">
  <a href="https://github.com/sunweaver/nextcloud-high-performance-backend-setup/blob/main/README_en.md">English</a> |
  <span>Deutsch</span>
</p>

# Einfaches Setup für Nextcloud Hochleistungsbackend, Signaling & Collabora Office



**Vorsicht: Beschreibung gilt erst ab Version 1.0! Zurzeit nur für Debian Unstable**

Dieses Skript installiert vollautomatisch das Nextcloud High Performance Backend mit eigenem Coturn- und Signaling-Server, sowie Collabora Office als Debian-Paket. Die Installation ist extra einfach gehalten und ermöglicht dadurch auch Anwendern mit wenig Unix-/Linux-Kenntnissen eine Installation in ca. 5 Minuten.

Das Nextcloud HPB kann als Debian-Paket (nur Debian Unstable) oder aus den aktuellen Sourcen (für Debian Stable) installiert werden. Das Collabora-Paket wird immer als aktuellstes Paket aus dem Stable-Zweig installiert. Bitte beachten Sie, dass Collabora Office in dieser Version auf 20 gleichzeitig arbeitende Benutzer beschränkt ist. Dies können Sie natürlich durch eine Lizenz-Key auch jederzeit erweitern.

[**Hier im Wiki finden Sie eine detaillierte Installationsanleitung!**](https://github.com/sunweaver/nextcloud-high-performance-backend-setup/wiki/02-Setup-Script)

**Voraussetzungen für den Betrieb:**

* Einen virtuellen oder physikalischen Server mit Debian
* Eine Subdomain für den Server, auf dem das Skript installiert wird

Sie werden bei der Installation durch 8 Dialoge geführt und danach werden die Pakete voll automatisch installiert, konfiguriert und Sie erhalten eine Übersicht mit allen einzutragenden Schlüsseln für die Nextcloud-Instanz. Das Skript kann auch mehrere Nextcloud-URLs auf dem Server verwalten. Diese geben Sie in dem Script einfach mit Kommata separiert ein (Multidomain).

**Folgende Systeme/Anwendungen werden installiert:**

* Coturn
* Signaling
* Let’s Encrypt
* Nginx
* UfW Firewall
* SSH
* Collabora Office
* High Performance Backend

 

**Für wen das Skript gedacht ist:**

Oft möchte man als Betrieb, Verein oder Schule eine Nextcloud einfach nur bei einem Provider mieten. Da gibt es gute Angebote z. B. bei Hetzner ([Storage Box](https://www.hetzner.com/de/storage/storage-box)) oder Ionos. Diese bieten zwar viel Speicherplatz an, aber die Rechenleistung ist oft stark eingeschränkt.

Hier kann das Skript helfen, da wir damit die fehlenden leistungsfressenden Anwendungen wie Videokonferenz (Talk) mit mehr als 4 Personen und Online-Office (Collabora Office) auf einen eigenen Server auslagern. Da Sie den Server selbst betreiben, gibt es auch keine DSGVO-Probleme. Für das Script eignen sich unter aderen sehr gut [Hetzner Cloud Server](https://www.hetzner.com/de/cloud). 

Das Skript eignet sich aber auch für größere Installationen, bei denen der Admin einfach nicht die ganze Installation per Hand machen möchte. Wir halten uns hier streng an die Debian-Vorgaben, damit spätere Updates reibungslos funktionieren. Das Skript sichert den Server mit der UfW Firewall ab. Zusätzlich können Sie aber auch noch den SSH-Zugriff deaktivieren. Dann kommen Sie nur noch über die Server-Konsole an die Maschine ran.

Wenn der Server einmal konfiguriert ist, braucht man im Idealfall auch kein Admin-Zugriff auf die Maschine übers Netz, es ist ein reines Arbeitstier. Der Server ist so konfiguriert, dass er selbstständig Updates einspielt und neustartet. Falls dann doch mal etwas schief geht, können Sie entweder selbst eingreifen oder einfach schnell eine neue Maschine erstellen, das ist ja in fünf Minuten erledigt.

 

**Spenden oder Beteiligen:**

Bitte denken Sie immer daran, dass es auch freie Software nicht umsonst gibt. Hinter all den Projekten verbringen Menschen ihre Zeit, ob beruflich oder privat. Es ist wichtig sich an der Entwicklung zu beteiligen. Sie können die Projekte finanziell oder durch Ihre Beteiligung unterstützen. Nur so kann freie Software besser werden und bleibt uns allen langfristig erhalten.

<https://nextcloud.com/contribute/>

Ich möchte mich hier noch bei den drei Firmen Nextcloud GmbH, Struktur AG sowie Collabora für die tolle Software bedanken, die uns ein selbstbestimmtes freies Arbeiten in der Cloud ermöglicht.  

Mirco Rohloff
