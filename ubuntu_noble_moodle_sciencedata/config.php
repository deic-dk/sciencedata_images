<?php  // Moodle configuration file - written for the ScienceData pod; start.sh fills in WWWROOT

unset($CFG);
global $CFG;
$CFG = new stdClass();

// PostgreSQL in the same pod, over its socket with peer authentication (role www)
$CFG->dbtype    = 'pgsql';
$CFG->dblibrary = 'native';
$CFG->dbhost    = 'localhost';
$CFG->dbname    = 'moodle';
$CFG->dbuser    = 'www';
$CFG->dbpass    = '';
$CFG->prefix    = 'mdl_';
$CFG->dboptions = ['dbpersist' => 0, 'dbsocket' => '/var/run/postgresql'];

// The public address: kube's reverse proxy terminates HTTPS and forwards plain HTTP
$CFG->wwwroot   = 'WWWROOT';
$CFG->sslproxy  = true;

// Persistent files on the ScienceData folder mounted at /var/moodledata;
// caches and temporary files local to the pod
$CFG->dataroot      = '/var/moodledata';
$CFG->localcachedir = '/var/cache/moodle/local';
$CFG->tempdir       = '/var/cache/moodle/temp';
$CFG->cachedir      = '/var/cache/moodle/cache';
$CFG->directorypermissions = 02777;
$CFG->admin = 'admin';

// The web server sends unmatched paths to r.php (see the Caddyfile)
$CFG->routerconfigured = true;

require_once(__DIR__ . '/lib/setup.php');

// There is no php closing tag in this file,
// it is intentional because it prevents trailing whitespace problems!
