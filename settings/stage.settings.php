<?php
if(getenv('SDMC_ENV') == 'stage') {
putenv('AH_SITE_ENVIRONMENT=stg');

$db_name = 'sdmc';
$databases = [
  'default' =>
  [
    'default' =>
    [
      'database' => $db_name,
      'username' => 'drupal',
      'password' => 'insecure.password',
      'host' => 'localhost',
      'port' => '3306',
      'namespace' => 'Drupal\\Core\\Database\\Driver\\mysql',
      'driver' => 'mysql',
      'prefix' => '',
    ],
  ],
];

$settings['trusted_host_patterns'] = [
  '^stage\.loc$',
  '^localhost',
  '^10\.70\.20\.167',
];

  $config['config_split.config_split.prod']['status'] = FALSE;
  $config['config_split.config_split.local']['status'] = FALSE;
  $config['config_split.config_split.dev']['status'] = FALSE;
  $config['config_split.config_split.stage']['status'] = TRUE;

  $config['google_analytics.settings']['account'] = 'UA-XXXXXXXX-X';
/*
  // Memcache configuration.
  $settings['memcache']['servers'] = ['127.0.0.1:11211' => 'default'];
  $settings['memcache']['bins'] = ['default' => 'default'];
  $settings['memcache']['key_prefix'] = 'stage';
  $settings['cache']['default'] = 'cache.backend.memcache';
  */
  }
