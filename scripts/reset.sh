#!/bin/bash

killall beam.smp
rm -R data

su - postgres
psql
# CREATE USER kambei WITH PASSWORD 'secret';
drop database ippan;
create database ippan;
GRANT ALL PRIVILEGES ON DATABASE ippan TO kambei;
exit
exit

rm nohup.out
