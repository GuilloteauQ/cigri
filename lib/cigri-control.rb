require 'cigri-clusterlib'
require 'json'

class Controller
  def initialize(logfile, cluster, config_file, min_cycle_duration)
    config_data = JSON.parse(File.read(config_file))
    @nb_jobs = config_data["nb_jobs"].nil? ? 0 : config_data["nb_jobs"].to_i
    @reference_load = config_data["reference_load"].nil? ? 3 : config_data["reference_load"].to_i
    @previous_error = 0
    @error = 0
    @logfile = logfile # TODO: May need to create the file if does not exist
    @cluster = cluster
    @kp = 0.1
    @rmax = 100
    @alpha = 1.0 / @rmax
    @h = min_cycle_duration # seconds
    @max_load = 8.0
  end

  def update_controlled_value()
    @nb_jobs = bound_nb_jobs(@nb_jobs + @kp * @error / @alpha)
  end

  def get_fileserver_load()
    loadavg_per_sensor = []
    Dir.glob("/tmp/loadavg_storage_server[0-9]").sort().each_with_index do |f, i|
      l =  `tail -n 1 #{f}`.split()
      loadavg_per_sensor[i] = {:date => l[0], :mn1 => l[1].to_f, :mn5 => l[2].to_f, :mn15 => l[3].to_f}
    end
    loadavg_per_sensor[0][:mn1]
  end

  def update_errors()
    @previous_error = @error
    @error = (@reference_load - self.get_fileserver_load()) / @max_load
  end

  def log()
    file = File.open(@logfile, "a+")
    file << "#{Time.now.to_i}, #{@nb_jobs}, #{self.get_waiting_jobs()}, #{self.get_running_jobs()}, #{self.get_fileserver_load}\n"
    file.close
  end

  def get_running_jobs()
    cluster_jobs = @cluster.get_jobs()
    nb_running_jobs = cluster_jobs.select{|j| j["state"] == "Running" or j["state"] == "Finishing" or j["state"] == "Launching"}.length
    nb_running_jobs
  end

  def get_waiting_jobs()
    cluster_jobs = @cluster.get_jobs()
    nb_waiting_jobs = cluster_jobs.select{|j| j["state"] == "Waiting"}.length
    nb_waiting_jobs
  end

  def get_cluster_load()
	@cluster.get_global_stress_factor
  end

  def get_error()
	@error
  end

  def get_nb_jobs()
	@nb_jobs
  end

  def get_percentage()
	@percentage
  end

end

def p_controller(error, k)
  k * error
end

def pd_controller(error, previous_error, kp, kd)
  kp * error + kd  * (error - previous_error)
end

def min(x, y)
  if x < y
    x
  else
    y
  end
end


def get_rates_for_campaigns(campaigns, campaign_heaviness, rate, percentage)
  # Will contain the mapping campaign_id -> rate
  rates = {}

  if campaigns.length == 1
    rates[campaigns[0]] = (percentage.to_i * rate / 100).to_i
  elsif campaigns.length > 1
    campaign_id0 = campaigns[0]
    campaign_id1 = campaigns[1]
    # we need to determine which campaign is heavy
    if campaign_heaviness[campaign_id0] and not campaign_heaviness[campaign_id1]
      campaign_id_heavy = campaign_id0
      campaign_id_light = campaign_id1
    else
      campaign_id_heavy = campaign_id1
      campaign_id_light = campaign_id0
    end
    # TODO else elsif if both heavy or both light
    rates[campaign_id_heavy] = (percentage.to_i * rate / 100).to_i
    rates[campaign_id_light] = rate - rates[campaign_id_heavy]
  end
  return rates
end

def bound_nb_jobs(nb_jobs)
  if nb_jobs < 0
    return 0
  end
  return nb_jobs
end

def bound_percentage(percentage)
  if percentage > 100
    return 100
  end
  if percentage < 0
    return 0
  end
  return percentage
end
