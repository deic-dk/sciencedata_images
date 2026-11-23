<?php
namespace mod_sciencedata\event;

/** A ScienceData folder was viewed (for logs and activity completion). */
class course_module_viewed extends \core\event\course_module_viewed {
    protected function init() {
        $this->data['crud'] = 'r';
        $this->data['edulevel'] = self::LEVEL_PARTICIPATING;
        $this->data['objecttable'] = 'sciencedata';
    }
}
