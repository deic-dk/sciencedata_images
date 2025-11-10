create database immich;
create user immich with encrypted password 'secret';
grant all privileges on database immich to immich;
ALTER USER immich WITH SUPERUSER;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS vchord CASCADE;