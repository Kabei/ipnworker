#!/bin/bash

su - postgres
psql
DROP DATABASE ippan;
CREATE DATABASE ippan;
CREATE USER kambei WITH PASSWORD 'secret';
GRANT ALL PRIVILEGES ON DATABASE ippan TO kambei;
exit
exit