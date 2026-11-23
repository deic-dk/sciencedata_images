<?php
// Run by start.sh as www: Moodle's "Log in with ScienceData" (OAuth 2 /
// OpenID Connect), configured from the Containers app's answer for this pod
// (GET api/pod-login, JSON on stdin) - every start, since a new pod gets a new
// login client.
//
//   php sciencedata_oidc.php <owner's ScienceData ID>   < answer
//   php sciencedata_oidc.php --off                       (no login client: disable)
//
// The owner logs in as Moodle's administrator (account 'admin', linked to
// their ID). Started for a group, the group's members get accounts at their
// first login (the provider admits only them); started just for the owner, no
// accounts are created (authpreventaccountcreation), so only the owner's linked
// login works. Logins are never linked to accounts by e-mail (oauth2_patch.sh).
// Moodle's own login form stays for local accounts the owner creates.

define('CLI_SCRIPT', true);
require('/var/www/moodle/config.php');

use core\oauth2\endpoint;
use core\oauth2\issuer;
use core\oauth2\user_field_mapping;
use auth_oauth2\linked_login;

const NAME = 'ScienceData';

$issuer = issuer::get_record(['name' => NAME]) ?: null;

if (($argv[1] ?? '') === '--off') {
	if ($issuer && $issuer->get('enabled')) {
		$issuer->set('enabled', 0);
		$issuer->update();
		echo "ScienceData login: off\n";
	}
	exit(0);
}

$owner = core_text::strtolower(trim($argv[1] ?? ''));
$in = json_decode(stream_get_contents(STDIN), true);
foreach (['issuer', 'authorization_url', 'token_url', 'userinfo_url', 'client_id', 'client_secret'] as $k) {
	if (empty($in[$k])) {
		fwrite(STDERR, "sciencedata_oidc: '$k' missing in the answer\n");
		exit(1);
	}
}
$group = (string)($in['group'] ?? '');

// The issuer
$data = [
	'name' => NAME,
	'loginpagename' => NAME,
	'image' => '',
	'clientid' => $in['client_id'],
	'clientsecret' => $in['client_secret'],
	'baseurl' => $in['issuer'],
	'enabled' => 1,
	'showonloginpage' => issuer::LOGINONLY,
	'basicauth' => 0,
	'loginscopes' => 'openid profile email',
	'loginscopesoffline' => 'openid profile email',
	'requireconfirmation' => 0,
	'alloweddomains' => '',
];
if ($issuer) {
	foreach ($data as $k => $v) {
		$issuer->set($k, $v);
	}
	$issuer->update();
} else {
	$issuer = new issuer(0, (object)$data);
	$issuer->create();
}
$id = $issuer->get('id');

// Its addresses
foreach (['authorization_endpoint' => 'authorization_url', 'token_endpoint' => 'token_url',
		'userinfo_endpoint' => 'userinfo_url'] as $name => $k) {
	$e = endpoint::get_record(['issuerid' => $id, 'name' => $name]);
	if ($e) {
		$e->set('url', $in[$k]);
		$e->update();
	} else {
		(new endpoint(0, (object)['issuerid' => $id, 'name' => $name, 'url' => $in[$k]]))->create();
	}
}

// The provider's fields: preferred_username is the ScienceData ID (the key of
// a login), not the e-mail - outside DTU the two differ
foreach (['username' => 'preferred_username', 'email' => 'email', 'firstname' => 'given_name',
		'lastname' => 'family_name'] as $internal => $external) {
	$m = user_field_mapping::get_record(['issuerid' => $id, 'internalfield' => $internal]);
	if ($m) {
		$m->set('externalfield', $external);
		$m->update();
	} else {
		(new user_field_mapping(0, (object)['issuerid' => $id, 'internalfield' => $internal,
			'externalfield' => $external]))->create();
	}
}

// The authentication method on, and who gets accounts
$auths = array_values(array_filter(explode(',', (string)get_config('core', 'auth'))));
if (!in_array('oauth2', $auths, true)) {
	$auths[] = 'oauth2';
	set_config('auth', implode(',', $auths));
}
set_config('authpreventaccountcreation', $group === '' ? 1 : 0);

// The owner = the administrator account: linked to the owner's ID only
$admin = get_admin();
if ($owner !== '') {
	foreach (linked_login::get_records(['userid' => $admin->id]) as $l) {
		if ($l->get('issuerid') != $id || $l->get('username') !== $owner) {
			$l->delete();
		}
	}
	$mine = linked_login::get_record(['issuerid' => $id, 'username' => $owner]);
	if ($mine && $mine->get('userid') != $admin->id) {
		// an account made at an earlier login of the owner: the login is the admin's now
		$mine->set('userid', $admin->id);
		$mine->set('confirmtoken', '');
		$mine->update();
	} else if (!$mine) {
		(new linked_login(0, (object)['issuerid' => $id, 'username' => $owner, 'userid' => $admin->id,
			'email' => $admin->email, 'confirmtoken' => '', 'confirmtokenexpires' => 0]))->create();
	}
}

$groups = is_array($in['groups'] ?? null) ? $in['groups'] : ($group === '' ? [] : [$group]);
echo 'ScienceData login: ' . ($groups === [] ? "the owner ($owner) only"
	: 'members of ' . implode(', ', $groups) . ", the owner ($owner) as admin") . "\n";
