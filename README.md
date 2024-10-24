# INSTALACION DE GUACAMOLE

```shell
wget https://raw.githubusercontent.com/zXMiguelXz/guacamole/refs/heads/main/1-setup.sh && chmod +x 1-setup.sh && ./1-setup.sh
```

** Antes de empezar, asegúrate de tener: **

- ** SO compatible: **
  -** Debian: 12.x o 11.x**
  - ** Ubuntu LTS variantes: 24.04, 23.04, 22.04 **
  - ** Raspbian Buster o Bullseye **
  - ** Imágenes oficiales en la nube del proveedor equivalentes a las versiones anteriores.** 
  -** 1 núcleo de CPU + 2GB RAM por cada 25 usuarios (más espacio mínimo de RAM y disco para su sistema operativo seleccionado).**
-** Puertos TCP abiertos: 22, 80 y 443 (ningún otro servicio que utilice 80, 8080 y 443)**
-** Si selecciona cualquiera de las opciones de proxy inverso de TLS, debe crear un registro DNS PRIVADO para el sitio proxy interno y un registro DNS PÚBLICO adicional si selecciona la opción Cifrar.**
- ** Paquetes de sudo y wget instalados **
-** El usuario que ejecuta el script 1-setup.sh debe tener permisos sudo **

## Instrucciones de Instalación Personalizadas

**Para personalizar con las muchas opciones de script disponibles:**

- Salida 1-setup.sh en el primer mensaje.
- Todas las opciones de script configurables se indican al inicio de 1-setup.sh 'en **Opciones de configuración silenciosa**. Vuelva a ejecutar el script de configuración editado después de realizar los cambios. (Ejecute esto localmente, no vuelva a ejecutar el enlace web de instalación automática). 
- Ciertas combinaciones de las opciones de configuración **Silent** permitirán una instalación totalmente desatendida que admita la implementación masiva o compilaciones de docker altamente personalizadas.

**Otras notas de instalación personalizadas útiles:**
-**Precaución:** Re-ejecutar el auto-instalador vuelve a descargar el conjunto de scripts y esto sobrescribirá todas sus ediciones de script. Por lo tanto, debe ejecutar 1-setup.sh LOCALMENTE después de la edición. Si se editan otros scripts, sus enlaces de descarga correspondientes en el script 1-setup.sh también deben ser comentados.
- Los scripts se actualizan automáticamente ** con la configuración de instalación elegida en 1a instalación** para crear un conjunto coincidente para futuras actualizaciones o adiciones de características consistentes. (Redescargar desde el enlace de instalación automática sobrescribirá estas actualizaciones.)
- El proxy inverso de Nginx está configurado de forma predeterminada para al menos TLS 1.2. Para sistemas antiguos, consulte las secciones comentadas del archivo ur/etc/nginx/nginx.confam después de la instalación.
- Un trabajo diario de copia de seguridad de MySQL se configura automáticamente bajo el crontab del propietario del script.
-**Nota de seguridad:** La opción Quick Connect trae algunas implicaciones de seguridad adicionales, tenga en cuenta los riesgos potenciales en su entorno.

**Opciones de script de endurecimiento posteriores a la instalación disponibles:**

- adadd-fail2ban.shal: Añade una política de bloqueo para Guacamole para protegerse contra ataques de contraseña de fuerza bruta.
- adadd-tls-guac-daemon.shal: Envuelve el tráfico interno entre el servidor guac y la aplicación guac en TLS.
- adadd-auth-ldap.shal: Script de plantilla para la integración simplificada de Active Directory SSO.
- adadd-smtp-relay-o365.sh: Script de plantilla para la integración de alertas de correo electrónico con MSO65 (Contraseña de la aplicación BYO).

## Integración de Active Directory SSO

**¿Necesita ayuda con la integración de Active Directory y la autenticación SSO?** Compruebe [aquí](https://github.com/zXMiguelXz/guacamole/blob/main/ACTIVE-DIRECTORY-HOW-TO.md).

## Actualización de Guacamole

**Para actualizar Guacamole (https://github.com/itiligent/Guacamole-Installer/blob/main/upgrade-guacamole.sh), edite upgrade-guacamole.sh para reflejar las últimas versiones de Guacamole & MySQL conector/J antes de ejecutar.** Este script también actualizará automáticamente las extensiones TOTP, DUO, LDAP, Quick Connect e History Recorded Storage si están presentes.


------------------------------------------------------------------------------------------------------------------------------------------------

# INSTALLATION OF GUACAMOLE

```
 shell
wget https://raw.githubusercontent.com/zXMiguelXz/guacamole/refs/heads/main/1-setup.sh && chmod +x 1-setup.sh & ./1-setup.sh
```

** Before you start, make sure you have: **

- ** Supported OS: **
  - ** Debian: 12.x or 11.x **
  - ** Ubuntu LTS variants: 24.04, 23.04, 22.04 **
  - ** Raspbian Buster or Bullseye **
  - ** Official cloud images of the provider equivalent to previous versions.** 
  - ** 1 CPU kernel + 2GB RAM for every 25 users (plus minimum RAM and disk space for your selected operating system).**
- ** Open TCP ports: 22, 80 and 443 (no other service using 80, 8080 and 443) **
- ** If you select any of the TLS reverse proxy options, you must create a PRIVATE DNS record for the internal proxy site and an additional PUBLIC DNS record if you select the Encrypt option.**
- ** installed sudo and wget packages **
- ** The user running the script 1-setup.sh must have sudo permissions **

## Custom Installation Instructions

** To customize with the many script options available: **

- Exit 1-setup.sh in the first message.
- All configurable script options are indicated at the beginning of 1-setup.sh 'in ** Silent configuration options **. Run the edited configuration script again after making the changes. (Run this locally, do not run the automatic installation web link again.) 
- Certain combinations of the ** Silent ** configuration options will allow a fully unattended installation that supports mass implementation or highly customized docker compilations.

** Other useful custom installation notes: **
- ** Caution: ** Re-run the auto-installer re-downloads the script set and this will overwrite all your script editions. Therefore, you must run 1-setup.sh LOCALLY after editing. If other scripts are edited, their corresponding download links in script 1-setup.sh should also be commented.
- Scripts are automatically updated ** with the installation settings chosen in 1st installation ** to create a matching set for future updates or additions of consistent features. (Redownloading from the automatic installation link will overwrite these updates.)
- The Nginx reverse proxy is configured by default for at least TLS 1.2. For older systems, see the commented sections of the ur / etc / nginx / nginx.confam file after installation.
- A daily MySQL backup job is automatically configured under the script owner's crontab.
- ** Security note: ** The Quick Connect option brings some additional security implications, keep in mind the potential risks in your environment.

** Post-installation hardening script options available: **

- adadd-fail2ban.shal: Adds a blocking policy for Guacamole to protect itself against brute force password attacks.
- adadd-tls-guac-daemon.shal: Wraps internal traffic between the guac server and the guac application in TLS.
- adadd-auth-ldap.shal: Template script for simplified integration of Active Directory SSO.
- adadd-smtp-relay-o365.sh: Template script for integrating email alerts with MSO65 (BYO application password).

## Integration of Active Directory SSO

** Need help with Active Directory integration and SSO authentication?** Check [here] (https://github.com/zXMiguelXz/guacamole/blob/main/ACTIVE-DIRECTORY-HOW-TO.md).

## Guacamole update

** To update Guacamole (https://github.com/itiligent/Guacamole-Installer/blob/main/upgrade-guacamole.sh), edit upgrade-guacamole.sh to reflect the latest versions of Guacamole & MySQL connector / J before running.** This script will also automatically update the TOTP, DUO, LDAP, Quick Connect and History Recorded Storage extensions if they are present.


