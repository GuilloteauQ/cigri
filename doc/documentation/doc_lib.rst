.. -*- rst-mode -*-

Libraries Description
=====================

Different libraries may be used by Cigri components. 

conflib
-------
Library handling the configuration file and variables. The configuration file is a bash-style VAR=VALUE collection of lines. This library offers a way to open a given or default configuration file and rapid access to the variables. 

iolib
-----

Library handling all interactions with the Cigri database. It
provides a connection method that gives a database handle, and many
useful queries.

clusterlib
----------

Generic library handling communications with the batch schedulers. By
default, it communicates with the OAR 2.5 API, but it should be able
to communicate with other APIs as well.

Methods offered by this library include the querying of the batch
scheduler to obtain info about resources and jobs. The library also
provides methods to submit jobs to the batchs.

apilib
------

Library handling the Cigri API that serves REST queries.

.. Local Variables:
.. ispell-local-dictionary: "american"
.. mode: flyspell
.. End:
