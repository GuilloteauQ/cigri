.. -*- rst-mode -*-

Modules Description
===================

Cigri is divided in several independent modules. Each module has a
specific unique role. This section depicts the roles of the different
modules.

Columbo
-------

This modules investigates problems.
It takes decisions depending on the *events*. 

It can:

- Detect infinite resubmissions
- Blacklist a cluster
- Resubmit a best-effort killed job (ie put a job back into the
  *bag_of_tasks* table)
- Send notifications to users
- ...

Monitoring
----------

Updates the database with new info


Spritz
------

Sptitz (reference to David Spritz, the weather man) computes metrics
on jobs such as average duration, throughput, ... With these values it
is able to give a forecast of what should happen in the future.

Metascheduler
-------------

The meta-scheduler is in charge of sharing the resources between the
different campaigns. 

Scheduler
---------

Once resources have been shared by the meta-scheduler, the scheduler
will decide how to execute the campaigns (temporal/dimensional
grouping) and add the jobs to the *job_to_launch* table with the
proper options.

Runner
------

This module is dedicated to launching jobs on the clusters. It reads
the jobs to launch from the database table *jobs_to_launch* and
submits them to the API lib.
It runs asynchronously, forked as one daemon for each cluster. Each runner waits for jobs and submit to the cluster it is responsible of. It submits the jobs as fast as it can but waits as soon as there's a waiting job. So, it has to check for the status of it's own jobs. An optimization algorithm tries to submit several jobs at a time (as oar array jobs) if the cluster "eats" the jobs quick enough.
The scheduler may have to pass some informations to the runner. So, there's a "runner_options" field that is a json hash read by the runner as options values. For example, the { type : "besteffort" } option may be passed to tell to the runner that the jobs must be ran as best-effort.
Jobs may also be tagged by the scheduler. For example, all the jobs having the same tag are groupped by the runner when the { grouping: "temporal" } option is passed.

Nikita
------

Deletes jobs that should be killed 

Almighty
--------

Almighty is the central component of Cigri. It is a coordinator as it
chooses what other module to launch. 

Modules are launched in this order:

#. module 1
#. module 2 

Collector
---------

Gathers data in a specific location.

JDL_parser
----------

The JDL parser module is used to parse and save when a new campaign is
submitted.

.. Local Variables:
.. ispell-local-dictionary: "american"
.. mode: flyspell
.. End:
