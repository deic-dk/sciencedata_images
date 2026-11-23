<?php
defined('MOODLE_INTERNAL') || die();

$definitions = [
    // what a share link points to - asked once an hour per link, not on every page view
    'shares' => [
        'mode' => cache_store::MODE_APPLICATION,
        'simplekeys' => true,
        'simpledata' => false,
        'ttl' => 3600,
    ],
];
