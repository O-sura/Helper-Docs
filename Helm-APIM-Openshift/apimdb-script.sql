/*Initial DB setup script for APIM*/
CREATE DATABASE apim_db CHARACTER SET latin1;
CREATE DATABASE shared_db CHARACTER SET latin1;

CREATE USER 'apimadmin'@'%' IDENTIFIED BY 'apimadmin';
GRANT ALL ON apim_db.* TO 'apimadmin'@'%';

CREATE USER 'sharedadmin'@'%' IDENTIFIED BY 'sharedadmin';
GRANT ALL ON shared_db.* TO 'sharedadmin'@'%';

FLUSH PRIVILEGES;
