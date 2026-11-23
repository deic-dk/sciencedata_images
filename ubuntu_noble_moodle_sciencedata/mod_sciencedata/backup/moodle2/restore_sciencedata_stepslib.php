<?php
defined('MOODLE_INTERNAL') || die();

class restore_sciencedata_activity_structure_step extends restore_activity_structure_step {
    protected function define_structure() {
        return $this->prepare_activity_structure([new restore_path_element('sciencedata', '/activity/sciencedata')]);
    }

    protected function process_sciencedata($data) {
        global $DB;
        $data = (object)$data;
        $data->course = $this->get_courseid();
        $newitemid = $DB->insert_record('sciencedata', $data);
        $this->apply_activity_instance($newitemid);
    }

    protected function after_execute() {
        $this->add_related_files('mod_sciencedata', 'intro', null);
    }
}
