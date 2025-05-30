include config.mk

PREFIX?=/usr/local
R2V=$(VERSION)
R2V?=5.9.8
USE_FRIDA_TOOLS=0
# frida_version=16.5.9
frida_version=$(shell grep 'set frida_version=' make.bat| cut -d = -f 2)
#frida_version=16.5.9
frida_major=$(shell echo $(frida_version)|cut -d . -f 1)

ifeq ($(frida_major),15)
R2FRIDA_PRECOMPILED_AGENT=1
else
# frida 16
R2FRIDA_PRECOMPILED_AGENT?=0
endif

R2FRIDA_PRECOMPILED_AGENT_URL=https://github.com/nowsecure/r2frida/releases/download/$(VERSION)/_agent.js

frida_version_major=$(shell echo $(frida_version) | cut -d . -f 1)

CFLAGS+=-DFRIDA_VERSION_STRING=\"${frida_version}\"
CFLAGS+=-DFRIDA_VERSION_MAJOR=${frida_version_major}

ifeq ($(strip $(frida_os)),)
ifeq ($(shell uname -o 2> /dev/null),Android)
frida_os := android
else
frida_os := $(shell uname -s | tr '[A-Z]' '[a-z]' | sed 's,^darwin$$,macos,')
endif
endif

ifeq ($(frida_os),linux)
HAVE_MUSL=$(shell (grep -q musl /bin/ls && test -x /lib/ld-musl*) && echo 1 || echo 0)
R2FRIDA_COMPILE_FLAGS=-Wl,-z,noexecstack
else
R2FRIDA_COMPILE_FLAGS=
HAVE_MUSL=0
endif

## not linux-arm64
ifeq ($(frida_os),android)
frida_arch := $(shell uname -m | sed -e 's,i[0-9]86,x86,g' -e 's,armv.*,arm,g' -e 's,aarch64,arm64,g')
frida_os_arch := $(frida_os)-$(frida_arch)
else
frida_arch := $(shell uname -m | sed -e 's,i[0-9]86,x86,g' -e 's,armv.*,armhf,g' -e 's,aarch64,arm64,g')
ifeq ($(HAVE_MUSL),1)
frida_os_arch := $(frida_os)-$(frida_arch)-musl
else
frida_os_arch := $(frida_os)-$(frida_arch)
endif
endif

WGET?=wget
CURL?=curl

ifneq ($(shell $(WGET) --help 2> /dev/null),)
USE_WGET=1
DLCMD=$(WGET) -c -q -O
else
USE_WGET=0
DLCMD=$(CURL) -Ls -o
endif

DESTDIR?=

ifeq ($(shell uname),Darwin)
# CFLAGS+=-arch arm64e -arch arm64
# LDFLAGS+=-arch arm64e -arch arm64
SO_EXT=dylib
else
SO_EXT=so
endif
CC?=gcc
CXX?=g++
CFLAGS+=-fPIC
LDFLAGS+=-fPIC
PLUGIN_LDFLAGS+=-shared -fPIC
CFLAGS+=-Wall
CFLAGS+=-Werror

CFLAGS+=-g
LDFLAGS+=-g

# R2
CFLAGS+=$(shell r2pm -r pkg-config --cflags r_core r_io r_util)
ifeq ($(frida_os),android)
LDFLAGS+=$(subst -lssl,,$(shell pkg-config --libs r_core r_io r_util))
else
LDFLAGS+=$(shell r2pm -r pkg-config --libs r_core r_io r_util)
endif
R2_BINDIR=$(shell r2 -H R2_PREFIX)/bin
R2PM_BINDIR=$(shell r2pm -H R2PM_BINDIR)
R2PM_MANDIR=$(shell r2pm -H R2PM_MANDIR)
ifeq ($(R2PM_MANDIR),)
R2PM_MANDIR := "$(R2PM_BINDIR)/../man"
$(warning "r2pm does not export a directory for manpages. Using $(R2PM_MANDIR).")
endif
R2_PLUGDIR=$(shell r2 -H R2_USER_PLUGINS)
R2_PLUGSYS=$(shell r2 -H R2_LIBR_PLUGINS)
ifeq ($(R2_PLUGDIR),)
r2:
	@echo Please install r2
	@exit 1
endif

CXXFLAGS+=$(CFLAGS)

USE_ASAN?=0
ifeq ($(USE_ASAN),1)
ASAN_CFLAGS=-fsanitize=address,undefined,signed-integer-overflow,integer-divide-by-zero
ASAN_LDFLAGS=$(ASAN_CFLAGS)
CFLAGS+=$(ASAN_CFLAGS)
LDFLAGS+=$(ASAN_LDFLAGS)
endif

WANT_SESSION_DEBUGGER?=1

CFLAGS+=-DWANT_SESSION_DEBUGGER=$(WANT_SESSION_DEBUGGER)

# FRIDA
FRIDA_SDK=ext/frida-$(frida_os)-$(frida_version)/libfrida-core.a
FRIDA_SDK_URL=https://github.com/frida/frida/releases/download/$(frida_version)/frida-core-devkit-$(frida_version)-$(frida_os_arch).tar.xz
FRIDA_CFLAGS+=-Iext/frida
FRIDA_CORE_LIBS=ext/frida/libfrida-core.a
#FRIDA_CORE_LIBS=$(shell find /tmp/lib/*.a)

FRIDA_LIBS+=$(FRIDA_CORE_LIBS)

# OSX-FRIDA
ifeq ($(shell uname),Darwin)
PLUGIN_LDFLAGS+=-Wl,-exported_symbol,_radare_plugin
  ifeq ($(frida_os),macos)
FRIDA_LDFLAGS+=-Wl,-no_compact_unwind
FRIDA_LIBS+=-framework Foundation
FRIDA_LIBS+=-framework IOKit
  endif
  ifeq ($(frida_os),ios)
FRIDA_LIBS+=-framework UIKit
FRIDA_LIBS+=-framework CoreGraphics
FRIDA_LIBS+=-framework Foundation
  else
  ifeq ($(frida_os),macos)
FRIDA_LIBS+=-lbsm
FRIDA_LIBS+=-framework Security
endif
  endif
  ifeq ($(frida_os),macos)
FRIDA_LIBS+=-framework AppKit
  endif
endif
ifneq ($(frida_os),android)
FRIDA_LIBS+=-lresolv
endif

ifeq ($(frida_os),android)
LDFLAGS+=-landroid -llog -lm
STRIP_SYMBOLS=yes
endif

ifeq ($(frida_os),linux)
LDFLAGS+=-Wl,--start-group
LDFLAGS+=-lm
endif

ifeq ($(STRIP_SYMBOLS),yes)
PLUGIN_LDFLAGS+=-Wl,--version-script,ld.script
PLUGIN_LDFLAGS+=-Wl,--gc-sections
endif

ifeq ($(frida_os),linux)
LDFLAGS+=-Wl,--end-group
endif

all: ext/frida
	rm -f src/_agent*
ifeq ($(frida_version_major),16)
	$(MAKE) src/r2frida-compile
endif
	$(MAKE) io_frida.$(SO_EXT)

deb:
	$(MAKE) -C dist/debian

IOS_ARCH=arm64
#armv7
IOS_ARCH_CFLAGS=$(addprefix -arch ,$(IOS_ARCH))
IOS_CC=xcrun --sdk iphoneos gcc $(IOS_ARCH_CFLAGS)
IOS_CXX=xcrun --sdk iphoneos g++ $(IOS_ARCH_CFLAGS)

.PHONY: io_frida.$(SO_EXT)

# XXX we are statically linking to the .a we should use shared libs if exist
ios:
	rm -rf ext
	$(MAKE) clean && $(MAKE)
	$(MAKE) src/_agent.h \
		&& cp -f src/_agent.h src/_agent.h.host \
		&& cp -f src/_agent.js src/_agent.js.host
	$(MAKE) r2-sdk-ios/$(R2V)
	rm -rf ext
	rm -f src/*.o
	$(MAKE) R2FRIDA_HOST_COMPILER=1 \
	CFLAGS="-Ir2-sdk-ios/include -Ir2-sdk-ios/include/libr \
	-DR2FRIDA_VERSION_STRING=\\\"${VERSION}\\\" \
	-DFRIDA_VERSION_STRING=\\\"${frida_version}\\\"" \
	LDFLAGS="-shared -fPIC r2-sdk-ios/lib/libr.a" \
	HOST_CC="$(CC)" CC="$(IOS_CC)" CXX="$(IOS_CXX)" \
	frida_os=ios frida_arch=arm64

r2-sdk-ios/$(R2V):
	rm -rf r2-sdk-ios
	$(DLCMD) r2-sdk-ios-$(R2V).zip https://github.com/radareorg/radare2/releases/download/$(R2V)/r2ios-sdk-$(R2V).zip
	mkdir -p r2-sdk-ios
	cd r2-sdk-ios/ && unzip ../r2-sdk-ios-$(R2V).zip
	mv r2-sdk-ios/usr/* r2-sdk-ios
	mkdir r2-sdk-ios/include/libr/sys
	touch r2-sdk-ios/include/libr/sys/ptrace.h

.PHONY: ext/frida asan

asan:
	$(MAKE) clean
	$(MAKE) USE_ASAN=1

ext/frida: $(FRIDA_SDK)
	[ "`readlink ext/frida`" = frida-$(frida_os)-$(frida_version) ] || \
		(cd ext && rm -f frida ; ln -fs frida-$(frida_os)-$(frida_version) frida)

config.mk config.h:
	./configure

io_frida.$(SO_EXT): src/io_frida.o
	pkg-config --cflags r_core
	$(CC) $^ -o $@ $(LDFLAGS) $(PLUGIN_LDFLAGS) $(FRIDA_LDFLAGS) $(FRIDA_LIBS)

src/io_frida.o: src/io_frida.c $(FRIDA_SDK) src/_agent.h
	$(CC) -c $(CFLAGS) $(FRIDA_CFLAGS) $< -o $@

src/_agent.h: src/_agent.js
	test -s src/_agent.js || ( rm -f src/_agent.js && ${MAKE} src/_agent.js )
	test -s src/_agent.js || exit 1
	[ -f src/_agent.h ] || (echo Running r2; r2 -NNnfqcpc $< | grep 0x > $@)

ifeq ($(R2FRIDA_HOST_COMPILER),1)
src/_agent.js:
	mv src/_agent.h.host src/_agent.h
	mv src/_agent.js.host src/_agent.js
	test -s src/_agent.js || rm -f src/_agent.js
else
src/_agent.js: src/r2frida-compile
ifeq ($(R2FRIDA_PRECOMPILED_AGENT),1)
	$(DLCMD) src/_agent.js $(R2FRIDA_PRECOMPILED_AGENT_URL)
else
ifeq ($(USE_FRIDA_TOOLS),1)
	frida-compile -o src/_agent.js -Sc src/agent/index.ts
	rax2 -qC < src/_agent.js > src/_agent.h
else
	R2PM_OFFLINE=1 r2pm -r src/r2frida-compile -H src/_agent.h -o src/_agent.js -Sc src/agent/index.ts || \
		src/r2frida-compile -H src/_agent.h -o src/_agent.js -Sc src/agent/index.ts
endif
	test -s src/_agent.js || rm -f src/_agent.js
endif
endif

node_modules:
	mkdir -p node_modules
	npm i

R2A_ROOT=$(shell pwd)/radare2-android-libs

R2S=~/prg/radare2/sys/android-shell.sh

android:
	# git clean -xdf
	rm -rf ext
	# building for arm64
	touch src/io_frida.c
	$(R2S) aarch64 $(MAKE) android-arm64 frida_os=android
ifeq ($(STRIP_SYMBOLS),yes)
	$(R2S) aarch64 aarch64-linux-android-strip io_frida.so
endif
	cp -f io_frida.so /tmp/io_frida-$(R2V)-android-arm64.so
	# git clean -xdf
	touch src/io_frida.c
	rm -rf ext
	# building for arm
	$(R2S) arm $(MAKE) android-arm frida_os=android
ifeq ($(STRIP_SYMBOLS),yes)
	$(R2S) arm arm-linux-androideabi-strip io_frida.so
endif
	cp -f io_frida.so /tmp/io_frida-$(R2V)-android-arm.so

radare2-android-arm64-libs:
	$(DLCMD) radare2_$(R2V)_aarch64.deb http://termux.net/dists/stable/main/binary-aarch64/radare2_${R2V}_aarch64.deb
	$(DLCMD) radare2-dev_$(R2V)_aarch64.deb http://termux.net/dists/stable/main/binary-aarch64/radare2-dev_${R2V}_aarch64.deb
	mkdir -p $(R2A_ROOT)
	cd $(R2A_ROOT) && 7z x -y ../radare2_${R2V}_aarch64.deb && tar xzvf data.tar.gz || tar xJvf data.tar.xz
	cd $(R2A_ROOT) && 7z x -y ../radare2-dev_${R2V}_aarch64.deb && tar xzvf data.tar.gz || tar xJvf data.tar.xz
	ln -fs $(R2A_ROOT)/data/data/com.termux/files/

R2A_DIR=$(R2A_ROOT)/data/data/com.termux/files/usr

android-arm64: radare2-android-arm64-libs
	$(MAKE) frida_os=android frida_arch=arm64 CC=ndk-gcc CXX=ndk-g++ \
		CFLAGS="-I$(R2A_DIR)/include/libr $(CFLAGS)" \
		LDFLAGS="-L$(R2A_DIR)/lib $(LDFLAGS) $(PLUGIN_LDFLAGS)" SO_EXT=so

radare2-android-arm-libs:
	$(DLCMD) radare2_$(R2V)_arm.deb http://termux.net/dists/stable/main/binary-arm/radare2_$(R2V)_arm.deb
	$(DLCMD) radare2-dev_$(R2V)_arm.deb http://termux.net/dists/stable/main/binary-arm/radare2-dev_$(R2V)_arm.deb
	mkdir -p $(R2A_ROOT)
	cd $(R2A_ROOT) ; 7z x -y ../radare2_$(R2V)_arm.deb ; tar xzvf data.tar.gz || tar xJvf data.tar.xz
	cd $(R2A_ROOT) ; 7z x -y ../radare2-dev_$(R2V)_arm.deb ; tar xzvf data.tar.gz || tar xJvf data.tar.xz
	ln -fs $(R2A_ROOT)/data/data/com.termux/files/

android-arm: radare2-android-arm-libs
	$(MAKE) frida_os=android frida_arch=arm CC=ndk-gcc CXX=ndk-g++ \
		CFLAGS="-I$(R2A_DIR)/include/libr $(CFLAGS)" \
		LDFLAGS="-L$(R2A_DIR)/lib $(LDFLAGS) $(PLUGIN_LDFLAGS)" SO_EXT=so

clean:
	$(RM) src/*.o src/_agent.js src/_agent.h config.h
	$(RM) -f src/r2frida-compile src/frida-compile
	$(RM) -rf ext
	$(RM) -f frida-sdk.tar.xz
	$(RM) -f src/io_frida.dylib src/io_frida.so
	$(RM) -rf $(R2A_DIR)

mrproper: clean
	$(RM) -rf node_modules
	$(RM) $(FRIDA_SDK)
	$(RM) -r ext/frida-$(frida_version)
	$(RM) ext/frida
	$(RM) -r ext/node

# user wide

user-install:
	mkdir -p $(DESTDIR)/"$(R2_PLUGDIR)"
	mkdir -p $(DESTDIR)/"$(R2PM_BINDIR)"
	$(RM) "$(DESTDIR)/$(R2_PLUGDIR)/io_frida.$(SO_EXT)"
	cp -f io_frida.$(SO_EXT)* $(DESTDIR)/"$(R2_PLUGDIR)"
	cp -f src/r2frida-compile $(DESTDIR)/"$(R2PM_BINDIR)"
	-mkdir -p "$(DESTDIR)/$(R2PM_MANDIR)/man1"
	-cp -f r2frida.1 "$(DESTDIR)/$(R2PM_MANDIR)/man1/r2frida.1"

user-uninstall:
	$(RM) "$(DESTDIR)/$(R2_PLUGDIR)/io_frida.$(SO_EXT)"
	$(RM) "$(DESTDIR)/$(R2PM_BINDIR)/r2frida-compile"
	-sudo $(RM) "$(DESTDIR)/$(PREFIX)/share/man/man1/r2frida.1"

user-symstall:
	mkdir -p "$(DESTDIR)/$(R2_PLUGDIR)"
	ln -fs $(shell pwd)/io_frida.$(SO_EXT)* "$(DESTDIR)/$(R2_PLUGDIR)"
	-sudo mkdir -p "$(DESTDIR)/$(PREFIX)/share/man/man1"
	-sudo ln -fs $(shell pwd)/r2frida.1 "$(DESTDIR)/$(PREFIX)/share/man/man1/r2frida.1"

# system wide

install:
	mkdir -p "$(DESTDIR)/$(R2_PLUGSYS)"
	cp -f io_frida.$(SO_EXT)* $(DESTDIR)/"$(R2_PLUGSYS)"
	mkdir -p "$(DESTDIR)/$(R2_BINDIR)"
	cp -f src/r2frida-compile $(DESTDIR)/"$(R2_BINDIR)"
	mkdir -p "$(DESTDIR)/$(PREFIX)/share/man/man1"
	cp -f r2frida.1 $(DESTDIR)/$(PREFIX)/share/man/man1/r2frida.1

symstall:
	mkdir -p "$(DESTDIR)/$(R2_PLUGSYS)"
	ln -fs $(shell pwd)/io_frida.$(SO_EXT)* $(DESTDIR)/"$(R2_PLUGSYS)"
	-mkdir -p "$(DESTDIR)/$(PREFIX)/share/man/man1"
	-ln -fs $(shell pwd)/r2frida.1 $(DESTDIR)/$(PREFIX)/share/man/man1/r2frida.1

uninstall:
	$(RM) "$(DESTDIR)/$(R2_PLUGSYS)/io_frida.$(SO_EXT)"
	$(RM) "$(DESTDIR)/$(R2_BINDIR)/r2frida-compile"
	$(RM) "$(DESTDIR)/$(PREFIX)/share/man/man1/r2frida.1"

release:
	$(MAKE) android STRIP_SYMBOLS=yes
	$(MAKE) -C dist/debian

indent fmt:
	deno fmt --indent-width 4 src/agent *.json

frida-sdk: ext/frida-$(frida_os)-$(frida_version)
	rm -f ext/frida
	cd ext && ln -fs frida-$(frida_os)-$(frida_version) frida

src/r2frida-compile: src/r2frida-compile.c node_modules
	$(CC) -g src/r2frida-compile.c $(FRIDA_CFLAGS) $(R2FRIDA_COMPILE_FLAGS) \
		$(shell pkg-config --cflags --libs r_util) $(FRIDA_LIBS) \
		$(CFLAGS) $(LDFLAGS) -pthread -Iext/frida -o $@

ext/frida-$(frida_os)-$(frida_version):
	@echo FRIDA_SDK=$(FRIDA_SDK)
	$(MAKE) $(FRIDA_SDK)

$(FRIDA_SDK):
	rm -f ext/frida
	mkdir -p $(@D)/_
ifeq (${USE_WGET},0)
	$(CURL) -Ls $(FRIDA_SDK_URL) | xz -d | tar -C $(@D)/_ -xf -
else
	rm -f frida-sdk.tar.xz
	$(DLCMD) frida-sdk.tar.xz -c $(FRIDA_SDK_URL)
	tar xJvf frida-sdk.tar.xz -C $(@D)/_
endif
	mv $(@D)/_/* $(@D)
	rmdir $(@D)/_
	#mv ext/frida ext/frida-$(frida_os)-$(frida_version)
	cd ext && ln -fs frida-$(frida_os)-$(frida_version) frida

vs:
	open -a "Visual Studio Code" .

update:
	$(RM) ext/frida/libfrida-core.a

.PHONY: all clean install user-install uninstall user-uninstall release symstall
