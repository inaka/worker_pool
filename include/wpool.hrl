
-type queue_mgr() :: atom().

-record(wpool, {name     :: wpool:name(),
                size     :: pos_integer(),
                next     :: pos_integer(),
                opts     :: [wpool:option()],
                qmanager :: queue_mgr()
               }).
