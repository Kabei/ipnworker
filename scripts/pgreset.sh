#!/bin/bash

su - postgres
psql
DROP DATABASE ippan;
CREATE DATABASE ippan;
GRANT ALL PRIVILEGES ON DATABASE ippan TO kambei;
exit
exit