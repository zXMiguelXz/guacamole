#!/bin/bash
######################################################################################################################
# Guacamole appliance setup script
# For Ubuntu / Debian / Raspbian
# David Harrop
# April 2023
#######################################################################################################################


# 1-setup.sh is a central script that manages all inputs, options and sequences other included 'install' scripts.
# 2-install-guacamole downloads Guacamole source and exectutes all Guacamole's build instructions.
# 3-install-nginx.sh automatically installs and configures Nginx to work as an http port 80 front end to Guacamole.
# 4a-install-tls-self-signed-nginx.sh sets up the new Nginx/Guacamole front end with self signed TLS certificates.
# 4b-install-tls-letsencrypt-nginx.sh sets up Nginx with public TLS certificates from LetsEncrypt.
# Scripts with "add" in their name can be run post install to add optional features not included in the main install.

# For troubleshooting check logs or place Guacamole in debug mode:
#     tail -f /var/log/syslog /var/log/tomcat*/*.out guac-setup/guacamole_setup.log
#     sudo systemctl stop guacd && sudo /usr/local/sbin/guacd -L debug -f

#######################################################################################################################
# Script pre-flight checks and settings ###############################################################################
#######################################################################################################################

clear

# Prepare text output colours
GREY='\033[0;37m'
DGREY='\033[0;90m'
GREYB='\033[1;37m'
LRED='\033[0;91m'
LGREEN='\033[0;92m'
LYELLOW='\033[0;93m'
NC='\033[0m' #No Colour

# Make sure the user is NOT running this script as root
if [[ $EUID -eq 0 ]]; then
    echo
    echo -e "${LRED}This script must NOT be run as root, it will prompt for sudo when needed." 1>&2
    echo -e ${NC}
    exit 1
fi

# Check if sudo is installed. (Debian does not always include sudo by default)
if ! command -v sudo &> /dev/null; then
    echo "${LRED}Sudo is not installed. Please install sudo."
    echo -e ${NC}
    exit 1
fi

# Make sure the user running setup is a member of the sudo group
if ! id -nG "$USER" | grep -qw "sudo"; then
    echo
    echo -e "${LRED}The current user (${USER}) must be a member of the 'sudo' group. Run: sudo usermod -aG sudo ${USER}${NC}" 1>&2
    exit 1
fi

# Check to see if any previous version of build files exist, if so stop and check to be safe.
if [[ "$(find . -maxdepth 1 \( -name 'guacamole-*' -o -name 'mysql-connector-j-*' \))" != "" ]]; then
    echo
    echo -e "${LRED}Possible previous install files detected in current build path. Please review and remove old guacamole install files before proceeding.${GREY}, exiting..." 1>&2
    echo
    exit 1
fi

# Query the OS version
source /etc/os-release
ID=$ID
VERSION_ID=$VERSION_ID
VERSION_CODENAME=$VERSION_CODENAME

#######################################################################################################################
# Core setup variables and mandatory inputs - EDIT VARIABLE VALUES TO SUIT ############################################
#######################################################################################################################

# Setup download and temp directory paths
USER_HOME_DIR=$(eval echo ~${SUDO_USER})
DOWNLOAD_DIR=$USER_HOME_DIR/guac-setup
DB_BACKUP_DIR=$USER_HOME_DIR/mysqlbackups
mkdir -p $DOWNLOAD_DIR
mkdir -p $DB_BACKUP_DIR

# GitHub download branch
GITHUB="https://raw.githubusercontent.com/zXMiguelXz/guacamole/main"

# Version of Guacamole to install
GUAC_VERSION="1.5.5"
GUAC_SOURCE_LINK="http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VERSION}"

# MySQL Connector/J version to install
MYSQLJCON="8.4.0"
MYSQLJCON_SOURCE_LINK="https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-${MYSQLJCON}.tar.gz"

# Provide a specific MySQL version e.g. 11.1.2 or leave blank "" to use distro default MySQL packages.
# See https://mariadb.org/mariadb/all-releases/ for available versions.
MYSQL_VERSION=""
MARIADB_SOURCE_LINK="https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"

# Reverse proxy uses this URL (Guacamole default is http://localhost:8080/guacamole/):
GUAC_URL=http://localhost:8080/guacamole/

# Get the default route interface IP. May need to manually override this for multi homed systems or where cloud images may use 127.0.x.x
DEFAULT_IP=$(ip addr show $(ip route | awk '/default/ { print $5 }') | grep "inet" | head -n 1 | awk '/inet/ {print $2}' | cut -d'/' -f1)

# Install log Location
INSTALL_LOG="${DOWNLOAD_DIR}/guacamole_install.log"

#######################################################################################################################
# Silent setup options - true/false or specific values below will skip prompt at install. EDIT TO SUIT ################
#######################################################################################################################
SERVER_NAME=""                  # Server hostname (blank = use the current hostname)
LOCAL_DOMAIN=""                 # Local DNS namespace/domain suffix (blank = keep the current suffix)
INSTALL_MYSQL=""                # Install MySQL locally (true/false)
SECURE_MYSQL=""                 # Apply mysql secure configuration tool (true/false)
MYSQL_HOST=""                   # Blank "" = localhost MySQL install, adding a specific IP address will assume a remote MySQL instance
MYSQL_PORT=""                   # If blank "" default is 3306
GUAC_DB=""                      # If blank "" default is guacamole_db
GUAC_USER=""                    # If blank "" default is guacamole_user
MYSQL_ROOT_PWD=""               # Manadatory entry here or at script prompt
GUAC_PWD=""                     # Manadatory entry here or at script prompt
DB_TZ=$(cat /etc/timezone)      # Blank "" defaults to UTC, for local timezone: $(cat /etc/timezone)
INSTALL_TOTP=""                 # Add TOTP MFA extension (true/false), can't be installed simultaneously with DUO)
INSTALL_DUO=""                  # Add DUO MFA extension (true/false, can't be installed simultaneously with TOTP)
INSTALL_LDAP=""                 # Add Active Directory extension (true/false)
INSTALL_QCONNECT=""             # Add Guacamole console quick connect feature (true/false)
INSTALL_HISTREC=""              # Add Guacamole history recording storage feature (true/false)
HISTREC_PATH=""                 # If blank "" sets the Apache's default path of /var/lib/guacamole/recordings
GUAC_URL_REDIR=""               # Auto redirect of host root URL http://xxx:8080 to http://xxx:8080/guacamole  (true/false)
INSTALL_NGINX=""                # Install & configure Nginx reverse proxy http:80 frontend (true/false)
PROXY_SITE=""                   # Local DNS name for reverse proxy site and/or self signed TLS certificates (blank "" defaults to $DEFAULT_FQDN)
SELF_SIGN=""                    # Add self signed TLS/https support to Nginx (true/false, Let's Encrypt not available with this option)
RSA_KEYLENGTH="2048"            # Self signed RSA TLS key length. At least 2048, must not be blank
CERT_COUNTRY="AU"               # Self signed cert setup, 2 character country code only, must not be blank
CERT_STATE="Victoria"           # Self signed cert setup, must not be blank
CERT_LOCATION="Melbourne"       # Self signed cert setup, must not be blank
CERT_ORG="zXMiguelXz"            # Self signed cert setup, must not be blank
CERT_OU="I.T."                  # Self signed cert setup, must not be blank
CERT_DAYS="3650"                # Self signed cert setup, days until self signed TLS cert expiry, blank = default 3650
LETS_ENCRYPT=""                 # Add Lets Encrypt public TLS cert for Nginx (true/false, self signed TLS not available with this option) 
LE_DNS_NAME=""                  # Public DNS name for use with Lets Encrypt certificates, must match public DNS
LE_EMAIL=""                     # Webmaster email for Lets Encrypt notifications
BACKUP_EMAIL=""                 # Email address to send MySQL backup notifications to
BACKUP_RETENTION="30"           # Days to keep SQL backups locally
RDP_SHARE_HOST=""               # Custom RDP host name shown in Windows Explorer (eg. "RDP_SHARE_LABEL on RDP_SHARE_HOST"). Blank "" = $SERVER_NAME
RDP_SHARE_LABEL="RDP Share"     # Custom RDP shared drive name in Windows Explorer (eg. "RDP_SHARE_LABEL on RDP_SHARE_HOST" eg. "your RDP share name on server01"
RDP_PRINTER_LABEL="RDP Printer" # Custom RDP printer name shown in Windows

#######################################################################################################################
# Download GitHub setup scripts. BEFORE RUNNING SETUP, COMMENT OUT DOWNLOAD LINES OF ANY SCRIPTS YOU HAVE EDITED ! ####
#######################################################################################################################

# Script branding header
echo
echo -e "${GREYB}Guacamole ${GUAC_VERSION} Auto Installer."
echo -e "              ${LGREEN}Powered by zXMiguelXz"
echo
echo

# Download the suite of install scripts from GitHub
cd $DOWNLOAD_DIR
echo -e "${GREY}Downloading the Guacamole build suite...${DGREY}"
wget -q --show-progress ${GITHUB}/2-install-guacamole.sh -O 2-install-guacamole.sh
wget -q --show-progress ${GITHUB}/3-install-nginx.sh -O 3-install-nginx.sh
wget -q --show-progress ${GITHUB}/4a-install-tls-self-signed-nginx.sh -O 4a-install-tls-self-signed-nginx.sh
wget -q --show-progress ${GITHUB}/4b-install-tls-letsencrypt-nginx.sh -O 4b-install-tls-letsencrypt-nginx.sh

# Download the suite of optional feature adding scripts
wget -q --show-progress ${GITHUB}/guac-optional-features/add-auth-duo.sh -O add-auth-duo.sh
wget -q --show-progress ${GITHUB}/guac-optional-features/add-auth-ldap.sh -O add-auth-ldap.sh
wget -q --show-progress ${GITHUB}/guac-optional-features/add-auth-totp.sh -O add-auth-totp.sh
wget -q --show-progress ${GITHUB}/guac-optional-features/add-xtra-quickconnect.sh -O add-xtra-quickconnect.sh
wget -q --show-progress ${GITHUB}/guac-optional-features/add-xtra-histrecstor.sh -O add-xtra-histrecstor.sh
wget -q --show-progress ${GITHUB}/guac-optional-features/add-smtp-relay-o365.sh -O add-smtp-relay-o365.sh
wget -q --show-progress ${GITHUB}/guac-optional-features/add-tls-guac-daemon.sh -O add-tls-guac-daemon.sh
wget -q --show-progress ${GITHUB}/guac-optional-features/add-fail2ban.sh -O add-fail2ban.sh
wget -q --show-progress ${GITHUB}/guac-management/backup-guacamole.sh -O backup-guacamole.sh
wget -q --show-progress https://raw.githubusercontent.com/zXMiguelXz/guacamole/main/upgrade-guacamole.sh -O upgrade-guacamole.sh


# Pause here to optionally customise downloaded scripts before any actual install actions begin
echo -e "${LYELLOW}Ctrl+Z now to exit now if you wish to customise 1-setup.sh options or create an unattended install."
echo

# This first sudo command is a trigger to pause for setup script customisation shown above, then to continue as sudo where needed.
sudo apt-get update -qq &> /dev/null

#######################################################################################################################
# Package dependency handling and workarounds for various distros, MODIFY ONLY IF NEEDED ##############################
#######################################################################################################################

# Standardise on a lexicon for the different MySQL package options
if [[ -z "${MYSQL_VERSION}" ]]; then
    # Use Linux distro default version.
    MYSQLSRV="default-mysql-server default-mysql-client mysql-common" # Server
    MYSQLCLIENT="default-mysql-client" # Client
    DB_CMD="mysql" # The mysql -v command is depricated on some versions.
else
    # Use official mariadb.org repo
    MYSQLSRV="mariadb-server mariadb-client mariadb-common" # Server
    MYSQLCLIENT="mariadb-client" # Client
    DB_CMD="mariadb" # The mysql -v command is depricated on some versions.
fi

# Standardise on a lexicon for the differing dependency package names between distros
# Current package names for various distros are referenced at https://guacamole.apache.org/doc/gug/installing-guacamole.html
JPEGTURBO=""
LIBPNG=""
if [[ ${ID,,} = "ubuntu" ]] || [[ ${ID,,} = *"ubuntu"* ]] || [[ ${ID,,} = *"linuxmint"* ]]; then
    JPEGTURBO="libjpeg-turbo8-dev"
    LIBPNG="libpng-dev"
    # Just in case this repo is not present in the distro
    sudo add-apt-repository -y universe &>>${INSTALL_LOG}
elif [[ ${ID,,} = "debian" ]] || [[ ${ID,,} = "raspbian" ]]; then
    JPEGTURBO="libjpeg62-turbo-dev"
    LIBPNG="libpng-dev"
fi

# Check for the more recent versions of Tomcat currently supported by the distro
if [[ $(apt-cache show tomcat10 2>/dev/null | egrep "Version: 10" | wc -l) -gt 0 ]]; then
    TOMCAT_VERSION="tomcat10"
elif [[ $(apt-cache show tomcat9 2>/dev/null | egrep "Version: 9" | wc -l) -gt 0 ]]; then
    TOMCAT_VERSION="tomcat9"
else
    # Default to this version
    TOMCAT_VERSION="tomcat9"
fi

#######################################################################################################################
# Ongoing fixes and workarounds as distros diverge/change #############################################################
#######################################################################################################################

# Workaround for Debian incompatibilities with later Tomcat versions. (Adds the oldstable repo and downgrades the Tomcat version)
if [[ ${ID,,} = "debian" && ${VERSION_CODENAME,,} = *"bookworm"* ]] || [[ ${ID,,} = "debian" && ${VERSION_CODENAME,,} = *"trixie"* ]]; then #(checks for upper and lower case)
    echo "deb http://deb.debian.org/debian/ bullseye main" | sudo tee /etc/apt/sources.list.d/bullseye.list &> /dev/null
    sudo apt-get update -qq &> /dev/null
    TOMCAT_VERSION="tomcat9"
fi

# Workaround for Ubuntu 23.x Tomcat 10 incompatibilities. Downgrades Tomcat to version 9 which is available from the Lunar repo.
if [[ ${ID,,} = "ubuntu" ]] && [[ ${VERSION_CODENAME,,} = *"lunar"* ]]; then
    TOMCAT_VERSION="tomcat9"
fi

# Workaround for Ubuntu 24.x Tomcat 10 incompatibilities. (Adds old Jammy repo and downgrades the Tomcat version)
if [[ ${ID,,} = "ubuntu" && ${VERSION_CODENAME,,} = *"noble"* ]]; then
    echo "deb http://archive.ubuntu.com/ubuntu/ jammy universe" | sudo tee /etc/apt/sources.list.d/jammy.list &> /dev/null
    sudo apt-get update -qq &> /dev/null
    TOMCAT_VERSION="tomcat9"
fi

# Uncomment here to force a specific Tomcat version.
# TOMCAT_VERSION="tomcat9"

# Workaround for 1.5.4 specific bug, see issue #31. This was fixed in 1.5.5
if [[ "${ID,,}" = "debian" && "${VERSION_CODENAME,,}" = *"bullseye"* ]] || [[ "${ID,,}" = "ubuntu" && "${VERSION_CODENAME,,}" = *"focal"* ]]; then
    IFS='.' read -ra guac_version_parts <<< "${GUAC_VERSION}"
    major="${guac_version_parts[0]}"
    minor="${guac_version_parts[1]}"
    patch="${guac_version_parts[2]}"
    # Uncomment 2nd line and comment first line if issue returns >=1.5.4 (See https://issues.apache.org/jira/browse/GUACAMOLE-1892))
	if (( major == 1 && minor == 5 && patch == 4 )); then
	#if (( major > 1 || (major == 1 && minor > 5) || ( major == 1 && minor == 5 && patch >= 4 ) )); then
      export LDFLAGS="-lrt"
    fi
fi

#######################################################################################################################
# DO NOT EDIT PAST THIS POINT! ########################################################################################
#######################################################################################################################

# An intitial dns suffix is needed as a starting value for the script prompts
get_domain_suffix() {
    echo "$1" | awk '{print $2}'
}
# Search for "search" and "domain" entries in /etc/resolv.conf
search_line=$(grep -E '^search[[:space:]]+' /etc/resolv.conf)
domain_line=$(grep -E '^domain[[:space:]]+' /etc/resolv.conf)
# Check if both "search" and "domain" lines exist
if [[ -n "$search_line" ]] && [[ -n "$domain_line" ]]; then
    # Both "search" and "domain" lines exist, extract the domain suffix from both
    search_suffix=$(get_domain_suffix "$search_line")
    domain_suffix=$(get_domain_suffix "$domain_line")
    # Print the domain suffix that appears first
    if [[ ${#search_suffix} -lt ${#domain_suffix} ]]; then
        DOMAIN_SUFFIX=$search_suffix
    else
        DOMAIN_SUFFIX=$domain_suffix
    fi
elif [[ -n "$search_line" ]]; then
    # If only "search" line exists
    DOMAIN_SUFFIX=$(get_domain_suffix "$search_line")
elif [[ -n "$domain_line" ]]; then
    # If only "domain" line exists
    DOMAIN_SUFFIX=$(get_domain_suffix "$domain_line")
else
    # If no "search" or "domain" lines found
    DOMAIN_SUFFIX="local"
fi

#######################################################################################################################
# Begin install menu prompts ##########################################################################################
#######################################################################################################################

# Consistent /etc/hosts and domain suffix values are needed for TLS implementation. The below approach
# allows the user to either hit enter at the prompt to keep current values, or enter new values for both. Silent install
# pre-set values (if provided) will bypass these prompts.

# Prompt to install MySQL
echo -e "${LGREEN}MySQL setup options:${GREY}"
if [[ -z ${INSTALL_MYSQL} ]]; then
    echo -e -n "SQL: Install MySQL locally? (For a REMOTE MySQL server select 'n') [y/n] [default y]: ${GREY}"
    read PROMPT
    if [[ ${PROMPT} =~ ^[Nn]$ ]]; then
        INSTALL_MYSQL=false
    else
        INSTALL_MYSQL=true
    fi
fi

# Prompt to apply the Mysql secure installation locally
if [[ -z ${SECURE_MYSQL} ]] && [[ "${INSTALL_MYSQL}" = true ]]; then
    echo -e -n "${GREY}SQL: Apply MySQL secure installation settings to LOCAL db? [y/n] [default y]: ${GREY}"
    read PROMPT
    if [[ ${PROMPT} =~ ^[Nn]$ ]]; then
        SECURE_MYSQL=false
    else
        SECURE_MYSQL=true
    fi
fi

# Prompt for additional MYSQL settings and values
if [[ "${INSTALL_MYSQL}" = false ]]; then
    [[ -z "${MYSQL_HOST}" ]] &&
        read -p "SQL: Enter remote MySQL server hostname or IP: " MYSQL_HOST
    [[ -z "${MYSQL_PORT}" ]] &&
        read -p "SQL: Enter remote MySQL server port [3306]: " MYSQL_PORT
    [[ -z "${GUAC_DB}" ]] &&
        read -p "SQL: Enter remote Guacamole database name [guacamole_db]: " GUAC_DB
    [[ -z "${GUAC_USER}" ]] &&
        read -p "SQL: Enter remote Guacamole user name [guacamole_user]: " GUAC_USER
fi
# Checking if a mysql host given, if not set a default
if [[ -z "${MYSQL_HOST}" ]]; then
    MYSQL_HOST="localhost"
fi
# Checking if a mysql port given, if not set a default
if [[ -z "${MYSQL_PORT}" ]]; then
    MYSQL_PORT="3306"
fi
# Checking if a database name given, if not set a default
if [[ -z "${GUAC_DB}" ]]; then
    GUAC_DB="guacamole_db"
fi
# Checking if a mysql user given, if not set a default
if [[ -z "${GUAC_USER}" ]]; then
    GUAC_USER="guacamole_user"
fi

# Prompt for MySQL root password, confirm correct password entry and prevent blank passwords. No root pw needed for remote instances.
if [[ -z "${MYSQL_ROOT_PWD}" ]] && [[ "${INSTALL_MYSQL}" = true ]]; then
    while true; do
        read -s -p "SQL: Enter ${MYSQL_HOST}'s MySQL ROOT password: " MYSQL_ROOT_PWD
        echo
        read -s -p "SQL: Confirm ${MYSQL_HOST}'s MySQL ROOT password: " PROMPT2
        echo
        [[ "${MYSQL_ROOT_PWD}" = "${PROMPT2}" ]] && [[ "${MYSQL_ROOT_PWD}" != "" ]] && [[ "${PROMPT2}" != "" ]] && break
        echo -e "${LRED}Passwords don't match or can't be null. Please try again.${GREY}" 1>&2
    done
fi

# Prompt for Guacamole User password, confirm correct password entry and prevent blank passwords
if [[ -z "${GUAC_PWD}" ]]; then
    while true; do
        read -s -p "SQL: Enter ${MYSQL_HOST}'s MySQL ${GUAC_USER} password: " GUAC_PWD
        echo
        read -s -p "SQL: Confirm ${MYSQL_HOST}'s MySQL ${GUAC_USER} password: " PROMPT2
        echo
        [[ "${GUAC_PWD}" = "${PROMPT2}" ]] && [[ "${GUAC_PWD}" != "" ]] && [[ "${PROMPT2}" != "" ]] && break
        echo -e "${LRED}Passwords don't match or can't be null. Please try again.${GREY}" 1>&2
    done
fi

# Prompt for preferred backup notification email address
if [[ -z ${BACKUP_EMAIL} ]]; then
    while true; do
        read -p "SQL: Enter email address for SQL backup messages [Enter to skip]: " BACKUP_EMAIL
        [[ "${BACKUP_EMAIL}" = "" ]] || [[ "${BACKUP_EMAIL}" != "" ]] && break
        # Rather than allow a blank value, un-comment to alternately force user to enter an explicit value instead
        # [[ "${BACKUP_EMAIL}" != "" ]] && break
        # echo -e "${LRED}You must enter an email address. Please try again.${GREY}" 1>&2
    done
fi
# If no backup notification email address is given, provide a non blank default value
if [[ -z ${BACKUP_EMAIL} ]]; then
    BACKUP_EMAIL="backup-email@yourdomain.com"
fi

echo
# Prompt to install TOTP MFA
echo -e "${LGREEN}Guacamole authentication extension options:${GREY}"
if [[ -z "${INSTALL_TOTP}" ]] && [[ "${INSTALL_DUO}" != true ]]; then
    echo -e -n "AUTH: Install TOTP? (choose 'n' if you want Duo) [y/n]? [default n]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        INSTALL_TOTP=true
        INSTALL_DUO=false
    else
        INSTALL_TOTP=false
    fi
fi

# Prompt to install Duo MFA
if [[ -z "${INSTALL_DUO}" ]] && [[ "${INSTALL_TOTP}" != true ]]; then
    echo -e -n "${GREY}AUTH: Install Duo? [y/n] [default n]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        INSTALL_DUO=true
        INSTALL_TOTP=false
    else
        INSTALL_DUO=false
    fi
fi

# We can't install TOTP and Duo at the same time (option not supported by Guacamole)
if [[ "${INSTALL_TOTP}" = true ]] && [[ "${INSTALL_DUO}" = true ]]; then
    echo -e "${LRED}GUAC MFA: TOTP and Duo cannot be installed at the same time.${GREY}" 1>&2
    exit 1
fi

# Prompt to install Duo MFA
if [[ -z "${INSTALL_LDAP}" ]]; then
    echo -e -n "${GREY}AUTH: Install LDAP? [y/n] [default n]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        INSTALL_LDAP=true
    else
        INSTALL_LDAP=false
    fi
fi

echo
# Prompt to install the Quick Connect feature (some higher security use cases may not want this)
echo -e "${LGREEN}Guacamole console optional extras:${GREY}"
if [[ -z "${INSTALL_QCONNECT}" ]]; then
    echo -e -n "${GREY}EXTRAS: Install Quick Connect feature? [y/n] [default n]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        INSTALL_QCONNECT=true
    else
        INSTALL_QCONNECT=false
    fi
fi

# Prompt to install the History Recorded Storage feature
if [[ -z "${INSTALL_HISTREC}" ]]; then
    echo -e -n "${GREY}EXTRAS: Install History Recorded Storage feature [y/n] [default n]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        INSTALL_HISTREC=true
    else
        INSTALL_HISTREC=false
    fi
fi

HISTREC_PATH_DEFAULT=/var/lib/guacamole/recordings # Apache default
if [[ -z ${HISTREC_PATH} ]] && [[ "${INSTALL_HISTREC}" = true ]]; then
    while true; do
        read -p "EXTRAS: Enter recorded storage path [Enter for default ${HISTREC_PATH_DEFAULT}]: " HISTREC_PATH
        [[ "${HISTREC_PATH}" = "" ]] || [[ "${HISTREC_PATH}" != "" ]] && break
    done
fi

# If no custom path is given, assume the Apache default path on hitting enter
if [[ -z "${HISTREC_PATH}" ]]; then
    HISTREC_PATH="${HISTREC_PATH_DEFAULT}"
fi

echo
# Prompt for Guacamole front end reverse proxy option
echo -e "${LGREEN}Reverse Proxy & front end options:${GREY}"
if [[ -z ${INSTALL_NGINX} ]]; then
    echo -e -n "FRONT END: Protect Guacamole behind Nginx reverse proxy [y/n]? [default n]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        INSTALL_NGINX=true
        GUAC_URL_REDIR=false
    else
        INSTALL_NGINX=false
    fi
fi

# Prompt to redirect http://root:8080 to http://root:8080/guacamole if not installing reverse proxy
if [[ -z ${GUAC_URL_REDIR} ]] && [[ "${INSTALL_NGINX}" = false ]]; then
    echo -e -n "FRONT END: Redirect Guacamole http://domain.root:8080 to /guacamole [y/n]? [default y]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Nn]$ ]]; then
        GUAC_URL_REDIR=false
    else
        GUAC_URL_REDIR=true
    fi
fi

# We must assign a DNS name for the new proxy site
if [[ -z ${PROXY_SITE} ]] && [[ "${INSTALL_NGINX}" = true ]]; then
    while true; do
        read -p "FRONT END: Enter proxy LOCAL DNS name? [Enter to use ${DEFAULT_FQDN}]: " PROXY_SITE
        [[ "${PROXY_SITE}" = "" ]] || [[ "${PROXY_SITE}" != "" ]] && break
        # Rather than allow the default value below, un-comment to alternately force user to enter an explicit name instead
        # [[ "${PROXY_SITE}" != "" ]] && break
        # echo -e "${LRED}You must enter a proxy site DNS name. Please try again.${GREY}" 1>&2
    done
fi

# If no proxy site dns name is given, lets assume the default FQDN is the proxy site name
if [[ -z "${PROXY_SITE}" ]]; then
    PROXY_SITE="${DEFAULT_FQDN}"
fi

# Prompt for self signed TLS reverse proxy option
if [[ -z ${SELF_SIGN} ]] && [[ "${INSTALL_NGINX}" = true ]]; then
    # Prompt the user to see if they would like to install self signed TLS support for Nginx, default of no
    echo -e -n "FRONT END: Add self signed TLS support to Nginx? [y/n]? (choose 'n' for Let's Encrypt)[default n]: "
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        SELF_SIGN=true
        LETS_ENCRYPT=false
    else
        SELF_SIGN=false
    fi
fi

# Prompt to enter a self sign TLS certificate expiry
if [[ -z "${CERT_DAYS}" ]] && [[ "${SELF_SIGN}" = true ]]; then
    while true; do
    read -p "FRONT END: Enter number of days till TLS certificates will expire [Enter for ${CERT_DAYS}]: " CERT_DAYS
        [[ "${CERT_DAYS}" = "" ]] || [[ "${CERT_DAYS}" != "" ]] && break
    done
fi
# If no self sign TLS certificate expiry given, lets assume a generous 10 year default certificate expiry
if [[ -z "${CERT_DAYS}" ]]; then
    CERT_DAYS="3650"
fi

# Prompt for Let's Encrypt TLS reverse proxy configuration option
if [[ -z ${LETS_ENCRYPT} ]] && [[ "${INSTALL_NGINX}" = true ]] && [[ "${SELF_SIGN}" = false ]]; then
    echo -e -n "FRONT END: Add Let's Encrypt TLS support to Nginx reverse proxy [y/n] [default n]: ${GREY}"
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        LETS_ENCRYPT=true
        SELF_SIGN=false
    else
        LETS_ENCRYPT=false
    fi
fi

# Prompt for Let's Encrypt public dns name
if [[ -z ${LE_DNS_NAME} ]] && [[ "${LETS_ENCRYPT}" = true ]] && [[ "${SELF_SIGN}" = false ]]; then
    while true; do
        read -p "FRONT END: Enter the PUBLIC FQDN for your proxy site : " LE_DNS_NAME
        [[ "${LE_DNS_NAME}" != "" ]] && break
        echo -e "${LRED}You must enter a public DNS name. Please try again.${GREY}" 1>&2
    done
fi

# Prompt for Let's Encrypt admin email
if [[ -z ${LE_EMAIL} ]] && [[ "${LETS_ENCRYPT}" = true ]] && [[ "${SELF_SIGN}" = false ]]; then
    while true; do
        read -p "FRONT END: Enter the email address for Let's Encrypt notifications : " LE_EMAIL
        [[ "${LE_EMAIL}" != "" ]] && break
        echo -e "${LRED}You must enter an email address. Please try again.${GREY}" 1>&2
    done
fi

#######################################################################################################################
# Start global setup actions  #########################################################################################
#######################################################################################################################

clear
echo
echo -e "${GREYB}Guacamole ${GUAC_VERSION} Auto Installer."
echo -e "              ${LGREEN}Powered by zXMiguelXz"
echo
echo

echo -e "${LGREEN}Beginning Guacamole setup...${GREY}"
echo

echo -e "${GREY}Synchronising the install script suite with the selected installation options..."
# Sync the various manual config scripts with the relevant variables selected at install
# This way scripts can be run at a later time without modification to match the original install
sed -i "s|MYSQL_HOST=|MYSQL_HOST='${MYSQL_HOST}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|MYSQL_PORT=|MYSQL_PORT='${MYSQL_PORT}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|GUAC_USER=|GUAC_USER='${GUAC_USER}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|GUAC_PWD=|GUAC_PWD='${GUAC_PWD}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|GUAC_DB=|GUAC_DB='${GUAC_DB}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|DB_BACKUP_DIR=|DB_BACKUP_DIR='${DB_BACKUP_DIR}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|BACKUP_EMAIL=|BACKUP_EMAIL='${BACKUP_EMAIL}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|BACKUP_RETENTION=|BACKUP_RETENTION='${BACKUP_RETENTION}'|g" $DOWNLOAD_DIR/backup-guacamole.sh

sed -i "s|CERT_COUNTRY=|CERT_COUNTRY='${CERT_COUNTRY}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh
sed -i "s|CERT_STATE=|CERT_STATE='${CERT_STATE}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh
sed -i "s|CERT_LOCATION=|CERT_LOCATION='${CERT_LOCATION=}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh
sed -i "s|CERT_ORG=|CERT_ORG='${CERT_ORG}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh
sed -i "s|CERT_OU=|CERT_OU='${CERT_OU}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh
sed -i "s|CERT_DAYS=|CERT_DAYS='${CERT_DAYS}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh

sed -i "s|INSTALL_MYSQL=|INSTALL_MYSQL='${INSTALL_MYSQL}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|MYSQL_HOST=|MYSQL_HOST='${MYSQL_HOST}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|MYSQL_PORT=|MYSQL_PORT='${MYSQL_PORT}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|GUAC_DB=|GUAC_DB='${GUAC_DB}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|MYSQL_ROOT_PWD=|MYSQL_ROOT_PWD='${MYSQL_ROOT_PWD}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|GUAC_USER=|GUAC_USER='${GUAC_USER}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|GUAC_PWD=|GUAC_PWD='${GUAC_PWD}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh

sed -i "s|RDP_SHARE_HOST=|RDP_SHARE_HOST='${RDP_SHARE_HOST}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|RDP_SHARE_LABEL=|RDP_SHARE_LABEL='${RDP_SHARE_LABEL}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|RDP_PRINTER_LABEL=|RDP_PRINTER_LABEL='${RDP_PRINTER_LABEL}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh

sed -i "s|PROXY_SITE=|PROXY_SITE='${PROXY_SITE}'|g" $DOWNLOAD_DIR/3-install-nginx.sh
sed -i "s|INSTALL_LOG=|INSTALL_LOG='${INSTALL_LOG}'|g" $DOWNLOAD_DIR/3-install-nginx.sh
sed -i "s|GUAC_URL=|GUAC_URL='${GUAC_URL}'|g" $DOWNLOAD_DIR/3-install-nginx.sh

sed -i "s|DOWNLOAD_DIR=|DOWNLOAD_DIR='${DOWNLOAD_DIR}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|PROXY_SITE=|PROXY_SITE='${PROXY_SITE}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_COUNTRY=|CERT_COUNTRY='${CERT_COUNTRY}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_STATE=|CERT_STATE='${CERT_STATE}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_LOCATION=|CERT_LOCATION='${CERT_LOCATION=}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_ORG=|CERT_ORG='${CERT_ORG}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_OU=|CERT_OU='${CERT_OU}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_DAYS=|CERT_DAYS='${CERT_DAYS}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|GUAC_URL=|GUAC_URL='${GUAC_URL}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|INSTALL_LOG=|INSTALL_LOG='${INSTALL_LOG}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|DEFAULT_IP=|DEFAULT_IP='${DEFAULT_IP}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|RSA_KEYLENGTH=|RSA_KEYLENGTH='${RSA_KEYLENGTH}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh

sed -i "s|DOWNLOAD_DIR=|DOWNLOAD_DIR='${DOWNLOAD_DIR}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh
sed -i "s|PROXY_SITE=|PROXY_SITE='${PROXY_SITE}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh
sed -i "s|GUAC_URL=|GUAC_URL='${GUAC_URL}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh
sed -i "s|LE_DNS_NAME=|LE_DNS_NAME='${LE_DNS_NAME}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh
sed -i "s|LE_EMAIL=|LE_EMAIL='${LE_EMAIL}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh
sed -i "s|INSTALL_LOG=|INSTALL_LOG='${INSTALL_LOG}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh

sed -i "s|LOCAL_DOMAIN=|LOCAL_DOMAIN='${LOCAL_DOMAIN}'|g" $DOWNLOAD_DIR/add-smtp-relay-o365.sh
if [[ $? -ne 0 ]]; then
    echo -e "${LRED}Failed. See ${INSTALL_LOG}${GREY}" 1>&2
    exit 1
else
    echo -e "${LGREEN}OK${GREY}"
    echo
fi

# Export the required variables for use by child install scripts
export DOWNLOAD_DIR="${DOWNLOAD_DIR}"
export GUAC_VERSION=$GUAC_VERSION
export GUAC_SOURCE_LINK=$GUAC_SOURCE_LINK
export ID=$ID
export VERSION_ID=$VERSION_ID
export VERSION_CODENAME=$VERSION_CODENAME
export MYSQLJCON=$MYSQLJCON
export MYSQLJCON_SOURCE_LINK=$MYSQLJCON_SOURCE_LINK
export MYSQL_VERSION=$MYSQL_VERSION
export MARIADB_SOURCE_LINK=$MARIADB_SOURCE_LINK
export MYSQLSRV=$MYSQLSRV
export MYSQLCLIENT=$MYSQLCLIENT
export DB_CMD=$DB_CMD
export TOMCAT_VERSION=$TOMCAT_VERSION
export GUAC_URL=$GUAC_URL
export INSTALL_LOG=$INSTALL_LOG
export JPEGTURBO=$JPEGTURBO
export LIBPNG=$LIBPNG
export INSTALL_MYSQL=$INSTALL_MYSQL
export SECURE_MYSQL=$SECURE_MYSQL
export MYSQL_HOST=$MYSQL_HOST
export MYSQL_PORT=$MYSQL_PORT
export GUAC_DB=$GUAC_DB
export GUAC_USER=$GUAC_USER
export MYSQL_ROOT_PWD="${MYSQL_ROOT_PWD}"
export GUAC_PWD="${GUAC_PWD}"
export DB_TZ="${DB_TZ}"
export INSTALL_TOTP=$INSTALL_TOTP
export INSTALL_DUO=$INSTALL_DUO
export INSTALL_LDAP=$INSTALL_LDAP
export INSTALL_QCONNECT=$INSTALL_QCONNECT
export INSTALL_HISTREC=$INSTALL_HISTREC
export HISTREC_PATH="${HISTREC_PATH}"
export GUAC_URL_REDIR=$GUAC_URL_REDIR
export INSTALL_NGINX=$INSTALL_NGINX
export PROXY_SITE=$PROXY_SITE
export RSA_KEYLENGTH=$RSA_KEYLENGTH
export DEFAULT_IP=$DEFAULT_IP
export CERT_COUNTRY=$CERT_COUNTRY
export CERT_STATE="${CERT_STATE}"
export CERT_LOCATION="${CERT_LOCATION}"
export CERT_ORG="${CERT_ORG}"
export CERT_OU="${CERT_OU}"
export CERT_DAYS=$CERT_DAYS
export LE_DNS_NAME=$LE_DNS_NAME
export LE_EMAIL=$LE_EMAIL
export BACKUP_EMAIL=$BACKUP_EMAIL
export RDP_SHARE_HOST="${RDP_SHARE_HOST}"
export RDP_SHARE_LABEL="${RDP_SHARE_LABEL}"
export RDP_PRINTER_LABEL="${RDP_PRINTER_LABEL}"
export LOCAL_DOMAIN=$LOCAL_DOMAIN
export DOMAIN_SUFFIX=$DOMAIN_SUFFIX

# Run the Guacamole install script (with all exported variables from this current shell)
sudo chmod 777 ./2-install-guacamole.sh
sudo -E ./2-install-guacamole.sh
if [[ $? -ne 0 ]]; then
    echo -e "${LRED}2-install-guacamole.sh FAILED. See ${INSTALL_LOG}${GREY}" 1>&2
    exit 1
elif [[ "${GUAC_URL_REDIR}" = true ]]; then
    echo -e "${LGREEN}Guacamole install complete\nhttp://${PROXY_SITE}:8080 - login user/pass: guacadmin/guacadmin\n${LYELLOW}***Be sure to change the password***${GREY}"
else
    echo -e "${LGREEN}Guacamole install complete\nhttp://${PROXY_SITE}:8080/guacamole - login user/pass: guacadmin/guacadmin\n${LYELLOW}***Be sure to change the password***${GREY}"
fi

# Add a Guacamole database backup (Mon-Fri 12:00am) into the current user's cron
mv $DOWNLOAD_DIR/backup-guacamole.sh $DB_BACKUP_DIR
crontab -l >cron_1
# Remove any pre-existing entry just in case
sed -i '/# backup guacamole/d' cron_1
# Create the backup job
echo "0 0 * * 1-5 ${DB_BACKUP_DIR}/backup-guacamole.sh # backup guacamole" >>cron_1
# Overwrite the old cron settings and cleanup
crontab cron_1
rm cron_1

#######################################################################################################################
# Start optional setup actions   ######################################################################################
#######################################################################################################################

# Install Nginx reverse proxy front end to Guacamole if option is selected (with all exported variables from this current shell)
if [[ "${INSTALL_NGINX}" = true ]]; then
    sudo -E ./3-install-nginx.sh
    echo -e "${LGREEN}Nginx install complete\nhttp://${PROXY_SITE} - admin login: guacadmin pass: guacadmin\n${LYELLOW}***Be sure to change the password***${GREY}"
fi

# Apply self signed TLS certificates to Nginx reverse proxy if option is selected (with all exported variables from this current shell)
if [[ "${INSTALL_NGINX}" = true ]] && [[ "${SELF_SIGN}" = true ]] && [[ "${LETS_ENCRYPT}" != true ]]; then
    sudo -E ./4a-install-tls-self-signed-nginx.sh ${PROXY_SITE} ${CERT_DAYS} ${DEFAULT_IP} | tee -a ${INSTALL_LOG} # Logged to capture client cert import instructions
    echo -e "${LGREEN}Self signed certificate configured for Nginx \n${LYELLOW}https:${LGREEN}//${PROXY_SITE}  - login user/pass: guacadmin/guacadmin\n${LYELLOW}***Be sure to change the password***${GREY}"
fi

# Apply Let's Encrypt TLS certificates to Nginx reverse proxy if option is selected (with all exported variables from this current shell)
if [[ "${INSTALL_NGINX}" = true ]] && [[ "${LETS_ENCRYPT}" = true ]] && [[ "${SELF_SIGN}" != true ]]; then
    sudo -E ./4b-install-tls-letsencrypt-nginx.sh
    echo -e "${LGREEN}Let's Encrypt TLS configured for Nginx \n${LYELLOW}https:${LGREEN}//${LE_DNS_NAME}  - login user/pass: guacadmin/guacadmin\n${LYELLOW}***Be sure to change the password***${GREY}"
fi

# Duo Settings reminder - If Duo is selected you can't login to Guacamole until this extension is fully configured
if [[ $INSTALL_DUO == "true" ]]; then
    echo
    echo -e "${LYELLOW}Reminder: Duo requires extra account specific info configured in the\n/etc/guacamole/guacamole.properties file before you can log in to Guacamole."
    echo -e "See https://guacamole.apache.org/doc/gug/duo-auth.html"
fi

# LDAP Settings reminder, LDAP auth is not functional until the config is complete
if [[ $INSTALL_LDAP == "true" ]]; then
    echo
    echo -e "${LYELLOW}Reminder: LDAP requires that your LDAP directory configuration match the exact format\nadded to the /etc/guacamole/guacamole.properties file before LDAP auth will be active."
    echo -e "See https://guacamole.apache.org/doc/gug/ldap-auth.html"
fi


# Done
printf "${LGREEN}Guacamole ${GUAC_VERSION} install complete! \n${NC}"
printf "${LGREEN} This installation is a modification of zXMiguelXz\n${NC}"
printf "${LGREEN}https://github.com/zXMiguelXz \n${NC}"


echo -e ${NC}

# Tidy up
echo
echo -e "${GREY}Removing build-essential package & cleaning up..."
mv $USER_HOME_DIR/1-setup.sh $DOWNLOAD_DIR
sudo apt remove -y build-essential &>>${INSTALL_LOG} # Lets not leave build resources installed on a secure system
sudo apt-get -y autoremove &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo -e "${LRED}Failed. Remove guac-setup, mysqlbackups and listInstall.sh" 1>&2
    exit 1
else
    echo -e "${LGREEN}OK${GREY}"
    echo
fi

