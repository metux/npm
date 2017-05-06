# vim: set softtabstop=2 shiftwidth=2:
SHELL = bash

## the nodeJS command to be run at build time
NODEJS ?= node
NODEJS_INTERPRETER ?= /usr/bin/env $(NODEJS)

PUBLISHTAG = $(shell node scripts/publish-tag.js)
BRANCH = $(shell git rev-parse --abbrev-ref HEAD)

markdowns = $(shell find doc -name '*.md' | grep -v 'index') README.md

html_docdeps = html/dochead.html \
               html/docfoot.html \
               scripts/doc-build.sh \
               package.json

cli_mandocs = $(shell find doc/cli -name '*.md' \
               |sed 's|.md|.1|g' \
               |sed 's|doc/cli/|man/man1/|g' ) \
               man/man1/npm-README.1

files_mandocs = $(shell find doc/files -name '*.md' \
               |sed 's|.md|.5|g' \
               |sed 's|doc/files/|man/man5/|g' ) \
               man/man5/npm-json.5 \
               man/man5/npm-global.5

misc_mandocs = $(shell find doc/misc -name '*.md' \
               |sed 's|.md|.7|g' \
               |sed 's|doc/misc/|man/man7/|g' ) \
               man/man7/npm-index.7

cli_htmldocs = $(shell find doc/cli -name '*.md' \
                |sed 's|.md|.html|g' \
                |sed 's|doc/cli/|html/doc/cli/|g' ) \
                html/doc/README.html

files_htmldocs = $(shell find doc/files -name '*.md' \
                  |sed 's|.md|.html|g' \
                  |sed 's|doc/files/|html/doc/files/|g' ) \
                  html/doc/files/npm-json.html \
                  html/doc/files/npm-global.html

misc_htmldocs = $(shell find doc/misc -name '*.md' \
                 |sed 's|.md|.html|g' \
                 |sed 's|doc/misc/|html/doc/misc/|g' ) \
                 html/doc/index.html

mandocs = $(cli_mandocs) $(files_mandocs) $(misc_mandocs)

htmldocs = $(cli_htmldocs) $(files_htmldocs) $(misc_htmldocs)

## command for building the docs
define build-docs
@echo "Building manpage: $@"
@mkdir -p $(dir $@)
@NODEJS="$(NODEJS)" scripts/doc-build.sh $< $@
endef

## command for calling the local (build-time) npm cli
define npm-local
$(NODEJS) bin/npm-cli.js
endef

define npm-local-install
$(call npm-local) install
endef

ifdef NODEJS_LIB_DIR
NPM_INSTALL_OPT = --prefix "$(DESTDIR)$(NODEJS_LIB_DIR)"
endif

all: doc

latest:	preprocess
	@echo "Installing latest published npm"
	@echo "Use 'make install' or 'make link' to install the code"
	@echo "in this folder that you're looking at right now."
	$(call npm-local-install) -g -f $(NPM_INSTALL_OPT) npm ${NPMOPTS}

install: all preprocess
	$(call npm-local-install) -g -f $(NPM_INSTALL_OPT) ${NPMOPTS}

# backwards compat
dev: install

link: uninstall preprocess
	$(call npm-local) link -f

clean: preprocess doc-clean
	rm -rf npmrc
	-$(call npm-local) cache clean
	$(MAKE) preprocess-clean

uninstall: preprocess
	$(call npm-local) rm npm -g -f

doc: preprocess $(mandocs) $(htmldocs)

docclean: doc-clean
doc-clean:
	rm -rf \
    html/doc \
    man

## build-time tools for the documentation
build-doc-tools := $(PREPROCESS_OUT)

man/man1/npm-README.1: README.md scripts/doc-build.sh package.json $(build-doc-tools)
	$(call build-docs)

man/man1/%.1: doc/cli/%.md scripts/doc-build.sh package.json $(build-doc-tools)
	$(call build-docs)

man/man5/npm-json.5: man/man5/package.json.5
	cp $< $@

man/man5/npm-global.5: man/man5/npm-folders.5
	cp $< $@

man/man5/%.5: doc/files/%.md scripts/doc-build.sh package.json $(build-doc-tools)
	$(call build-docs)

doc/misc/npm-index.md: scripts/index-build.js package.json $(build-doc-tools)
	$(NODEJS) scripts/index-build.js > $@

html/doc/index.html: doc/misc/npm-index.md $(html_docdeps) $(build-doc-tools)
	$(call build-docs)

man/man7/%.7: doc/misc/%.md scripts/doc-build.sh package.json $(build-doc-tools)
	$(call build-docs)

html/doc/README.html: README.md $(html_docdeps) $(build-doc-tools)
	$(call build-docs)

html/doc/cli/%.html: doc/cli/%.md $(html_docdeps) $(build-doc-tools)
	$(call build-docs)

html/doc/files/npm-json.html: html/doc/files/package.json.html
	cp $< $@

html/doc/files/npm-global.html: html/doc/files/npm-folders.html
	cp $< $@

html/doc/files/%.html: doc/files/%.md $(html_docdeps) $(build-doc-tools)
	$(call build-docs)

html/doc/misc/%.html: doc/misc/%.md $(html_docdeps) $(build-doc-tools)
	$(call build-docs)

doc: man

man: $(cli_docs)

test: preprocess doc
	$(call npm-local) test

tag: preprocess
	$(call npm-local) tag npm@$(PUBLISHTAG) latest

ls-ok:
	$(NODEJS) . ls >/dev/null

gitclean:
	git clean -fd

publish: gitclean ls-ok link doc-clean doc preprocess
	@git push origin :v$(shell $(call npm-local) --no-timing -v) 2>&1 || true
	git push origin $(BRANCH) &&\
	git push origin --tags &&\
	$(call npm-local) publish --tag=$(PUBLISHTAG)

release: gitclean ls-ok doc-clean doc preprocess
	$(call npm-local) prune --production
	@bash scripts/release.sh

sandwich:
	@[ $$(whoami) = "root" ] && (echo "ok"; echo "ham" > sandwich) || (echo "make it yourself" && exit 13)

## generate executable scripts with nodejs command
PREPROCESS_IN  := \
	$(shell find bin node_modules scripts test/tap -type f -name "*.prepro.in") \
	package.json.prepro.in
PREPROCESS_OUT := $(patsubst %.prepro.in,%,$(PREPROCESS_IN))

define preproc
	@echo "Transforming $< to $@"
	@cat $< | sed -e 's~@@NODEJS_INTERPRETER@@~$(NODEJS_INTERPRETER)~g;' \
	       | sed -e 's~@@NODEJS@@~$(NODEJS)~g;' > $@
	@chmod "$@" --reference="$<"
endef

%:	%.prepro.in
	$(call preproc)

scripts/%:	scripts/%.prepro.in
	$(call preproc)

preprocess: $(PREPROCESS_OUT)

preprocess-clean:
	@rm -f $(PREPROCESS_OUT)

.PHONY: all latest install dev link doc clean uninstall test man doc-clean docclean release ls-ok realclean \
        preprocess preprocess-clean
