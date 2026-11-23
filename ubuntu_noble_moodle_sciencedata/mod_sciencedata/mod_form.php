<?php
defined('MOODLE_INTERNAL') || die();

require_once($CFG->dirroot . '/course/moodleform_mod.php');

class mod_sciencedata_mod_form extends moodleform_mod {
    public function definition() {
        global $DB;
        $mform = $this->_form;

        $mform->addElement('text', 'name', get_string('name'), ['size' => '48']);
        $mform->setType('name', PARAM_TEXT);
        $mform->addRule('name', null, 'required', null, 'client');
        $this->standard_intro_elements();

        // the folders in 'Course material' - one per group that logs in
        $folders = [];
        foreach ((new \mod_sciencedata\dav(''))->ls('') ?? [] as $e) {
            if ($e['folder']) {
                $folders[$e['name']] = $e['name'];
            }
        }
        $current = (string)($this->current->folder ?? '');
        if ($current !== '' && !isset($folders[$current])) {
            $folders = [$current => $current] + $folders; // kept even if it is gone
        }
        if ($folders) {
            $mform->addElement('select', 'folder', get_string('folder', 'sciencedata'), $folders);
            // a new activity: the folder of a group this course enrols by cohort sync, if any
            if ($current === '' && !empty($this->current->course)) {
                $cohorts = $DB->get_fieldset_sql("SELECT c.name FROM {enrol} e JOIN {cohort} c ON c.id = e.customint1
                    WHERE e.enrol = 'cohort' AND e.courseid = ?", [$this->current->course]);
                foreach ($cohorts as $name) {
                    $safe = trim(str_replace(['/', '\\'], '-', $name), ' .');
                    if (isset($folders[$safe])) {
                        $mform->setDefault('folder', $safe);
                        break;
                    }
                }
            }
        } else {
            $mform->addElement('static', 'nofolders', get_string('folder', 'sciencedata'), get_string('nofolders', 'sciencedata'));
            $mform->addElement('hidden', 'folder', '');
        }
        $mform->setType('folder', PARAM_RAW);
        $mform->addHelpButton('folder', 'folder', 'sciencedata');

        $this->standard_coursemodule_elements();
        $this->add_action_buttons();
    }

    public function validation($data, $files) {
        $errors = parent::validation($data, $files);
        if (\mod_sciencedata\dav::clean((string)($data['folder'] ?? '')) === null) {
            $errors['folder'] = get_string('invalid');
        }
        return $errors;
    }
}
