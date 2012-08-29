% This file is licensed to you under the Apache License,
% Version 2.0 (the "License"); you may not use this file
% except in compliance with the License.  You may obtain
% a copy of the License at
%
% http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing,
% software distributed under the License is distributed on an
% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
% KIND, either express or implied.  See the License for the
% specific language governing permissions and limitations
% under the License.

%% @hidden
-module(wpool_SUITE).

-type config() :: [{atom(), term()}].

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).

-spec all() -> [atom()].
all() -> [].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
	wpool:start(),
	Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
	wpool:stop(),
	Config.