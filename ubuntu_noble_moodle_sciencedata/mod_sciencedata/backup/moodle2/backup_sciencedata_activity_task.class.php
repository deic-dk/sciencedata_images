<?php
// Backup of a ScienceData folder activity: its settings - which folder it
// shows - not the files, which stay on ScienceData (a restored or copied
// course shows the same folder; choose another in the activity's settings).
defined('MOODLE_INTERNAL') || die();

require_once($CFG->dirroot . '/mod/sciencedata/backup/moodle2/backup_sciencedata_stepslib.php');

class backup_sciencedata_activity_task extends backup_activity_task {
    protected function define_my_settings() {
    }

    protected function define_my_steps() {
        $this->add_step(new backup_sciencedata_activity_structure_step('sciencedata_structure', 'sciencedata.xml'));
    }

    public static function encode_content_links($content) {
        global $CFG;
        $base = preg_quote($CFG->wwwroot . '/mod/sciencedata', '#');
        $content = preg_replace('#(' . $base . '/index\.php\?id=)([0-9]+)#', '$@SCIENCEDATAINDEX*$2@$', $content);
        return preg_replace('#(' . $base . '/view\.php\?id=)([0-9]+)#', '$@SCIENCEDATAVIEWBYID*$2@$', $content);
    }
}
