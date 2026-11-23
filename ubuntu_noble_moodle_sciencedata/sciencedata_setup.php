<?php
// Run by start.sh as www at each start: Moodle's links to ScienceData.
//
//   php sciencedata_setup.php '<ScienceData hosts, space-separated>' [<owner's files over WebDAV>]
//
// - Course material: the folder 'Course material' in the owner's ScienceData
//   files - an ordinary folder: web interface, sync client, shared with the
//   course's group for the students - offered in Moodle's file picker by
//   repository_sciencedata (read over WebDAV from inside the pod: the pod
//   network's address login makes the owner's files readable).
// - The ScienceData links filter (filter_sciencedata) on, for these hosts:
//   share links in course text become notebook previews with a Run button,
//   video players and folder cards.

define('CLI_SCRIPT', true);
require('/var/www/moodle/config.php');
require_once($CFG->dirroot . '/repository/lib.php');
require_once($CFG->libdir . '/filterlib.php');

\core\session\manager::set_user(get_admin()); // repository changes need site:config

// Course material, from the owner's ScienceData files
$davurl = trim($argv[2] ?? '') ?: 'https://sciencedata/files';
$options = ['pluginname' => '', 'folder' => 'Course material', 'davurl' => $davurl];
if (!$DB->record_exists('repository', ['type' => 'sciencedata'])) {
	(new repository_type('sciencedata', $options, true))->create(true); // makes its one site-wide instance
	echo "course material: the ScienceData folder 'Course material' in the file picker\n";
} else {
	$type = repository::get_type_by_typename('sciencedata');
	$type->update_options($options);
	$type->update_visibility(true);
}
// earlier image versions offered a folder inside Moodle's data root (File system repository)
if ($fsid = $DB->get_field('repository', 'id', ['type' => 'filesystem'])) {
	foreach ($DB->get_records('repository_instances', ['typeid' => $fsid, 'name' => 'Course material (ScienceData)']) as $old) {
		repository::get_repository_by_id($old->id, context_system::instance())->delete();
		echo "course material: removed the earlier data-root folder from the file picker\n";
	}
}

// Course material has one home: ScienceData folders ('ScienceData folder'
// activity). Moodle's own File and Folder activities - copies that would drift
// apart from ScienceData - are hidden from the activity chooser; existing ones
// keep working, and an administrator can show them again.
foreach (['resource', 'folder'] as $mod) {
	if ($DB->get_field('modules', 'visible', ['name' => $mod])) {
		$DB->set_field('modules', 'visible', 0, ['name' => $mod]);
		\core_plugin_manager::reset_caches();
		echo "course material: Moodle's own '$mod' activity hidden (ScienceData folders instead)\n";
	}
}

// The filter
$hosts = trim($argv[1] ?? '');
if ($hosts !== '') {
	set_config('hosts', $hosts, 'filter_sciencedata');
}
if (get_config('filter_sciencedata', 'nbviewer') === false) {
	set_config('nbviewer', 'https://kube.sciencedata.dk:8443', 'filter_sciencedata');
}
if (get_config('filter_sciencedata', 'runurl') === false) {
	set_config('runurl', '', 'filter_sciencedata');
}
filter_set_global_state('sciencedata', TEXTFILTER_ON);
echo 'ScienceData links: ' . get_config('filter_sciencedata', 'hosts') . "\n";
