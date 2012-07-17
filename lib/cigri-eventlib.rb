#!/usr/bin/ruby -w
#
# This library contains the classes relative to Events
# It may be considered as an extension to the iolib, as
# it still makes SQL queries, but more in a "meta" way
#

require 'cigri-logger'
require 'cigri-conflib'
require 'cigri-iolib'

CONF = Cigri.conf unless defined? CONF
EVENTLOGGER = Cigri::Logger.new('EVENTLIB', CONF.get('LOG_FILE'))

module Cigri

  # Event class
  # An event instance can be get from the database or newly created
  # See Datarecord class for more doc
  class Event < Datarecord
    attr_reader :props

    # Creates a new event or get it from the database
    def initialize(props={})
      if props
        if props[:state].nil?
          props[:state]="open"
        end
        if props[:checked].nil?
          props[:checked]="no"
        end
        props[:date_open]=Time::now()
        msg=""
        props.each_key do |prop| 
          msg += "#{prop}=\"#{props[prop]}\" "
        end
        EVENTLOGGER.debug("New event:" + msg) unless props[:nodb]    
      end
      super("events",props)
    end

    # Close the event
    def close
      update({:date_closed => Time::now(), :state => 'closed'})    
    end

    # Mark the event as checked (check='yes')
    # An event maybe checked by colombo, but still open, for example
    # when colombo generates another event depending on this one
    def checked
      update({:checked => 'yes'}) 
    end

  end # class Event

  # Eventset class
  # For sets of events
  class Eventset < Dataset

    # Creates the new Eventset
    def initialize(props={})
      super("events",props)
      to_events
    end

    # Alias to the dataset records
    def events
      @records
    end

    def to_events
      events=[]
      @records.each do |record|
        props = record.props
        props[:nodb] = true
        event = Event.new(props)
        events << event
      end
      @records = events
    end

  end # Class Eventset


end # module Cigri
