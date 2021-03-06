#!/usr/bin/ruby -w

require 'optparse'

options = {:dryrun => ''}
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: psql_init.rb [options] ..."
  
  opts.on( '-d', '--database DATABASE', 'name of the CiGri database' ) do |database|
    options[:database] = database
  end
  
  opts.on( '-n', '--dryrun', 'prints all the commands but does not execute them' ) do
    options[:dryrun] = 'echo '
  end
  
    opts.on( '-p', '--password PASSWORD', 'password for user with full rights on the CiGri database' ) do |password|
    options[:password] = password
  end
  
  opts.on( '-s', '--sql_file SQLFILE', String, 'SQL file to initialize the cigri database' ) do |sql|
    options[:sql] = sql
  end
  
  opts.on( '-t', '--type TYPE (psql)', ['psql'], 'Type of the database (psql)' ) do |type|
    options[:type] = type
  end
  
  opts.on( '-u', '--user USER', 'login for user with full rights on the CiGri database' ) do |user|
    options[:user] = user
  end
  
  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end
end

begin
  optparse.parse!(ARGV)
rescue OptionParser::ParseError => e
  STDERR.puts e
  STDERR.puts "\n" + optparse.to_s
  exit 1
end



default = {:database => 'cigri',:user => 'cigri', :password => 'cigri',
           :sql => "./psql_structure.sql", :type => 'psql'}
questions = {
  :database => "Enter the name for the cigri database (default: #{default[:database]}): ",
  :user     => "Enter the username of the cigri user (default: #{default[:user]}): ",
  :password => "Enter the password of the cigri user (default: #{default[:password]}): ",
  :sql      => "Enter the SQL file to initialize the tables (default: #{default[:sql]}: )",
  :type     => "Enter the type of database you want to use (default: #{default[:type]}: )"
}

#force order using a list
[:type, :database, :user, :password, :sql].each do |field|
  unless options[field]
    begin
      continue = false
      print questions[field]
      input = gets.chomp
      #white spaces are not permitted
      if input =~ /\s+/
        continue = true
        puts 'Spaces are not allowed, try again.'
        next
      end
      options[field] = input.empty? ? default[field] : input
    end while continue
    puts "Using: \'#{options[field]}\'"
  end
end

if options[:type].eql?('psql')
  BASE_CMD = "#{options[:dryrun]}sudo -u postgres psql -q -c "

  puts 'Executing commands:'
  system("#{BASE_CMD} \"CREATE ROLE #{options[:user]} LOGIN PASSWORD \'#{options[:password]}\'\"")
  system("#{BASE_CMD} \"CREATE DATABASE #{options[:database]} OWNER #{options[:user]} ENCODING 'UTF8' TEMPLATE template0\"")
  cmd = "#{options[:dryrun]}sudo -u postgres psql -q -d #{options[:database]} -f #{options[:sql]}"
  system(cmd)
  abort "[ERROR] Unable to execute: #{cmd}" unless $?.success?
  # The following is a trick to grant privileges on every table of the database
  cmd = "sudo -u postgres psql -qAt -c \"select 'grant select, insert, update, delete on ' || tablename || ' to #{options[:user]};' from pg_tables where schemaname = 'public'\" #{options[:database]} | sudo -u postgres psql #{options[:database]}"
  if options[:dryrun].length > 0
    puts cmd
  else
    system(cmd)
    abort "[ERROR] Unable to execute: #{cmd}" unless $?.success?
  end
  # The following is a trick to grant privileges on every sequence of the database
  cmd = "sudo -u postgres psql -qAt -c \"select 'grant select, update on ' || relname || ' to #{options[:user]};' from pg_class where relkind = 'S'\" #{options[:database]} | sudo -u postgres psql #{options[:database]}"
  if options[:dryrun].length > 0
    puts cmd
  else
    system(cmd)
    abort "[ERROR] Unable to execute: #{cmd}" unless $?.success?
  end
else
  abort "[ERROR] database type should be one of {psql})"
end

puts "\nTERMINTATED SUCCESSFULLY"
