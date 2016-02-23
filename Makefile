all: install_rebar3 ck build ct

install_rebar3:
	@./config/install_rebar3.sh

build:
	@./config/build.sh

ck: dialyzer edoc

cu: clean_upgrade

clean_upgrade: remove_appup upgrade

remove_appup:
	@rm -f ebin/*.appup

upgrade:
	@#bash -x
	@./config/hcu.sh

run:
	@./config/run.sh

reset:
	@git fetch --all
	@git reset --hard origin/master

ct:
	@./config/rebar3 do ct -c, cover
	@rm -f test/*.beam
	@./config/test_coverage.sh

ct_analyze:
	@./config/show_ct_errors.sh

dialyzer:
	@./config/rebar3 dialyzer

edoc:
	@./config/gen_edoc.sh