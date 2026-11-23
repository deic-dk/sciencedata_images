<?php
// A ScienceData folder: its content, read live from ScienceData; for teachers
// also upload, new folder and delete - straight in ScienceData.
require('../../config.php');
require_once($CFG->libdir . '/completionlib.php');

use mod_sciencedata\dav;

$id = required_param('id', PARAM_INT);              // course module
$sub = optional_param('p', '', PARAM_RAW);          // subfolder, relative to the activity's folder
$action = optional_param('action', '', PARAM_ALPHA);
$play = optional_param('play', '', PARAM_RAW);      // a video in this folder to play
const SD_VIDEO = '/\.(mp4|m4v|mov|mkv|webm|avi|wmv|mpe?g|flv|3gp|ts|mts|m2ts|ogv)$/i';

$cm = get_coursemodule_from_id('sciencedata', $id, 0, false, MUST_EXIST);
$folder = $DB->get_record('sciencedata', ['id' => $cm->instance], '*', MUST_EXIST);
$course = $DB->get_record('course', ['id' => $cm->course], '*', MUST_EXIST);
require_course_login($course, true, $cm);
$context = context_module::instance($cm->id);
require_capability('mod/sciencedata:view', $context);
$manage = has_capability('mod/sciencedata:manage', $context);

$sub = dav::clean($sub) ?? '';
$dav = new dav($folder->folder);
$here = new moodle_url('/mod/sciencedata/view.php', ['id' => $cm->id] + ($sub === '' ? [] : ['p' => $sub]));

// Changes - teachers only, posted with the session key; back to the listing
if ($action !== '' && $manage && confirm_sesskey()) {
    $msgs = [];
    if ($action === 'upload' && !empty($_FILES['files']['name'])) {
        foreach ((array)$_FILES['files']['name'] as $i => $name) {
            $tmp = $_FILES['files']['tmp_name'][$i] ?? '';
            $name = dav::clean_name((string)$name);
            if ($name === '' || !is_uploaded_file($tmp)) {
                continue;
            }
            $ok = $dav->put(ltrim($sub . '/' . $name, '/'), $tmp);
            $msgs[] = get_string($ok ? 'uploaded' : 'failed', 'sciencedata', s($name));
        }
    } else if ($action === 'mkdir') {
        $name = dav::clean_name(required_param('name', PARAM_RAW));
        if ($name !== '') {
            $ok = $dav->mkdir(ltrim($sub . '/' . $name, '/'));
            $msgs[] = $ok ? s($name) : get_string('failed', 'sciencedata', s($name));
        }
    } else if ($action === 'delete') {
        $name = dav::clean_name(required_param('name', PARAM_RAW));
        if ($name !== '') {
            $ok = $dav->delete(ltrim($sub . '/' . $name, '/'));
            if ($ok && preg_match(SD_VIDEO, $name)) {
                $dav->delete(ltrim($sub . '/.web/' . $name . '.mp4', '/')); // its web version, if any
            }
            $msgs[] = $ok ? get_string('deletedx', 'moodle', s($name)) : get_string('failed', 'sciencedata', s($name));
        }
    }
    redirect($here, implode('<br>', $msgs), null, \core\output\notification::NOTIFY_INFO);
}

// Viewed (logs, completion)
$event = \mod_sciencedata\event\course_module_viewed::create(['objectid' => $folder->id, 'context' => $context]);
$event->add_record_snapshot('course', $course);
$event->add_record_snapshot('sciencedata', $folder);
$event->trigger();
(new completion_info($course))->set_module_viewed($cm);

$PAGE->set_url($here);
$PAGE->set_title(format_string($folder->name));
$PAGE->set_heading($course->fullname);
$PAGE->set_activity_record($folder);
echo $OUTPUT->header();

// Where we are, within the activity's folder
$crumbs = [html_writer::link(new moodle_url('/mod/sciencedata/view.php', ['id' => $cm->id]), format_string($folder->name))];
$acc = '';
foreach ($sub === '' ? [] : explode('/', $sub) as $p) {
    $acc = ltrim($acc . '/' . $p, '/');
    $crumbs[] = html_writer::link(new moodle_url('/mod/sciencedata/view.php', ['id' => $cm->id, 'p' => $acc]), s($p));
}
echo html_writer::tag('p', implode(' / ', $crumbs), ['class' => 'mb-3']);

// A video to play: its web version (made by the pod's transcoding job), else
// the original if browsers can play it as it is
$play = dav::clean_name($play);
if ($play !== '' && preg_match(SD_VIDEO, $play)) {
    $webs = $dav->ls(ltrim($sub . '/.web', '/')) ?? [];
    $hasweb = (bool)array_filter($webs, static fn($w) => $w['name'] === $play . '.mp4');
    $orig = ltrim($sub . '/' . $play, '/');
    $src = $hasweb ? ltrim($sub . '/.web/' . $play . '.mp4', '/') : (preg_match('/\.(mp4|m4v|webm)$/i', $play) ? $orig : null);
    echo html_writer::start_div('mod-sciencedata-player mb-4');
    echo html_writer::tag('h3', s($play), ['class' => 'h5']);
    if ($src !== null) {
        echo html_writer::tag('video', '', ['controls' => 'controls', 'preload' => 'metadata', 'style' => 'max-width:100%;max-height:70vh',
            'src' => (new moodle_url('/mod/sciencedata/download.php', ['id' => $cm->id, 'f' => $src]))->out(false)]);
    }
    if (!$hasweb && $src === null) {
        echo $OUTPUT->notification(get_string('webpreparing', 'sciencedata'), 'info');
    }
    echo html_writer::tag('p', html_writer::link(new moodle_url('/mod/sciencedata/download.php', ['id' => $cm->id, 'f' => $orig]),
        get_string('downloadoriginal', 'sciencedata')), ['class' => 'mt-2']);
    echo html_writer::end_div();
}

$entries = $dav->ls($sub);
if ($entries === null) {
    echo $OUTPUT->notification(get_string('notreachable', 'sciencedata'), 'warning');
} else if (!$entries) {
    echo $OUTPUT->notification(get_string('empty', 'sciencedata'), 'info');
} else {
    $table = new html_table();
    $table->attributes['class'] = 'generaltable mod-sciencedata-list';
    $table->head = [get_string('name'), get_string('size', 'sciencedata'), get_string('modified', 'sciencedata')];
    if ($manage) {
        $table->head[] = '';
    }
    foreach ($entries as $e) {
        $rel = ltrim($sub . '/' . $e['name'], '/');
        if ($e['folder']) {
            $icon = $OUTPUT->pix_icon(file_folder_icon(), '');
            $link = html_writer::link(new moodle_url('/mod/sciencedata/view.php', ['id' => $cm->id, 'p' => $rel]), $icon . ' ' . s($e['name']));
            $size = '';
        } else {
            $icon = $OUTPUT->pix_icon(file_file_icon(['filename' => $e['name']]), '');
            $target = preg_match(SD_VIDEO, $e['name'])
                ? new moodle_url('/mod/sciencedata/view.php', ['id' => $cm->id, 'play' => $e['name']] + ($sub === '' ? [] : ['p' => $sub]))
                : new moodle_url('/mod/sciencedata/download.php', ['id' => $cm->id, 'f' => $rel]);
            $link = html_writer::link($target, $icon . ' ' . s($e['name']));
            $size = display_size($e['size']);
        }
        $row = [$link, $size, $e['mtime'] ? userdate($e['mtime'], get_string('strftimedatetimeshort', 'langconfig')) : ''];
        if ($manage) {
            $row[] = html_writer::tag('form',
                html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'sesskey', 'value' => sesskey()])
                . html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'action', 'value' => 'delete'])
                . html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'name', 'value' => $e['name']])
                . html_writer::tag('button', get_string('delete'), ['type' => 'submit', 'class' => 'btn btn-link p-0']),
                ['method' => 'post', 'action' => $here->out(false), 'class' => 'd-inline',
                 'onsubmit' => 'return confirm(' . json_encode(get_string('deleteconfirm', 'sciencedata', $e['name'])) . ')']);
        }
        $table->data[] = $row;
    }
    echo html_writer::table($table);
}

// Teachers: add files and folders - they go straight to ScienceData
if ($manage) {
    $hidden = html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'sesskey', 'value' => sesskey()]);
    echo html_writer::start_div('d-flex flex-wrap gap-4 mt-3');
    echo html_writer::tag('form',
        $hidden . html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'action', 'value' => 'upload'])
        . html_writer::tag('label', get_string('upload', 'sciencedata'), ['for' => 'sd-files', 'class' => 'me-2'])
        . html_writer::empty_tag('input', ['type' => 'file', 'name' => 'files[]', 'id' => 'sd-files', 'multiple' => 'multiple', 'class' => 'me-2'])
        . html_writer::tag('button', get_string('upload', 'sciencedata'), ['type' => 'submit', 'class' => 'btn btn-primary']),
        ['method' => 'post', 'enctype' => 'multipart/form-data', 'action' => $here->out(false)]);
    echo html_writer::tag('form',
        $hidden . html_writer::empty_tag('input', ['type' => 'hidden', 'name' => 'action', 'value' => 'mkdir'])
        . html_writer::empty_tag('input', ['type' => 'text', 'name' => 'name', 'placeholder' => get_string('newfolder', 'sciencedata'),
            'aria-label' => get_string('newfolder', 'sciencedata'), 'class' => 'form-control d-inline-block w-auto me-2'])
        . html_writer::tag('button', get_string('create', 'sciencedata'), ['type' => 'submit', 'class' => 'btn btn-secondary']),
        ['method' => 'post', 'action' => $here->out(false)]);
    echo html_writer::end_div();
    echo html_writer::tag('p', get_string('samefolder', 'sciencedata', s($folder->folder)), ['class' => 'text-muted mt-3']);
}

echo $OUTPUT->footer();
