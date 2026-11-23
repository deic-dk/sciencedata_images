<?php
defined('MOODLE_INTERNAL') || die();

require_once($CFG->dirroot . '/mod/sciencedata/backup/moodle2/restore_sciencedata_stepslib.php');

class restore_sciencedata_activity_task extends restore_activity_task {
    protected function define_my_settings() {
    }

    protected function define_my_steps() {
        $this->add_step(new restore_sciencedata_activity_structure_step('sciencedata_structure', 'sciencedata.xml'));
    }

    public static function define_decode_contents() {
        return [new restore_decode_content('sciencedata', ['intro'], 'sciencedata')];
    }

    public static function define_decode_rules() {
        return [
            new restore_decode_rule('SCIENCEDATAINDEX', '/mod/sciencedata/index.php?id=$1', 'course'),
            new restore_decode_rule('SCIENCEDATAVIEWBYID', '/mod/sciencedata/view.php?id=$1', 'course_module'),
        ];
    }

    public static function define_restore_log_rules() {
        return [
            new restore_log_rule('sciencedata', 'add', 'view.php?id={course_module}', '{sciencedata}'),
            new restore_log_rule('sciencedata', 'update', 'view.php?id={course_module}', '{sciencedata}'),
            new restore_log_rule('sciencedata', 'view', 'view.php?id={course_module}', '{sciencedata}'),
        ];
    }

    public static function define_restore_log_rules_for_course() {
        return [new restore_log_rule('sciencedata', 'view all', 'index.php?id={course}', null)];
    }
}
