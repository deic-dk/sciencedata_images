<?php
defined('MOODLE_INTERNAL') || die();

$capabilities = [
    // see the folder and download its files
    'mod/sciencedata:view' => [
        'captype' => 'read',
        'contextlevel' => CONTEXT_MODULE,
        'archetypes' => ['guest' => CAP_ALLOW, 'user' => CAP_ALLOW],
    ],
    // upload, make folders, delete - straight in ScienceData
    'mod/sciencedata:manage' => [
        'riskbitmask' => RISK_XSS,
        'captype' => 'write',
        'contextlevel' => CONTEXT_MODULE,
        'archetypes' => ['editingteacher' => CAP_ALLOW, 'manager' => CAP_ALLOW],
    ],
    'mod/sciencedata:addinstance' => [
        'riskbitmask' => RISK_XSS,
        'captype' => 'write',
        'contextlevel' => CONTEXT_COURSE,
        'archetypes' => ['editingteacher' => CAP_ALLOW, 'manager' => CAP_ALLOW],
        'clonepermissionsfrom' => 'moodle/course:manageactivities',
    ],
];
