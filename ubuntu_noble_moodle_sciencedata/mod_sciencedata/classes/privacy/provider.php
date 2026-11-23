<?php
namespace mod_sciencedata\privacy;

/** The activity stores no personal data; the files are on ScienceData. */
class provider implements \core_privacy\local\metadata\null_provider {
    public static function get_reason(): string {
        return 'privacy:metadata';
    }
}
