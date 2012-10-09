#!/usr/bin/ruby -w

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'cigri'
require 'cigri-joblib'
require 'cigri-colombolib'
require 'cigri-notificationlib'
begin
  require 'xmpp4r/client'
  XMPPLIB=true
rescue LoadError
  XMPPLIB=false
end

$0='cigri: updator'

begin
  config = Cigri.conf
  logger = Cigri::Logger.new('UPDATOR', config.get('LOG_FILE'))
  
  %w{INT TERM}.each do |signal|
    Signal.trap(signal){ 
      #cleanup!
      logger.warn('Interruption caught: exiting.')
      exit(1)
    }
  end
  
  logger.debug('Starting')

  # Check for finished campaigns
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
    end
  end 

  # Autofix clusters
  events=Cigri::Eventset.new({:where => "state='open' and class='cluster'"})
  Cigri::Colombo.new(events).autofix_clusters

  # Check for blacklists
  events=Cigri::Eventset.new({:where => "state='open' and code='BLACKLIST'"})
  Cigri::Colombo.new(events).check_blacklists

  # Check jobs to resubmit
  events=Cigri::Eventset.new({:where => "state='open' and code='RESUBMIT' and class='job'"})
  Cigri::Colombo.new(events).check_jobs

  # Send notifications
  # !! This piece of code is just for testing. !!
  # !! It should go into a notification module that runs asynchronously !!
  # and get a signal to send notifications.
  # TODO: check events that are not yet notified and aggregate if necessary before sending message(s)
  im_handlers={}
  if XMPPLIB 
    jid = Jabber::JID.new(config.get("NOTIFICATIONS_XMPP_IDENTITY"))
    im_handlers[:xmpp] = Jabber::Client.new(jid)
    im_handlers[:xmpp].connect(config.get("NOTIFICATIONS_XMPP_SERVER"),config.get("NOTIFICATIONS_XMPP_PORT"))
    im_handlers[:xmpp].auth(config.get("NOTIFICATIONS_XMPP_PASSWORD"))
  end
  message=Cigri::Message.new({:admin => true, :user => "kameleon", :message => "Test message!"},im_handlers)
  message.send
 
  logger.debug('Exiting')
end
