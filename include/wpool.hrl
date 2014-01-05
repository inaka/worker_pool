
-record(wpool, {name     :: wpool:name(),
                size     :: pos_integer(),
                next     :: pos_integer(),
                opts     :: [wpool:option()],
                qmanager :: atom()}).
