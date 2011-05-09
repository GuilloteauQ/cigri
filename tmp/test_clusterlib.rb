#!/usr/bin/ruby -w

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__),'../', 'lib'))
$LOAD_PATH.unshift("#{ENV["CIGRIDIR"]}/lib")

require 'cigri'
require 'cigri-clusterlib'

cluster=Cigri::Cluster.new(:name => "fukushima")
cluster.submit_job(:command => "sleep 300")
cluster.get_resources.each do |resource|
  puts resource['id'].to_s+" ("+resource['network_address']+" on "+resource['cluster']+")"
#  resource.jobs.each do |job|
#    puts "  job: "+job['id'].to_s
#  end
end
