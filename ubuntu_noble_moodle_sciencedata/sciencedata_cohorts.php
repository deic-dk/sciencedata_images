<?php
// Run by cron as www every 5 minutes (and once at start): each ScienceData
// group that logs in to this Moodle is kept as a cohort with its members, so a
// course enrols a group once ("Cohort sync") and students who join or leave
// the group are enrolled or unenrolled by themselves.
//
//   php sciencedata_cohorts.php <owner's ScienceData ID>
//
// Members come from the Containers app (GET api/pod-members; the pod network's
// address login makes the call the owner's). Members without a Moodle account
// get one now - the OAuth 2 kind, linked to their ScienceData ID - so they can
// be enrolled before they first log in; their e-mail address and names are
// filled in at that login. The owner (Moodle's admin) is not put in cohorts.
// Cohorts of groups no longer attached to the pod are left as they are.
//
// And once per group, a course: named after the group, enrolling its cohort as
// students (cohort sync), the owner as teacher, with a ScienceData folder
// activity on the group's course-material folder - unless a course already
// enrols the cohort. Remembered per group (config sciencedata_courses), so a
// course the owner renames, deletes or re-links is left alone.

define('CLI_SCRIPT', true);
require('/var/www/moodle/config.php');
require_once($CFG->dirroot . '/cohort/lib.php');
require_once($CFG->dirroot . '/user/lib.php');
require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->dirroot . '/course/modlib.php');
require_once($CFG->libdir . '/enrollib.php');

use auth_oauth2\linked_login;
use core\oauth2\issuer;

$owner = core_text::strtolower(trim($argv[1] ?? ''));
$issuer = issuer::get_record(['name' => 'ScienceData']);
if (!$issuer || !$issuer->get('enabled')) {
	exit(0); // no ScienceData login here
}

// The members, per group
$proto = 'https';
$env = @file_get_contents('/etc/moodle_backup.env');
if ($env !== false && preg_match("/^HOME_SERVER_PROTOCOL='?(https?)'?/m", $env, $p)) {
	$proto = $p[1];
}
$ch = curl_init($proto . '://sciencedata/index.php/apps/user_pods/api/pod-members');
curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 60,
	CURLOPT_SSL_VERIFYPEER => false, CURLOPT_SSL_VERIFYHOST => 0]); // the home server's internal address
$body = curl_exec($ch);
$status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
$groups = $status === 200 ? (json_decode((string)$body, true)['groups'] ?? null) : null;
if (!is_array($groups)) {
	fwrite(STDERR, "sciencedata_cohorts: no member list (HTTP $status)\n");
	exit(1);
}

// Cohort sync, the enrolment method that uses cohorts, on
$enrols = array_values(array_filter(explode(',', (string)get_config('core', 'enrol_plugins_enabled'))));
if (!in_array('cohort', $enrols, true)) {
	$enrols[] = 'cohort';
	set_config('enrol_plugins_enabled', implode(',', $enrols));
}

$admin = get_admin();
\core\session\manager::set_user($admin); // making courses needs the capabilities
$system = context_system::instance();
$issuerid = $issuer->get('id');

/** Once per group: a course for it (see the top), unless one already enrols its cohort. */
function course_for_group(string $gid, stdClass $cohort, stdClass $admin): void {
	global $DB, $CFG;
	$flag = 'course_' . sha1($gid);
	if (get_config('sciencedata_courses', $flag) !== false) {
		return; // made (or found) before: the owner's to manage from then on
	}
	$existing = $DB->get_field_sql("SELECT courseid FROM {enrol} WHERE enrol = 'cohort' AND customint1 = ?",
		[$cohort->id], IGNORE_MULTIPLE);
	if ($existing) {
		set_config($flag, $existing, 'sciencedata_courses');
		return;
	}
	$short = $base = core_text::substr($gid, 0, 100);
	for ($i = 2; $DB->record_exists('course', ['shortname' => $short]); $i++) {
		$short = $base . " ($i)";
	}
	$course = create_course((object)[
		'fullname' => core_text::substr($gid, 0, 254), 'shortname' => $short,
		'category' => core_course_category::get_default()->id,
		'summary' => 'For the members of the ScienceData group ' . s($gid) . '.', 'summaryformat' => FORMAT_HTML,
	]);
	$student = $DB->get_field('role', 'id', ['shortname' => 'student']);
	enrol_get_plugin('cohort')->add_instance($course, ['customint1' => $cohort->id, 'roleid' => $student, 'customint2' => 0]);
	enrol_try_internal_enrol($course->id, $admin->id, $DB->get_field('role', 'id', ['shortname' => 'editingteacher']));
	if ($modid = $DB->get_field('modules', 'id', ['name' => 'sciencedata'])) {
		add_moduleinfo((object)[
			'modulename' => 'sciencedata', 'module' => $modid, 'course' => $course->id, 'section' => 0, 'visible' => 1,
			'name' => 'Course material', 'intro' => '', 'introformat' => FORMAT_HTML,
			'folder' => trim(str_replace(['/', '\\'], '-', $gid), ' .'), // as sciencedata_course_folders.php names it
		], $course);
	}
	require_once($CFG->dirroot . '/enrol/cohort/locallib.php');
	enrol_cohort_sync(new null_progress_trace(), $course->id);
	set_config($flag, $course->id, 'sciencedata_courses');
	echo "course for group $gid: made ($short)\n";
}

/** The Moodle account of a ScienceData ID: linked, or made now. 0 = leave out. */
function account_of(string $uid, string $name, int $issuerid): int {
	global $DB, $CFG;
	$link = linked_login::get_record(['issuerid' => $issuerid, 'username' => $uid]);
	if ($link) {
		return (int)$link->get('userid');
	}
	$user = $DB->get_record('user', ['username' => $uid, 'mnethostid' => $CFG->mnet_localhost_id, 'deleted' => 0]);
	if ($user && $user->auth !== 'oauth2') {
		return 0; // a local account with that name: not ours to link
	}
	if (!$user) {
		// first and last name from the display name (the login fills in the
		// provider's own split, and the e-mail address)
		$parts = preg_split('/\s+/', trim($name)) ?: [];
		$last = count($parts) > 1 ? array_pop($parts) : '';
		$id = user_create_user((object)[
			'auth' => 'oauth2', 'username' => $uid, 'confirmed' => 1,
			'mnethostid' => $CFG->mnet_localhost_id,
			'firstname' => $parts ? implode(' ', $parts) : $uid, 'lastname' => $last, 'email' => '',
		], false, false);
	} else {
		$id = (int)$user->id;
	}
	(new linked_login(0, (object)['issuerid' => $issuerid, 'username' => $uid, 'userid' => $id,
		'email' => '', 'confirmtoken' => '', 'confirmtokenexpires' => 0]))->create();
	return $id;
}

foreach ($groups as $gid => $members) {
	$gid = (string)$gid;
	$idnumber = 'sciencedata:' . substr(sha1($gid), 0, 24);
	$cohort = $DB->get_record('cohort', ['idnumber' => $idnumber]);
	if (!$cohort) {
		$cohort = (object)['contextid' => $system->id, 'name' => core_text::substr($gid, 0, 254), 'idnumber' => $idnumber,
			'description' => 'Members of the ScienceData group ' . s($gid) . ' - kept up to date automatically.',
			'descriptionformat' => FORMAT_HTML, 'visible' => 1, 'component' => ''];
		$cohort->id = cohort_add_cohort($cohort);
	}
	$want = [];
	foreach ((array)$members as $m) {
		$uid = core_text::strtolower(trim((string)($m['uid'] ?? '')));
		if ($uid === '' || $uid === $owner || clean_param($uid, PARAM_USERNAME) !== $uid) {
			continue;
		}
		if ($id = account_of($uid, (string)($m['name'] ?? ''), $issuerid)) {
			$want[$id] = true;
		}
	}
	unset($want[$admin->id]);
	$have = array_flip($DB->get_fieldset_select('cohort_members', 'userid', 'cohortid = ?', [$cohort->id]));
	foreach (array_diff_key($want, $have) as $id => $_) {
		cohort_add_member($cohort->id, $id);
	}
	foreach (array_diff_key($have, $want) as $id => $_) {
		cohort_remove_member($cohort->id, $id);
	}
	echo "cohort " . $gid . ": " . count($want) . " members\n";
	course_for_group($gid, $cohort, $admin);
}
