-module(telvm_lab_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    Dispatch = cowboy_router:compile([
        {'_', [{"/", telvm_lab_handler, []}]}
    ]),
    {ok, _} = cowboy:start_clear(
        telvm_http_listener,
        [
            {port, 3333},
            {ip, {0, 0, 0, 0}}
        ],
        #{env => #{dispatch => Dispatch}}
    ),
    telvm_lab_sup:start_link().

stop(_State) ->
    ok.
