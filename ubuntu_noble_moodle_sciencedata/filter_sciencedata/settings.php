<?php
defined('MOODLE_INTERNAL') || die();

if ($ADMIN->fulltree) {
    $settings->add(new admin_setting_configtext('filter_sciencedata/hosts',
        get_string('hosts', 'filter_sciencedata'), get_string('hosts_desc', 'filter_sciencedata'), 'sciencedata.dk', PARAM_RAW_TRIMMED));
    $settings->add(new admin_setting_configtext('filter_sciencedata/nbviewer',
        get_string('nbviewer', 'filter_sciencedata'), get_string('nbviewer_desc', 'filter_sciencedata'), 'https://kube.sciencedata.dk:8443', PARAM_URL));
    $settings->add(new admin_setting_configtext('filter_sciencedata/runurl',
        get_string('runurl', 'filter_sciencedata'), get_string('runurl_desc', 'filter_sciencedata'), '', PARAM_URL));
}
