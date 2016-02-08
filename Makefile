# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.

.PHONY: help clean clean-dist sdist dist dev docs test test-js test-py test-scala init dev_image server install dev-build system-test clean-watch clean-watch-docs
.SUFFIXES:
MAKEFLAGS=-r

help:
	@echo '            init - setups machine with base requirements for dev'
	@echo '           clean - clean build files'
	@echo '     clean-watch - tries to stop the file watch started by dev'
	@echo 'clean-watch-docs - tries to stop the file watch started by docs'
	@echo '             dev - start container with source mounted for development'
	@echo '            docs - start container that serves documentation'
	@echo '           sdist - build a source distribution'
	@echo '         install - install latest sdist into a container'
	@echo '          server - starts a container with extension installed through pip'
	@echo '     system-test - run system integration tests with selenium'
	@echo '            test - run all units'
	@echo '         test-py - run python units'
	@echo '         test-js - run javascript units'
	@echo '      test-scala - run scala units'
	@echo '             all - run all necessary streps to produce and validate a build'


ROOT_REPO:=jupyter/all-spark-notebook:0017b56d93c9
REPO:=jupyter/all-spark-notebook-bower:0017b56d93c9

PYTHON?=python3

URTH_BOWER_FILES:=$(shell find elements -name bower.json)
URTH_SRC_DIRS:=$(foreach dir, $(URTH_BOWER_FILES), $(shell dirname $(dir)))
URTH_DIRS:=$(foreach dir, $(URTH_SRC_DIRS), $(shell basename $(dir)))
URTH_COMP_LINKS:=$(foreach dir, $(URTH_DIRS), $(shell echo "bower_components/$(dir)"))
NPM_BIN_DIR:=$(shell npm bin)
$(URTH_COMP_LINKS): | node_modules/bower $(URTH_SRC_DIRS)
	@echo 'Linking local Urth elements'
	@$(foreach dir, $(URTH_SRC_DIRS), cd $(abspath $(dir)) && $(NPM_BIN_DIR)/bower link;)
	@$(foreach name, $(URTH_DIRS), $(NPM_BIN_DIR)/bower link $(name);)

init: node_modules dev_image

node_modules: package.json
	@npm install

node_modules/bower: node_modules

bower_components: node_modules/bower bower.json
	@npm run bower -- install

dev_image:
	@-docker rm -f bower-build
	@docker run -it --user root --name bower-build \
		$(ROOT_REPO) bash -c 'apt-get update && \
		apt-get install --yes curl && \
		curl --silent --location https://deb.nodesource.com/setup_0.12 | sudo bash - && \
		apt-get install --yes nodejs npm && \
		ln -s /usr/bin/nodejs /usr/bin/node && \
		npm install -g bower'
	@docker commit bower-build $(REPO)
	@-docker rm -f bower-build

clean: clean-dist
	@-rm -rf *.egg-info
	@-rm -rf __pycache__ */__pycache__ */*/__pycache__
	@-find . -name '*.pyc' -exec rm -fv {} \;
	@-rm -rf bower_components node_modules

clean-dist:
	@-rm -rf dist

.watch: node_modules
	@echo 'Doing watch'
	@npm run watch & echo $$! > .watch

.watch-docs: node_modules
	@echo 'Doing watch-docs'
	@npm run watch-docs & echo $$! > .watch-docs

clean-watch:
	@echo 'Killing watch'
	-@kill -9 `pgrep -P $$(cat .watch)`
	-@rm .watch

clean-watch-docs:
	@echo 'Killing watch-docs'
	-@kill -9 `pgrep -P $$(cat .watch-docs)`
	-@rm .watch-docs

dist/urth/widgets/ext/notebook/js: ${shell find nb-extension/js}
	@echo 'Moving src/nb-extension'
	@mkdir -p dist/urth/widgets/ext/notebook/js
	@cp -R nb-extension/js/* dist/urth/widgets/ext/notebook/js/.

dist/urth/widgets/ext/notebook/elements: ${shell find elements}
	@echo 'Moving elements'
	@mkdir -p dist/urth/widgets/ext/notebook/elements
	@cp -R elements/* dist/urth/widgets/ext/notebook/elements/.
	@touch dist/urth/widgets/ext/notebook/elements

dist/urth/widgets/ext/notebook/bower_components: bower_components ${shell find elements} | $(URTH_COMP_LINKS)
	@echo 'Moving bower_components'
	@mkdir -p dist/urth/widgets/ext/notebook/bower_components
	@cp -RL bower_components/* dist/urth/widgets/ext/notebook/bower_components/.

dist/urth/widgets/ext/notebook: dist/urth/widgets/ext/notebook/bower_components dist/urth/widgets/ext/notebook/js dist/urth/widgets/ext/notebook/elements

dist/urth/widgets/ext: ${shell find nb-extension/python/urth/widgets/ext}
	@echo 'Moving frontend extension code'
	@mkdir -p dist/urth/widgets/ext
	@cp -R nb-extension/python/urth/widgets/ext/* dist/urth/widgets/ext/.

dist/urth: ${shell find kernel-python/urth} dist/urth/widgets/ext dist/urth/widgets/ext/notebook
	@echo 'Moving python code'
	@mkdir -p dist/urth
	@cp -R kernel-python/urth/* dist/urth/.

dist/urth/widgets/ext/notebook/urth-widgets.jar: ${shell find kernel-scala/src/main/scala/}
ifeq ($(NOSCALA), true)
	@echo 'Skipping scala code'
else
	@echo 'Building scala code'
	@mkdir -p dist/urth/widgets/ext/notebook
	@docker run -it --rm \
		-v `pwd`:/src \
		cloudet/sbt-sparkkernel-image:1.5.1 bash -c 'cp -r /src/kernel-scala /tmp/src && \
			cd /tmp/src && \
			sbt package && \
			cp target/scala-2.10/urth-widgets*.jar /src/dist/urth/widgets/ext/notebook/urth-widgets.jar'
endif

dist/docs: dist/docs/bower_components dist/docs/site dist/docs/site/generated_docs.json

dist/docs/bower_components: node_modules etc/docs/bower.json
	@echo 'Installing documentation dependencies'
	@mkdir -p dist/docs
	@cp etc/docs/bower.json dist/docs/bower.json
	@npm run docsbower -- install

dist/docs/site: node_modules ${shell find etc/docs/site}
	@echo 'Moving static doc site content'
	@mkdir -p dist/docs/site
	@cp -R etc/docs/site/* dist/docs/site
	@echo 'Running polybuild on docs.html'
	@npm run polybuild -- --maximum-crush dist/docs/site/docs.html
	@mv dist/docs/site/docs.build.html dist/docs/site/docs.html

dist/docs/site/generated_docs.json: dist/docs/site bower_components ${shell find elements/**/*.html} etc/docs/hydrolyze_elements.js etc/docs/urth-elements.html | $(URTH_COMP_LINKS)
	@echo 'Running hydrolysis to generate doc json'
	@node etc/docs/hydrolyze_elements.js 'etc/docs/urth-elements.html' 'dist/docs/site/generated_docs.json'

dist/scripts: etc/scripts/jupyter-declarativewidgets
	@mkdir -p dist/scripts
	@cp etc/scripts/jupyter-declarativewidgets dist/scripts/jupyter-declarativewidgets

dist/VERSION: COMMIT=$(shell git rev-parse --short=12 --verify HEAD)
dist/VERSION:
	@mkdir -p dist
	@echo "$(COMMIT)" > dist/VERSION

dist: dist/urth dist/urth/widgets/ext/notebook/urth-widgets.jar dist/scripts dist/VERSION

sdist: dist
	@cp -R MANIFEST.in dist/.
	@cp -R setup.py dist/.
	@docker run -it --rm \
		-v `pwd`/dist:/src \
		$(EXTRA_OPTIONS) \
		$(REPO) bash -c '$(SETUP_CMD) cp -r /src /tmp/src && \
			cd /tmp/src && \
			python setup.py sdist $(POST_SDIST) && \
			cp -r dist/*.tar.gz /src/.'

test: test-js test-py test-scala

test-js: | $(URTH_COMP_LINKS)
	@echo 'Running web component tests...'
	@npm run test

test-js-remote: | $(URTH_COMP_LINKS)
ifdef SAUCE_USER_NAME
	@echo 'Running web component tests remotely on Sauce Labs...'
	@npm run test-sauce --silent -- --sauce-tunnel-id \"$(TRAVIS_JOB_NUMBER)\" --sauce-username $(SAUCE_USER_NAME) --sauce-access-key $(SAUCE_ACCESS_KEY)
else
	@npm run test -- --local chrome
endif

test-py: dist/urth
	@echo 'Running python tests in $(PYTHON)...'
	@$(MAKE) _test-py-$(PYTHON)

_test-py-python2: EXTENSION_DIR=/opt/conda/envs/python2/lib/python2.7/site-packages/urth
_test-py-python2: CMD=python --version; python -m unittest discover $(EXTENSION_DIR) "test*[!_py3].py"
_test-py-python2: SETUP_CMD=source activate python2; pip install -U mock;
_test-py-python2: _test-py

_test-py-python3: EXTENSION_DIR=/usr/local/lib/python3.4/dist-packages/urth
_test-py-python3: CMD=python --version; python -m unittest discover $(EXTENSION_DIR)
_test-py-python3: _test-py

_test-py:
	@docker run -it --rm \
		-v `pwd`/dist/urth:$(EXTENSION_DIR) \
		$(REPO) bash -c '$(SETUP_CMD) $(CMD)'

test-scala:
ifeq ($(NOSCALA), true)
	@echo 'Skipping scala tests...'
else
	@echo 'Running scala tests...'
	@docker run -it --rm \
		-v `pwd`/kernel-scala:/src \
		cloudet/sbt-sparkkernel-image:1.5.1 bash -c 'cp -r /src /tmp/src && \
			cd /tmp/src && \
			sbt test'
endif

testdev: | $(URTH_COMP_LINKS)
	@npm run test -- -p

install: CMD?=exit
install: SERVER_NAME?=urth_widgets_install_validation
install: OPTIONS?=-it --rm
install: _run-$(PYTHON)

server: CMD?=ipython notebook --no-browser --port 8888 --ip="*"
server: SERVER_NAME?=urth_widgets_server
server: OPTIONS?=-it --rm
server: PORT_MAP?=-p 9500:8888
server: VOL_MAP?=-v `pwd`/etc/notebooks:/home/jovyan/work
server: _run-$(PYTHON)

_run-python3: _run

_run-python2: SETUP_CMD=source activate python2; pip install futures==3.0.3;
_run-python2: _run

_run:
	@echo 'Running container named $(SERVER_NAME) in $(PYTHON)'
	@docker run $(OPTIONS) --name $(SERVER_NAME) \
		$(PORT_MAP) \
		-e USE_HTTP=1 \
		-v `pwd`:/src \
		$(VOL_MAP) \
		$(REPO) bash -c '$(SETUP_CMD) \
			pip install --no-binary ::all: $$(ls -1 /src/dist/*.tar.gz | tail -n 1) && \
			jupyter declarativewidgets install --user && \
			jupyter declarativewidgets activate && \
			$(CMD)'

dev: CMD?=sh -c "python --version; ipython notebook --no-browser --port 8888 --ip='*'"
dev: .watch dist
	-@CMD='$(CMD)' $(MAKE) _dev-$(PYTHON)
	@$(MAKE) clean-watch

_dev-python2: EXTENSION_DIR=/opt/conda/envs/python2/lib/python2.7/site-packages/urth
_dev-python2: SETUP_CMD=source activate python2; pip install futures==3.0.3;
_dev-python2: _dev

_dev-python3: EXTENSION_DIR=/opt/conda/lib/python3.4/site-packages/urth
_dev-python3: _dev

_dev: NB_HOME?=/root
_dev:
	@docker run -it --rm \
		-p 8888:8888 \
		-e JVM_OPT=-Dlog4j.logLevel=trace \
		-v `pwd`/dist/urth/widgets/ext/notebook:$(NB_HOME)/.local/share/jupyter/nbextensions/urth_widgets \
		-v `pwd`/dist/urth:$(EXTENSION_DIR) \
		-v `pwd`/etc:$(NB_HOME)/nbconfig \
		-v `pwd`/etc/notebook.json:$(NB_HOME)/.jupyter/nbconfig/notebook.json \
		-v `pwd`/etc/jupyter_notebook_config.py:$(NB_HOME)/.jupyter/jupyter_notebook_config.py \
		-v `pwd`/etc/notebooks:/home/jovyan/work \
		$(REPO) bash -c '$(SETUP_CMD) $(CMD)'

start-selenium:
	@echo "Installing and starting Selenium Server..."
	@node_modules/selenium-standalone/bin/selenium-standalone install
	@node_modules/selenium-standalone/bin/selenium-standalone start & echo $$! > SELENIUM_PID

run-test: SERVER_NAME?=urth_widgets_integration_test_server
run-test: BROWSER_LIST?=chrome
run-test:
	-@docker rm -f $(SERVER_NAME)
	@OPTIONS=-d SERVER_NAME=$(SERVER_NAME) $(MAKE) server
	@echo 'Waiting for server to start...'
	@LIMIT=60; while [ $$LIMIT -gt 0 ] && ! docker logs $(SERVER_NAME) 2>&1 | grep 'Notebook is running'; do echo waiting $$LIMIT...; sleep 1; LIMIT=$$(expr $$LIMIT - 1); done
	@$(foreach browser, $(BROWSER_LIST), echo 'Running system integration tests on $(subst +, ,$(browser))...'; npm run system-test -- --baseurl $(BASEURL) --test-type $(TEST_TYPE) --browser "$(subst +, ,$(browser))" --platform "Windows 10";)

system-test: BASEURL?=http://192.168.99.100:9500
system-test: SERVER_NAME?=urth_widgets_integration_test_server
system-test: BROWSER_LIST?=chrome
system-test:
ifdef SAUCE_USER_NAME
	@echo 'Running system tests on Sauce Labs...'
	BASEURL=$(BASEURL) BROWSER_LIST="$(BROWSER_LIST)" TEST_TYPE=remote $(MAKE) run-test
else
	$(MAKE) start-selenium
	$(MAKE) sdist
	@echo 'Starting system integration tests locally...'
	BASEURL=$(BASEURL) BROWSER_LIST="$(BROWSER_LIST)" TEST_TYPE=local $(MAKE) run-test || (docker rm -f $(SERVER_NAME); -kill `cat SELENIUM_PID`; rm SELENIUM_PID; exit 1)
	-@kill `cat SELENIUM_PID`
	-@rm SELENIUM_PID
endif
	@echo 'System integration tests complete.'
	-@docker rm -f $(SERVER_NAME)

docs: DOC_PORT?=4001
docs: BASEURL?=http://127.0.0.1
docs: .watch-docs dist/docs
	@echo "Serving docs at $(BASEURL):$(DOC_PORT)"
	@bash -c "trap 'make clean-watch-docs' INT TERM ; npm run http-server -- dist/docs/site -p $(DOC_PORT)"

all: BASEURL?=http://192.168.99.100:9500
all: init
	$(MAKE) test-js-remote
	$(MAKE) test-py
	PYTHON=python2 $(MAKE) test-py
	$(MAKE) test-scala
	$(MAKE) sdist
	$(MAKE) install
	PYTHON=python2 $(MAKE) install
	@BASEURL=$(BASEURL) BROWSER_LIST="$(BROWSER_LIST)" $(MAKE) system-test
	@BASEURL=$(BASEURL) BROWSER_LIST="$(BROWSER_LIST)" PYTHON=python2 $(MAKE) system-test
	$(MAKE) dist/docs

release: EXTRA_OPTIONS=-e PYPI_USER=$(PYPI_USER) -e PYPI_PASSWORD=$(PYPI_PASSWORD)
release: SETUP_CMD=echo "[server-login]" > ~/.pypirc; echo "username:" ${PYPI_USER} >> ~/.pypirc; echo "password:" ${PYPI_PASSWORD} >> ~/.pypirc;
release: POST_SDIST=register upload
release: sdist
