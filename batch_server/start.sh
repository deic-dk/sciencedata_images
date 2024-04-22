#!/bin/bash

# We'll allow this local user to submit and pick up jobs
LOCAL_USER_DN="/CN=$SD_UID/O=kube.sciencedata.dk"
LOCAL_USER_PASSWORD="secret"
# We will also allow using the ScienceData cert/key to submit and pick up jobs
USER_SUBJECT="O=sciencedata.dk,CN=$SD_UID"
SPOOL_DIR="/var/spool/gridfactory"
DATA_DIR="/var/www/grid/data"
VO_FILE="$DATA_DIR/vos/default.txt"
SSL_HOST_CERT="/var/www/grid/hostcert.pem"
SSL_HOST_KEY="/var/www/grid/hostkey.pem"
SSL_HOST_KEY_UNENC="/var/www/grid/hostkey_unenc.pem"
SYSTEM_CA_CERTS="/etc/ssl/certs"
MY_CA_CERTS="/var/www/grid/certificates"
APACHE_GRID_CONF="/etc/apache2/sites-available/grid.conf"
APACHE_GRID_CONF_TEMPLATE="/usr/share/gridfactory/grid.conf"
MY_MK_VO="/usr/sbin/mk_vo.sh"
MY_HOSTNAME=`hostname`
GRIDFACTORY_INDEX="/var/spool/gridfactory/index.html"
GRIDFACTORY_CONF="/etc/gridfactory.conf"
KEY_PASSWORD="secret"
MY_DB_USERNAME="root"
MY_DB_PASSWORD=""
DAV_LOCK_DIR="/var/lock/dav"
DB_DIR="/var/spool/db"
LOG_DIR="/var/log/gridfactory"
## This is the user of the GridFactory debs. May not exist.
DEFAULT_GRID_USER="www-data"
## This should be your existing Apache user.
GRID_USER="www-data"
# Validity of test cert
TEST_CERT_DAYS=30
CA_CERT_DAYS=3650
MY_CERT_PATH=~/.gridfactory

###

runSSH(){
# SSH access to account with sudo rights - or just set password for root
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
	  echo "$SSH_PUBLIC_KEY" >> /root/.ssh/authorized_keys
fi
if [[ -n "$ROOT_PASSWORD" ]]; then
	  echo "root:$ROOT_PASSWORD" | chpasswd;
fi

# Resolve sciencedata to the 10.2.0.0/24 address of the silo of the user
[[ -n $HOME_SERVER ]] && echo "$HOME_SERVER	sciencedata" >> /etc/hosts
[[ -n $HOME_SERVER ]] && echo "*/5 * * * * root grep sciencedata /etc/hosts || echo \"$HOME_SERVER	sciencedata\" >> /etc/hosts" > /etc/cron.d/sciencedata_hosts
[[ -n $PUBLIC_HOME_SERVER ]] && echo "$PUBLIC_HOME_SERVER" >> /tmp/public_home_server
[[ -n $SETUP_SCRIPT  && -f "$SETUP_SCRIPT" ]] && . "$SETUP_SCRIPT"

service cron start

/usr/sbin/dropbear -p 22 -W 65536 -F -E
}

setDirsOwnership(){
  mkdir -p "$DAV_LOCK_DIR"
  chown -R "$GRID_USER" "$SPOOL_DIR" "$DATA_DIR" "$LOG_DIR" "$DAV_LOCK_DIR"
  if [ ! -e "$DB_DIR" ]; then
    ln -s "$SPOOL_DIR" "$DB_DIR"
  fi
  chown $GRID_USER $GRIDFACTORY_CONF
  chmod o-r $GRIDFACTORY_CONF
}

changeDaemonUser(){
if [ "$DEFAULT_GRID_USER" != "$GRID_USER" ]; then
  for name in spoolmanager queuemanager pullmanager; do
    sed  -i "s/GRIDFACTORY_USER=\"$DEFAULT_GRID_USER\"/GRIDFACTORY_USER=\"$GRID_USER\"/" /etc/init.d/$name
  done
fi
}

configureApache(){
  ## Check some permissions
  if [ ! -f $MY_MK_VO ]; then
    echo "WARNING: $MY_MK_VO was not found. This probably means that you did not install mod_gacl \
and mod_gridfactory. Please do this - without these modules GridFactory cannot run.";
  fi
  ## Configure the Apache config file
  cp "$APACHE_GRID_CONF_TEMPLATE" "$APACHE_GRID_CONF"
  sed -i "s|logs/|/var/log/apache2/|g" "$APACHE_GRID_CONF"
  sed -i "s/MY_HOSTNAME/$MY_HOSTNAME/g" "$APACHE_GRID_CONF"
  sed -i "s/MY_DB_USERNAME/$MY_DB_USERNAME/g" "$APACHE_GRID_CONF"
  sed -i "s|MY_DB_PASSWORD|$MY_DB_PASSWORD|g" "$APACHE_GRID_CONF"
  sed -i "s|MY_MK_VO|$MY_MK_VO|g" "$APACHE_GRID_CONF"
  apache_conf_dir=`dirname "$APACHE_GRID_CONF"`
  apache_conf_file=`basename "$APACHE_GRID_CONF"`
  cd "$apache_conf_dir/../sites-enabled"
  ln -s ../sites-available/$apache_conf_file
  # This config file is from mod_gridfactory.conf, it has a subset of the directives of grid.conf
  rm "gridfactory.conf"
  cd ..
  sed -i -E 's|^(Include ports.conf)|#\1|' apache2.conf
  sed -i "s|MY_HOSTNAME|$MY_HOSTNAME|" "$GRIDFACTORY_INDEX"
  cd
}

configureCerts(){

# See https://stackoverflow.com/questions/11153058/java7-refusing-to-trust-certificate-in-trust-store
grep GridFactory /etc/ssl/openssl.cnf || sed -i -E "s|# GridFactory\n(\[ crl_ext \])|keyUsage = cRLSign, keyCertSign, nonRepudiation, digitalSignature, keyEncipherment\n\n\1|" /etc/ssl/openssl.cnf

## Create self-signed certificate - already done, but it has no CA attribute, so we make one which has.
#make-ssl-cert generate-default-snakeoil --force-overwrite
## Create host certificate with CA attribute
openssl req -x509 -nodes -extensions v3_ca -subj "/CN=`hostname`" -days $CA_CERT_DAYS -newkey rsa:2048 -config /etc/ssl/openssl.cnf -extensions v3_ca -batch -keyout $SSL_HOST_KEY_UNENC -out $SSL_HOST_CERT

#-addext basicConstraints=critical,CA:TRUE,pathlen:1

# Copy it to the CA dirs
my_ca_cert=`openssl x509 -in $SSL_HOST_CERT -hash | head -1`.0
rm -f $SYSTEM_CA_CERTS/$my_ca_cert
rm -f $MY_CA_CERTS/$my_ca_cert
cp $SSL_HOST_CERT $SYSTEM_CA_CERTS/$my_ca_cert
cp $SSL_HOST_CERT $MY_CA_CERTS/$my_ca_cert

## Create encrypted key from unencrypted key
echo "Writing encrypted key $SSL_HOST_KEY"
openssl rsa -des3 -in "$SSL_HOST_KEY_UNENC" -passin "pass:" -passout "pass:$KEY_PASSWORD" > "$SSL_HOST_KEY"

# Get sciencedata.dk ca certificate
#echo | openssl s_client -connect sciencedata.dk:443 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "sciencedata.pem"
curl https://sciencedata.dk/my_ca_cert.pem -o sciencedata.pem
sciencedata_ca_cert=`openssl x509 -in sciencedata.pem -hash | head -1`.0
cp -f "sciencedata.pem" $SYSTEM_CA_CERTS/$sciencedata_ca_cert
cp -f "sciencedata.pem" $MY_CA_CERTS/$sciencedata_ca_cert

cd
# Create test certificate request
mkdir -p $MY_CERT_PATH
openssl req -new -out $MY_CERT_PATH/userreq.pem -newkey rsa:4096 -keyout $MY_CERT_PATH/userkey.pem -subj "$LOCAL_USER_DN" -passout pass:$LOCAL_USER_PASSWORD
# Sign it with the hostcert generated above
RANDFILE=/tmp/.random openssl x509 -req -in $MY_CERT_PATH/userreq.pem -CA "$SSL_HOST_CERT" -CAkey "$SSL_HOST_KEY_UNENC" -CAcreateserial -out $MY_CERT_PATH/usercert.pem -days $TEST_CERT_DAYS -sha256

## Set permissions
chmod go+r $SYSTEM_CA_CERTS/*
chmod go+r $MY_CA_CERTS/*
chown "$GRID_USER":"$GRID_USER" "$SSL_HOST_KEY_UNENC" "$SSL_HOST_KEY"
chmod 640 "$SSL_HOST_KEY_UNENC" "$SSL_HOST_KEY"
chmod 644 "$SSL_HOST_CERT"
## Allow the unencrypted key to be read by mysql.
## We're assuming the Apache user's primary group is a group of the same name as that of the user
## and that the MySQL user is "mysql".
usermod -a -G $GRID_USER mysql
## Check if things went well
if [ ! -f $SSL_HOST_KEY -o  ! -f $SSL_HOST_KEY_UNENC ]; then
  echo "WARNING: there was a problem setting up your SSL keys.\
Please make sure you have an encrypted host key in $SSL_HOST_KEY and a \
corresponding host certificate in $SSL_HOST_CERT and run this script again" 1>&2
fi
}

configureGridFactory(){
  sed -i "s/MY_HOSTNAME/$MY_HOSTNAME/g" "$GRIDFACTORY_CONF"
  sed -i "s/MY_DB_USERNAME/$MY_DB_USERNAME/g" "$GRIDFACTORY_CONF"
  sed -i "s/MY_DB_PASSWORD/$MY_DB_PASSWORD/g" "$GRIDFACTORY_CONF"
  sed -i "s/MY_KEY_PASSWORD/$KEY_PASSWORD/g" "$GRIDFACTORY_CONF"
}

configureGACL(){
## Skip if .gacl file already there
if [ -e "$SPOOL_DIR/.gacl" ]; then
  return
fi
HOST_SUBJECT=`openssl x509 -in "$SSL_HOST_CERT" -subject -noout | sed -E 's|^subject= *||'`
echo "Setting GACL permissions on $DATA_DIR: and $SPOOL_DIR: \
allowing all to read and $HOST_SUBJECT to write/submit/pickup jobs. To allow others, please edit \
$VO_FILE and/or $SPOOL_DIR/.gacl. Notice that url can be an http or https URL. \
Use https://$MY_HOSTNAME/vos/default.txt from other hosts."
echo "<gacl>
  <entry>
    <any-user/>
    <allow><read/><list/></allow>
  </entry>
  <entry>
    <dn-list>
      <url>file://$VO_FILE</url>
    </dn-list>
    <allow><read/><list/><write/><admin/></allow>
  </entry>
</gacl>" > "$SPOOL_DIR/.gacl"

cp -a "$SPOOL_DIR/.gacl" "$DATA_DIR/.gacl"
}

configureVO(){
cd
# NOTICE: GACL parsing only works for subjects with no spaces before/after commas and equal signs
HOST_SUBJECT=`openssl x509 -in "$SSL_HOST_CERT" -subject -noout | sed -E 's|^subject= *||' | sed 's| = |=|g' | sed 's|, |,|g'`
LOCAL_USER_SUBJECT=`openssl x509 -in $MY_CERT_PATH/usercert.pem -subject -noout | sed -E 's|^subject= *||' | sed 's| = |=|g' | sed 's|, |,|g'`
if ! grep "$LOCAL_USER_SUBJECT" "$VO_FILE" >& /dev/null; then
  echo $LOCAL_USER_SUBJECT >> "$VO_FILE"
fi
if ! grep "$USER_SUBJECT" "$VO_FILE" >& /dev/null; then
  echo $USER_SUBJECT >> "$VO_FILE"
fi
if ! grep "$HOST_SUBJECT" "$VO_FILE" >& /dev/null; then
  echo $HOST_SUBJECT >> "$VO_FILE"
fi
}

startServices(){
  service mysql start
  service apache2 start
  service spoolmanager start
  service queuemanager start
}

setDirsOwnership
changeDaemonUser
configureCerts
configureApache
configureGridFactory
configureGACL
configureVO
startServices
runSSH