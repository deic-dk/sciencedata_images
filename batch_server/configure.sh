#!/bin/bash

#  Copyright 2024 (C) Frederik Orellana, Technical University of Denmark.
#  All Rights Reserved.
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program. If not, see http://www.gnu.org/licenses/.

### BEGIN Configuration

MY_CNF="/etc/mysql/mysql.conf.d/mysqld.cnf"
TMP_MY_CNF="/tmp/my."`date +%s`".cnf"

### END Configuration

configureMy_cnf()
{
## Skip if my.cnf already configured
if grep 'START configuration for GridFactory' $MY_CNF > /dev/null; then
  return
fi
## Skip if my.cnf not writable
if [ ! -w $MY_CNF ]; then
  echo "$MY_CNF not writable" 1>&2
  return
fi

# Fix wrongly configure homedir (on Ubuntu Jammy)
service mysql stop
usermod -d /var/lib/mysql/ mysql
service mysql start

echo "Configuring $MY_CNF"
while read f; do
echo $f
if [ "$f" == "[mysqld]" ]; then
  cat << EOF
## START configuration for GridFactory
ansi
#max_allowed_packet=32M
#skip-innodb
innodb_data_home_dir = /var/lib/mysql
innodb_data_file_path = ibdata1:10M:autoextend
innodb_log_group_home_dir = /var/lib/mysql
# Deprecated as of 5.0.24
#innodb_log_arch_dir = /var/lib/mysql
# Doesn't work in 5.5.14-2.fc15
#set-variable = max_connections=300
## END configuration for GridFactory
EOF
fi
done < $MY_CNF > $TMP_MY_CNF
echo "Backing up $MY_CNF to $MY_CNF.orig"
mv -f $MY_CNF $MY_CNF.orig
mv -f $TMP_MY_CNF $MY_CNF
}

checkDB(){
  echo show tables | mysql GridFactory
}

configureDB()
{
## Skip if database already configured
if checkDB; then
  echo "MySQL database already configured"
  return
fi
echo "Configuring MySQL database"
echo "CREATE DATABASE GridFactory;
CREATE TABLE GridFactory.jobDefinition (
  identifier varchar(255) NOT NULL,
  name varchar(255) default NULL,
  csStatus varchar(255) default NULL,
  userInfo varchar(255) default NULL,
  inputFileURLs text default NULL,
  outFileMapping text,
  providerInfo varchar(255) default NULL,
  stdoutDest varchar(255) default NULL,
  stderrDest varchar(255) default NULL,
  created datetime default NULL,
  lastModified datetime default NULL,
  outTmp varchar(255) default NULL,
  errTmp varchar(255) default NULL,
  jobID varchar(255) default NULL,
  metaData text,
  host varchar(255) default NULL,
  nodeId varchar(255) default NULL,
  runningSeconds int(16) default NULL,
  ramMb int(16) default NULL,
  executable varchar(255) default NULL,
  executables text default NULL,
  opSys varchar(255) default NULL,
  runtimeEnvironments text default NULL,
  allowedVOs varchar(255) default NULL,
  vos varchar(255) default NULL,
  virtualize tinyint (4) default NULL,
  PRIMARY KEY (identifier)
);" | mysql
echo "CREATE TABLE GridFactory.jobHistory (
  identifier varchar(255) NOT NULL,
  name varchar(255) default NULL,
  csStatus varchar(255) default NULL,
  userInfo varchar(255) default NULL,
  inputFileURLs text default NULL,
  outFileMapping text,
  providerInfo varchar(255) default NULL,
  stdoutDest varchar(255) default NULL,
  stderrDest varchar(255) default NULL,
  created datetime default NULL,
  lastModified datetime default NULL,
  outTmp varchar(255) default NULL,
  errTmp varchar(255) default NULL,
  jobID varchar(255) default NULL,
  metaData text,
  host varchar(255) default NULL,
  nodeId varchar(255) default NULL,
  runningSeconds int(16) default NULL,
  ramMb int(16) default NULL,
  executable varchar(255) default NULL,
  executables text default NULL,
  opSys varchar(255) default NULL,
  runtimeEnvironments text default NULL,
  allowedVOs varchar(255) default NULL,
  vos varchar(255) default NULL,
  virtualize tinyint (4) default NULL,
  csStatusHistory text,
  PRIMARY KEY (identifier)
);" | mysql
echo "CREATE TABLE GridFactory.nodeInformation (
  identifier varchar(255) NOT NULL,
  host varchar(255) default NULL,
  opSys varchar(255) default NULL,
  subnodesDbUrl varchar(255) default NULL,
  maxJobs int(16) default NULL,
  allowedVOs text,
  virtualize tinyint(4) default NULL,
  hypervisors text,
  maxRamMbPerJob int(16) default NULL,
  maxRunningSecondsPerJob int(16) default NULL,
  providerInfo varchar(255) default NULL,
  created datetime default NULL,
  lastModified datetime default NULL,
  PRIMARY KEY (identifier)
);" | mysql
echo "use mysql; ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';" | mysql
chmod go+rw /run/mysqld
}

setupServices(){
  service mysql restart
  rm /etc/apache2/sites-enabled/000-default.conf
  service apache2 restart
  echo "Starting spoolmanager and queuemanager. If you want to run pullmanager, you have to configure it manually."
  service spoolmanager restart
  service queuemanager restart
  update-rc.d spoolmanager defaults
  update-rc.d queuemanager defaults
}

configureMy_cnf
configureDB
setupServices

