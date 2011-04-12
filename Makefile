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

tests:	spec/*/*_spec.rb
	rspec $? ${SPEC_OPTS}

cov: rcov

rcov: spec/*/*_spec.rb modules/*/* lib/*
	rcov -I lib spec/**/*.rb --exclude gems -o doc/rcov -T

clean:
	rm -rf doc/rdoc doc/yard doc/rcov .yardoc
