#!/usr/bin/ruby -w

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'cigri'
require 'cigri-notificationlib'
require 'cigri-conflib'
require 'cigri-joblib'
require 'cigri-colombolib'

config = Cigri.conf
logger = Cigri::Logger.new("JUDAS #{ARGV[0]}", config.get('LOG_FILE'))

$0 = "cigri: judas #{ARGV[0]}"

begin
  require 'net/smtp'
  SMTPLIB||=true
rescue LoadError
  SMTPLIB||=false
  logger.warn("Net/smtp lib not found: mail notifications will be disabled!")
end
begin
  require 'xmpp4r/client'
  XMPPLIB||=true
rescue LoadError
  XMPPLIB||=false
  logger.warn("Xmpp4r lib not found: xmpp notifications will be disabled!")
end
IRCLIB=false

# Signal traping
%w{INT TERM}.each do |signal|
  Signal.trap(signal){ 
    #cleanup!
    STDERR.puts('Interruption caught: exiting.')
    exit(1)
  }
end

logger.info("Starting judas (notification module)")

# Connexion handlers
im_handlers={}
if XMPPLIB
  # Xmpp connexion
  if config.exists?("NOTIFICATIONS_XMPP_SERVER")
    def xmpp_connect(client,config,logger)
      return true if client.is_connected?
      client.connect(config.get("NOTIFICATIONS_XMPP_SERVER"),config.get("NOTIFICATIONS_XMPP_PORT",5222).to_i)
      client.auth(config.get("NOTIFICATIONS_XMPP_PASSWORD"))
      client.send(Jabber::Presence.new.set_show(:dnd).set_status('I am the new grid!'))
      # add the callback to respond to server ping
      client.add_iq_callback do |iq_received|
        if iq_received.type == :get
          if iq_received.queryns.to_s != 'http://jabber.org/protocol/disco#info'
            iq = Jabber::Iq.new(:result, client.jid.node)
            iq.id = iq_received.id
            iq.from = iq_received.to
            iq.to = iq_received.from
            client.send(iq)
          end
        end
      end
      client.on_exception do |e|
        logger.warn("XMPP disconnected (#{e.message}). Trying to re-connect")
        sleep 3
        client.close
        sleep 2
        xmpp_connect(client,config,logger)
      end
    end
    jid = Jabber::JID.new(config.get("NOTIFICATIONS_XMPP_IDENTITY"))
    im_handlers[:xmpp] = Jabber::Client.new(jid)
    begin
      xmpp_connect(im_handlers[:xmpp],config,logger)
    rescue => e
      logger.error("Could not connect to XMPP server, notifications disabled: #{e.inspect}\n#{e.backtrace}")
      im_handlers[:xmpp]=nil
    end
  end
end
if IRCLIB
  # Irc connexion goes here
end

# Notify function
def notify(im_handlers)
  # Notify all open events (excepted internals)
  events=Cigri::Eventset.new(:where => "state='open' and notified=false and code !='RESUBMIT'
                                                                        and code !='RESUBMIT_END'
                                       ")
  Cigri::Colombo.new(events).notify(im_handlers)

  # Notify events of the class notify (events created closed, just for notification)
  events=Cigri::Eventset.new(:where => "class='notify' and notified=false")
  Cigri::Colombo.new(events).notify(im_handlers)

  # Notify events of the class log (events created closed, just for logging and admin notification)
  events=Cigri::Eventset.new(:where => "class='log' and notified=false and code != 'QUEUED_FOR_TOO_LONG'")
  Cigri::Colombo.new(events).notify(im_handlers)
end

# Setting up trap on USR1
notify_flag=false
trap("USR1") {
  STDERR.puts("Received USR1, so checking notifications")
  notify_flag=true
}

# Main loop
logger.info("Ready")
while true do
  if notify_flag==true
    notify(im_handlers)
    notify_flag=false
  end
  sleep 10
end
