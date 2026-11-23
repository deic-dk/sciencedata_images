<?php
defined('MOODLE_INTERNAL') || die();

// Teachers and managers add course material; students get it through the course.
$capabilities = [
    'repository/sciencedata:view' => [
        'captype' => 'read',
        'contextlevel' => CONTEXT_MODULE,
        'archetypes' => [
            'editingteacher' => CAP_ALLOW,
            'coursecreator' => CAP_ALLOW,
            'manager' => CAP_ALLOW,
        ],
    ],
];
