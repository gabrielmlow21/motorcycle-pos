-- Runs once, on first boot of an empty mysql-data volume.
--
-- The test suite needs its own database so `php artisan test` can migrate and
-- truncate freely without destroying the data you are developing against.
CREATE DATABASE IF NOT EXISTS pos_test
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

GRANT ALL PRIVILEGES ON pos_test.* TO 'posadmin'@'%';
FLUSH PRIVILEGES;
