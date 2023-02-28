<p align="center">
  <a href="https://github.com/sunweaver/nextcloud-high-performance-backend-setup/blob/main/README.md">Deutsch</a> |
  <span>English</span>
</p>

# Easy setup for Nextcloud High performance backend, Signaling & Collabora Office


This script installs the Nextcloud High Performance Backend with its own coturn and signaling server, as well as Collabora Office as a Debian package. The installation is kept extra simple and thus also enables users with a few Unix/Linux skills an installation in about 5 minutes.

The Nextcloud HPB can be installed as a Debian package (only Debian Unstable) or from the current source code (for Debian Stable). The Collabora package is always installed as the latest package from the stable branch. Please note that Collabora Office in this version is limited to 20 users working simultaneously. Of course, you can also expand this at any time with a license key.

[**Here in the wiki you will find detailed installation instructions in German!**](https://github.com/sunweaver/nextcloud-high-performance-backend-setup/wiki/02-Setup-Script)

[**You can download the newest version of the script here**](https://github.com/sunweaver/nextcloud-high-performance-backend-setup/releases)

**Requirements**

* A virtual or physical server with Debian 11 (Bullseye)
* A subdomain for the server on which the script is installed

You are guided by 8 dialogues during the installation and then the packages are fully installed, configured and you will receive an overview with all the keys for the Nextcloud instance. The script can also manage several Nextcloud URLs on the server. In the script, simply enter these with commas sepparized(multidomain).


**The following systems/applications wil be installed:**

* Coturn
* Signaling
* Let’s Encrypt
* Nginx
* UfW Firewall
* SSH
* Collabora Office
* High Performance Backend

 
 

**For whom the script is intended:**

As a company, association or school, you often just want to rent a Nextcloud from a provider. There are good offers e. g. at Hetzner ([Storage Box](https://www.hetzner.com/de/storage/storage-box)) or Ionos. These offer a lot of storage space, but the computing power is often severely restricted.

The script can help here, as it outsources the missing performance-eating applications such as video conference (Talk) with more than 4 people and online office (Collabora Office) on our own server. Since you operate the server yourself, there are no GDPR problems. Among other things, [Hetzner Cloud Servers](https://www.hetzner.com/de/cloud) are very suitable for the script.

The script is also suitable for larger installations where the admin simply does not want to make the entire installation by hand. We stick strictly to the Debian requirements here so that later updates work smoothly. The script secures the server with the UFW firewall. In addition, you can also deactivate SSH access. Then you can only get access to the machine via the server console.

If the server is configured, ideally you don't need admin access to the machine via the internet, it is a pure work animal. The server is configured in such a way that it enables updates independently and restarts. If something goes wrong, you can either intervene yourself or simply create a new machine quickly, which is done in five minutes.


**Example application scenario**

[Nextcloud with video conference (Talk) and a connection to the school portal Hessen financed by the school support association in Germany!](https://github.com/sunweaver/nextcloud-high-performance-backend-setup/wiki/05-Bsp-Anwendungen)

 
**Donate or participate:**

Please always remember that free software does not exist for nothing. People spend their time behind all the projects, whether professionally or privately. It is important to participate in the development. You can support the projects financially or through your participation. This is the only way free software can get better and remain in the long term.

<https://nextcloud.com/contribute/>

I would like to thank the three companies Nextcloud GmbH, Structure AG and Collabora for the great software that enables us a self-determined free work in the cloud.

Mirco Rohloff
