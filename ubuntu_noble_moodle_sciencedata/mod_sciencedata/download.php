<?php
// A file of a ScienceData folder, streamed from ScienceData to someone who may
// view the activity (byte ranges passed on: videos can seek).
require('../../config.php');

use mod_sciencedata\dav;

$id = required_param('id', PARAM_INT);
$rel = dav::clean(required_param('f', PARAM_RAW));

$cm = get_coursemodule_from_id('sciencedata', $id, 0, false, MUST_EXIST);
$folder = $DB->get_record('sciencedata', ['id' => $cm->instance], '*', MUST_EXIST);
$course = $DB->get_record('course', ['id' => $cm->course], '*', MUST_EXIST);
require_course_login($course, true, $cm);
require_capability('mod/sciencedata:view', context_module::instance($cm->id));
if ($rel === null || $rel === '') {
    send_file_not_found();
}

\core\session\manager::write_close();
$name = basename($rel);
// shown in the browser: what browsers display safely; everything else downloaded
$inline = (bool)preg_match('/\.(pdf|png|jpe?g|gif|webp|mp4|webm|ogg|mp3|wav|txt)$/i', $name);
if (!(new dav($folder->folder))->send($rel, $name, $inline)) {
    send_file_not_found();
}
