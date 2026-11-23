<?php
defined('MOODLE_INTERNAL') || die();

class backup_sciencedata_activity_structure_step extends backup_activity_structure_step {
    protected function define_structure() {
        // no user data: the files are on ScienceData
        $sciencedata = new backup_nested_element('sciencedata', ['id'],
            ['name', 'intro', 'introformat', 'folder', 'timemodified']);
        $sciencedata->set_source_table('sciencedata', ['id' => backup::VAR_ACTIVITYID]);
        $sciencedata->annotate_files('mod_sciencedata', 'intro', null);
        return $this->prepare_activity_structure($sciencedata);
    }
}
