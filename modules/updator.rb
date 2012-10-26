#!/usr/bin/ruby -w

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'cigri'
require 'cigri-joblib'
require 'cigri-colombolib'
require 'cigri-clusterlib'
require 'cigri-iolib'

$0='cigri: updator'

def notify_judas
  Process.kill("USR1",Process.ppid)
end

begin
  config = Cigri.conf
  logger = Cigri::Logger.new('UPDATOR', config.get('LOG_FILE'))
 
  GRID_USAGE_UPDATE_PERIOD=config.get('GRID_USAGE_UPDATE_PERIOD',60)
 
  %w{INT TERM}.each do |signal|
    Signal.trap(signal){ 
      #cleanup!
      logger.warn('Interruption caught: exiting.')
      exit(1)
    }
  end
  
  logger.debug('Starting')

  ## 
  # Check for finished campaigns
  ## 
  campaigns=Cigri::Campaignset.new
  campaigns.get_running
  campaigns.each do |campaign|
    logger.debug("campaign #{campaign.id} has remaining tasks") if campaign.has_remaining_tasks?
    logger.debug("campaign #{campaign.id} has to_launch jobs") if campaign.has_to_launch_jobs?
    logger.debug("campaign #{campaign.id} has launching jobs") if campaign.has_launching_jobs?
    logger.debug("campaign #{campaign.id} has active jobs") if campaign.has_active_jobs?
    logger.info("campaign #{campaign.id} has open events") if campaign.has_open_events?
    if campaign.finished?
      campaign.update({'state' => 'terminated'})
      logger.info("Campaign #{campaign.id} is finished")
      Cigri::Event.new(:class => 'notify', :state => 'closed', :campaign_id => campaign.id,
                       :code => "FINISHED_CAMPAIGN", :message => "Campaign is finished")
      notify_judas
    end
  end 

  ## 
  # Autofix clusters
  ## 
  events=Cigri::Eventset.new({:where => "state='open' and class='cluster'"})
  Cigri::Colombo.new(events).autofix_clusters

  ## 
  # Check for blacklists
  ## 
  events=Cigri::Eventset.new({:where => "state='open' and code='BLACKLIST'"})
  Cigri::Colombo.new(events).check_blacklists

  ## 
  # Check jobs to resubmit
  ## 
  events=Cigri::Eventset.new({:where => "state='open' and code='RESUBMIT' and class='job'"})
  Cigri::Colombo.new(events).check_jobs

  ## 
  # Update grid_usage table
  ## 
  last_grid_usage_entry_date=0
  db_connect do |dbh|
    last_grid_usage_entry_date=last_grid_usage_entry_date(dbh)
  end
  if Time.now.to_i - last_grid_usage_entry_date.to_i > GRID_USAGE_UPDATE_PERIOD
   logger.debug("updating grid_usage")
    begin
      cigri_jobs=Cigri::Jobset.new
      cigri_jobs.get_running
      cigri_jobs.records.map! {|j| j.props[:remote_id].to_i }        
      date=Time.now
      Cigri::ClusterSet.new.each do |cluster|
        # Get the resource_units
        cluster_resources=cluster.get_resources
        cigri_resources=0
        unavailable_resources=[]
        resource_units={}
        cluster_resources.each do |r|
          resource_units[r["id"]]=r[cluster.props[:resource_unit]]
          unavailable_resources << r[cluster.props[:resource_unit]] if r["state"] != "Alive"
                                                   #TODO: manage standby resources
        end
        max_resource_units=resource_units.values.uniq.length 
  
        # Get the cluster jobs
        cluster_jobs=cluster.get_jobs
        # Jobs consume resources units
        cluster_jobs.each do |cluster_job|
          cluster_job["resources"].each do |job_resource|
            count=resource_units.length
            resource_units.delete_if {|k,v| v==resource_units[job_resource["id"]] }
            if cigri_jobs.records.include?(cluster_job["id"].to_i )
              cigri_resources+=count-resource_units.length
            end
          end
        end
  
        # Create the entry
        Datarecord.new("grid_usage",{:date => date,
                                   :cluster_id => cluster.id,
                                   :max_resources => max_resource_units,
                                   :used_resources => max_resource_units - resource_units.values.uniq.length,
                                   :used_by_cigri => cigri_resources,
                                   :unavailable_resources => unavailable_resources.uniq.length
                                  })
      end 
    rescue => e
      logger.warn("Could not update the grid_usage table! #{e.message} #{e.backtrace}") 
    end
  end
  
  logger.debug('Exiting')
end
