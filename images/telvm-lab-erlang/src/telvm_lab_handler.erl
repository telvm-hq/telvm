-module(telvm_lab_handler).

-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State) ->
    Body = <<"{\"status\":\"ok\",\"service\":\"telvm-lab\",\"probe\":\"/\"}">>,
    Req = cowboy_req:reply(
        200,
        #{<<"content-type">> => <<"application/json">>},
        Body,
        Req0
    ),
    {ok, Req, State}.
