<?php
// The ScienceData folders of a course.
require('../../config.php');

$id = required_param('id', PARAM_INT);
$course = $DB->get_record('course', ['id' => $id], '*', MUST_EXIST);
require_course_login($course, true);
$PAGE->set_url('/mod/sciencedata/index.php', ['id' => $id]);
$PAGE->set_title(get_string('modulenameplural', 'sciencedata'));
$PAGE->set_heading($course->fullname);
echo $OUTPUT->header();
echo $OUTPUT->heading(get_string('modulenameplural', 'sciencedata'));
$items = [];
foreach (get_all_instances_in_course('sciencedata', $course) as $f) {
    $items[] = html_writer::link(new moodle_url('/mod/sciencedata/view.php', ['id' => $f->coursemodule]), format_string($f->name));
}
echo $items ? html_writer::alist($items) : $OUTPUT->notification(get_string('thereareno', 'moodle', get_string('modulenameplural', 'sciencedata')), 'info');
echo $OUTPUT->footer();
