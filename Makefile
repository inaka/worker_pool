RUN := erl -pa ebin -pa deps/*/ebin -smp enable -s lager -boot start_sasl ${ERL_ARGS}

all:
	rebar get-deps && rebar compile

erl:
	rebar skip_deps=true compile

clean:
	rebar clean

clean_logs:
	rm -rf log*

build_plt: erl
	dialyzer --verbose --build_plt --apps kernel stdlib erts compiler hipe crypto \
		edoc gs syntax_tools --output_plt ~/.wpool.plt -pa deps/*/ebin ebin

analyze: erl
	dialyzer --verbose -pa deps/*/ebin --plt ~/.wpool.plt -Werror_handling ebin

xref: all
	rebar skip_deps=true --verbose xref

shell: erl
	if [ -n "${NODE}" ]; then ${RUN} -name ${NODE}@`hostname`; \
	else ${RUN}; \
	fi

run: erl
	if [ -n "${NODE}" ]; then ${RUN} -name ${NODE}@`hostname` -s wpool; \
	else ${RUN} -s wpool; \
	fi

test: erl
	mkdir -p log/ct
	rebar skip_deps=true ct --verbose 3
	open log/ct/index.html

doc: erl
	rebar skip_deps=true doc