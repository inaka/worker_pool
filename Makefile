RUN := erl -pa ebin -pa deps/*/ebin -smp enable -s lager -boot start_sasl ${ERL_ARGS}
HOST := `hostname`
REBAR ?= './rebar'

all:
	${REBAR} get-deps && ${REBAR} compile

erl:
	${REBAR} skip_deps=true compile

clean:
	${REBAR} clean

clean_logs:
	rm -rf log*

build_plt: erl
	dialyzer --verbose --build_plt --apps kernel stdlib erts compiler hipe crypto \
		edoc gs syntax_tools --output_plt ~/.wpool.plt -pa deps/*/ebin ebin

analyze: erl
	dialyzer --verbose -pa deps/*/ebin --plt ~/.wpool.plt -Werror_handling ebin

xref: all
	${REBAR} skip_deps=true --verbose xref

shell: erl
	if [ -n "${NODE}" ]; then ${RUN} -name ${NODE}@${HOST}; \
	else ${RUN}; \
	fi

run: erl
	if [ -n "${NODE}" ]; then ${RUN} -name ${NODE}@${HOST} -s wpool; \
	else ${RUN} -s wpool; \
	fi

test: erl
	mkdir -p log/ct
	${REBAR} skip_deps=true ct --verbose 3
	open log/ct/index.html

doc: erl
	${REBAR} skip_deps=true doc

erldocs: erl
	erldocs . -o doc/
