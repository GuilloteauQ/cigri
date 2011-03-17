#!/usr/bin/env ruby
require 'cigri_jdl_parser'

abort ("Usage: #{__FILE__} JDL_FILE") unless ARGV.length == 1

filename = ARGV[0]

abort ("JDL file \"#{filename}\" not readable. Aborting") unless File.readable?(filename)


p Cigri::JDLParser.parse(File.read(filename))

