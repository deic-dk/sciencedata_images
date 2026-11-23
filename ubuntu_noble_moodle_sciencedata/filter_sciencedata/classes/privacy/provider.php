<?php
namespace filter_sciencedata\privacy;

/** The filter stores no personal data. */
class provider implements \core_privacy\local\metadata\null_provider {
    public static function get_reason(): string {
        return 'privacy:metadata';
    }
}
