<?php

/**
 * @file
 * Helper for BLT using bitbucket to detect a CI env.
 */

if (isset($_ENV['BITBUCKET_COMMIT'])) {

  // Sets BLT "is_ci_env" variable.
  $_ENV['CI'] = TRUE;

  $databases = [
    'default' => [
      'default' => [
        'database' => 'drupal',
        'username' => 'drupal',
        'password' => 'drupal',
        'host' => '127.0.0.1',
        'port' => '3306',
        'namespace' => 'Drupal\\Core\\Database\\Driver\\mysql',
        'driver' => 'mysql',
        'prefix' => '',
      ],
    ],
  ];

}
