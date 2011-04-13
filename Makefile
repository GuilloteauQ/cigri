#!/usr/bin/make
# $Id$
SHELL=/bin/bash

PREFIX=/usr/local
MANDIR=$(PREFIX)/man
BINDIR=$(PREFIX)/bin
SBINDIR=$(PREFIX)/sbin
CIGRIDIR=$(PREFIX)/share/cigri
DOCDIR=$(PREFIX)/share/doc/cigri
VARDIR=/var/lib/cigri
CONFDIR=/etc
WWWDIR=/var/www
WWWUSER=www-data
WWWGROUP=www-data
CIGRIOWNER=cigri
CIGRIGROUP=cigri

SPEC_OPTS=--colour --format nested

.PHONY: man

all: usage

install: usage

usage:
	@echo "WORK IN PROGRESS..."
	@echo "Usage: make < rdoc | yard | tests | cov >"

rdoc:
	rdoc -o doc/rdoc

yard:
	yard -o doc/yard lib modules

spec: tests

rspec: tests

tests: spec/*/*_spec.rb
	rspec $? ${SPEC_OPTS}

cov: rcov

rcov: spec/*/*_spec.rb modules/*/* lib/* spec/spec_helper.rb
	rcov -I lib:spec spec/**/*.rb --exclude gems -o doc/rcov -T

test-setup: test-setup-pg test-setup-mysql

test-setup-pg:
	database/init_db.rb -u cigritest -p cigritest -d cigritest -t psql -s database/psql_structure.sql
	sudo -u postgres psql cigritest -f spec/init_fill.sql

test-setup-mysql:
	database/init_db.rb -u cigritest -p cigritest -d cigritest -t mysql -s database/mysql_structure.sql
	mysql -u cigritest -pcigritest cigritest < spec/init_fill.sql


test-clean: test-clean-pg test-clean-mysql

test-clean-pg:
	-sudo -u postgres psql -c "drop database cigritest"
	-sudo -u postgres psql -c "drop role cigritest"

test-clean-mysql:
	-mysql -u root -p -e "drop database cigritest; drop user cigritest@localhost"

clean:
	rm -rf doc/rdoc doc/yard doc/rcov .yardoc
