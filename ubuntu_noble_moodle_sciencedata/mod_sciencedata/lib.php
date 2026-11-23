<?php
// ScienceData folder: a course activity showing a folder in 'Course material'
// in the site owner's ScienceData files - live, read on each view; teachers'
// uploads, new folders and deletions go straight to ScienceData. One folder,
// two ways in (Moodle, and ScienceData's web interface or sync client); no
// copies, so nothing to keep in sync.
defined('MOODLE_INTERNAL') || die();

function sciencedata_supports($feature) {
    return match ($feature) {
        FEATURE_MOD_ARCHETYPE => MOD_ARCHETYPE_RESOURCE,
        FEATURE_GROUPS => false,
        FEATURE_GROUPINGS => false,
        FEATURE_MOD_INTRO => true,
        FEATURE_COMPLETION_TRACKS_VIEWS => true,
        FEATURE_GRADE_HAS_GRADE => false,
        FEATURE_GRADE_OUTCOMES => false,
        FEATURE_BACKUP_MOODLE2 => true, // the settings (which folder); the files stay on ScienceData
        FEATURE_SHOW_DESCRIPTION => true,
        FEATURE_MOD_PURPOSE => MOD_PURPOSE_CONTENT,
        default => null,
    };
}

function sciencedata_add_instance($data, $mform) {
    global $DB;
    $data->folder = \mod_sciencedata\dav::clean((string)$data->folder) ?? '';
    $data->timemodified = time();
    return $DB->insert_record('sciencedata', $data);
}

function sciencedata_update_instance($data, $mform) {
    global $DB;
    $data->id = $data->instance;
    $data->folder = \mod_sciencedata\dav::clean((string)$data->folder) ?? '';
    $data->timemodified = time();
    return $DB->update_record('sciencedata', $data);
}

/** Removes the activity only - the folder and its files stay on ScienceData. */
function sciencedata_delete_instance($id) {
    global $DB;
    if (!$DB->record_exists('sciencedata', ['id' => $id])) {
        return false;
    }
    $DB->delete_records('sciencedata', ['id' => $id]);
    return true;
}

function sciencedata_get_view_actions() {
    return ['view'];
}

function sciencedata_get_post_actions() {
    return ['update', 'add'];
}
