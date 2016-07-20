-record(wpool, { name                  :: wpool:name()
               , size                  :: pos_integer()
               , next                  :: pos_integer()
               , opts                  :: [wpool:option()]
               , qmanager              :: wpool_queue_manager:queue_mgr()
               , born = os:timestamp() :: erlang:timestamp()
               }).
