#!/usr/bin/ruby -w

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'cigri'
require 'cigri-clusterlib'
require 'cigri-joblib'

begin
  config = Cigri.conf
  logger = Cigri::Logger.new("RUNNER #{ARGV[0]}", config.get('LOG_FILE'))

  if ARGV[0].nil?
    raise Cigri::Error, "runner should be passed the name of a cluster as an argument"
  else
    cluster=Cigri::Cluster.new(:name => ARGV[0])
  end

  $0="cigri: runner #{ARGV[0]}"

  # Signal traping
  %w{INT TERM}.each do |signal|
    Signal.trap(signal){ 
      #cleanup!
      logger.warn('Interruption caught: exiting.')
      exit(1)
    }
  end
  

  # Default configuration
  if config.exists?('RUNNER_DEFAULT_INITIAL_NUMBER_OF_JOBS') 
    n=config.get('RUNNER_DEFAULT_INITIAL_NUMBER_OF_JOBS').to_i
  else
    n=5
  end
  if config.exists?('RUNNER_MIN_CYCLE_DURATION')
    MIN_CYCLE_DURATION=config.get('RUNNER_MIN_CYCLE_DURATION').to_i
  else
    MIN_CYCLE_DURATION=5
  end
  SLEEP_MORE=10 #used as a sleep value when no job is submitted
 

  #Main runner loop
  logger.info("Starting runner on #{ARGV[0]}")
  N=n
  while true do
    logger.debug('New iteration')

    time=Time::now.to_i
    sleep_more=0

    ##########################################################################
    # Jobs control
    ##########################################################################
    # 
    # Reset the tap
    # The "n" variable is like a tap. It represents the number of jobs
    # we can start at a time (as a oar array job)
    # We close the tap (ie set n to 0) if the cluster is not running
    # our jobs, and we open it if all the jobs are running or terminated
    n=N
    #
    # Update the jobs state and close the tap if necessary
    current_jobs=Cigri::Jobset.new
    current_jobs.get_submitted(cluster.id)
    current_jobs.get_running(cluster.id)
    current_jobs.each do |job|
      if job.props[:remote_id].nil? || job.props[:remote_id] == ""
        #TODO: Create an event here: the job is lost, it has no remote_id
        job.update({'state' => 'event'})
        logger.error("Job #{job.id} is lost, it has no remote_id!") 
      else
        begin
          cluster_job=cluster.get_job(job.props[:remote_id].to_i,job.props[:grid_user])
          case cluster_job["state"] 
            when "Terminated"
              job.update({'state' => 'terminated'})
            when "Error"
              job.update({'state' => 'event'})
            when "Running"
              job.update({'state' => 'running'})
            when "Finishing"
              job.update({'state' => 'running'})
            when "Waiting"
              job.update({'state' => 'remote_waiting'})
              # close the tap
              n=0
            else
              # close the tap
              n=0
          end
        rescue => e
          #TODO: event: could not get the remote job
          logger.error("Could not get remote job #{job.id}! #{e.inspect}") 
        end
      end
    end 

    ##########################################################################
    # Jobs submission
    ##########################################################################
    #
    # Get the jobs to launch and submit them
    # 
    tolaunch_jobs=Cigri::JobtolaunchSet.new
    if tolaunch_jobs.get_next(cluster.id,n) > 0 # if the tap is open
      logger.info("Got #{tolaunch_jobs.length} jobs to launch")
      # Take the jobs from the b-o-t
      jobs = tolaunch_jobs.take
      # Submit the new jobs
      begin
        jobs.submit(cluster.id)        
      rescue => e
        # TODO: Event!
        logger.warn("Could not submit jobs on #{cluster.name}: #{e.inspect}")
      end
    else
      sleep_more = SLEEP_MORE
    end

    # Sleep if necessary
    cycle_duration=Time::now.to_i - time
    sleep MIN_CYCLE_DURATION-cycle_duration if cycle_duration < MIN_CYCLE_DURATION
    sleep sleep_more
  end
end
