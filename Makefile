ifeq ($(findstring clean,$(MAKECMDGOALS)),)
-include Makefile.config
endif

all: opam opam-installer
	@

ifeq ($(JBUILDER),)
  JBUILDER_FILE = src_ext/jbuilder/_build/install/default/bin/jbuilder$(EXE)
  ifeq ($(shell command -v cygpath 2>/dev/null),)
    JBUILDER := $(JBUILDER_FILE)
  else
    JBUILDER := $(shell echo "$(JBUILDER_FILE)" | cygpath -f - -a)
  endif
else
  JBUILDER_FILE=
endif

ALWAYS:
	@

JBUILDER_DEP = ALWAYS $(JBUILDER_FILE)

src_ext/jbuilder/_build/install/default/bin/jbuilder$(EXE): src_ext/jbuilder.stamp
	cd src_ext/jbuilder && ocaml bootstrap.ml && ./boot.exe

src_ext/jbuilder.stamp:
	make -C src_ext jbuilder.stamp

jbuilder: $(JBUILDER_DEP)
	@$(JBUILDER) build @install

opam: $(JBUILDER_DEP) opam.install
	ln -sf _build/default/src/client/opamMain.exe $@

%-static: ALWAYS
	OPAM_BUILD_STATIC=true $(MAKE) $*

opam-installer: $(JBUILDER_DEP)
	$(JBUILDER) build src/tools/opam_installer.exe
	ln -sf _build/default/src/tools/opam_installer.exe $@

opam-admin.top: $(JBUILDER_DEP)
	$(JBUILDER) build src/tools/opam_admin_top.bc
	ln -sf _build/default/src/tools/opam_admin_top.bc $@

lib-ext:
	$(MAKE) -j -C src_ext lib-ext

download-ext:
	$(MAKE) -C src_ext archives

clean-ext:
	$(MAKE) -C src_ext distclean

clean:
	$(MAKE) -C doc $@
	rm -f *.install *.env *.err *.info *.out
	rm -rf _build

distclean: clean clean-ext
	rm -rf autom4te.cache bootstrap
	rm -f Makefile.config config.log config.status aclocal.m4
	rm -f src/*.META src/*/.merlin

OPAMINSTALLER_FLAGS = --prefix "$(DESTDIR)$(prefix)"
OPAMINSTALLER_FLAGS += --mandir "$(DESTDIR)$(mandir)"

# With ocamlfind, prefer to install to the standard directory rather
# than $(prefix) if there are no overrides
ifdef OCAMLFIND
ifndef DESTDIR
ifneq ($(OCAMLFIND),no)
    LIBINSTALL_DIR ?= $(shell $(OCAMLFIND) printconf destdir)
endif
endif
endif

ifneq ($(LIBINSTALL_DIR),)
    OPAMINSTALLER_FLAGS += --libdir "$(LIBINSTALL_DIR)"
endif

opam-devel.install: $(JBUILDER_DEP)
	$(JBUILDER) build -p opam opam.install
	sed -e "s/bin:/libexec:/" opam.install > $@

opam-%.install: $(JBUILDER_DEP)
	$(JBUILDER) build -p opam-$* $@

opam.install: $(JBUILDER_DEP)
	$(JBUILDER) build $@

opam-actual.install: opam.install
	@sed -n -e "/^bin: /,/^]/p" $< > $@
	@echo 'man: [' >>$@
	@$(patsubst %,echo '  "'%'"' >>$@;,$(wildcard doc/man/*.1))
	@echo ']' >>$@
	@echo 'doc: [' >>$@
	@$(foreach x,$(wildcard doc/man-html/*.html),\
	  echo '  "$x" {"man/$(notdir $x)"}' >>$@;)
	@$(foreach x,$(wildcard doc/pages/*.html),\
	  echo '  "$x" {"$(notdir $x)"}' >>$@;)
	@echo ']' >>$@

OPAMLIBS = core format solver repository state client

opam-%: $(JBUILDER_DEP)
	$(JBUILDER) build opam-$*.install

opam-lib: $(JBUILDER_DEP)
	$(JBUILDER) build $(patsubst %,opam-%.install,$(OPAMLIBS))

installlib-%: $(JBUILDER_DEP) opam-installer opam-%.install
	$(if $(wildcard src_ext/lib/*),\
	  $(error Installing the opam libraries is incompatible with embedding \
	          the dependencies. Run 'make clean-ext' and try again))
	$(JBUILDER) exec -- opam-installer $(OPAMINSTALLER_FLAGS) opam-$*.install

uninstalllib-%: $(JBUILDER_DEP) opam-installer opam-%.install
	$(JBUILDER) exec -- opam-installer -u $(OPAMINSTALLER_FLAGS) opam-$*.install

libinstall: $(JBUILDER_DEP) opam-admin.top $(OPAMLIBS:%=installlib-%)
	@

install: opam-actual.install $(JBUILDER_DEP)
	$(JBUILDER) exec -- opam-installer $(OPAMINSTALLER_FLAGS) $<

libuninstall: $(OPAMLIBS:%=uninstalllib-%)
	@

uninstall: opam-actual.install $(JBUILDER_DEP)
	$(JBUILDER) exec -- opam-installer -u $(OPAMINSTALLER_FLAGS) $<

.PHONY: tests tests-local tests-git
tests: $(JBUILDER_DEP)
	$(JBUILDER) runtest

# tests-local, tests-git
tests-%:
	$(MAKE) -C tests $*

.PHONY: doc
doc: all
	$(MAKE) -C doc

.PHONY: man man-html
man man-html: opam opam-installer
	$(MAKE) -C doc $@

configure: configure.ac m4/*.m4
	aclocal -I m4
	autoconf

release-tag:
	git tag -d latest || true
	git tag -a latest -m "Latest release"
	git tag -a $(version) -m "Release $(version)"

cold:
	./shell/bootstrap-ocaml.sh
	env PATH="`pwd`/bootstrap/ocaml/bin:$$PATH" ./configure $(CONFIGURE_ARGS)
	env PATH="`pwd`/bootstrap/ocaml/bin:$$PATH" $(MAKE) lib-ext
	env PATH="`pwd`/bootstrap/ocaml/bin:$$PATH" $(MAKE)
