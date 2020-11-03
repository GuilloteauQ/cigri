require 'cigri-clusterlib'
require 'json'

class Controller
  # We try to give a generic API for the controller
  # Here parameters contains most likely a list of all the parameters to use
  # in the case of a PI controller is will contain two values: the coef Kp and Ki
  # It is possible to add others attributes:
  #   - the cumulated error
  #   - some constant matrices
  def initialize(logfile, cluster, config_file)
    config_data = JSON.parse(File.read(config_file))
    @nb_jobs = 0
	@logfile = logfile # TODO: May need to create the file if does not exist
	@cluster = cluster
  end

  def update_controlled_value()
    return
  end

  def update_nb_jobs_submitted(n)
    @nb_jobs = n
  end

  def get_fileserver_load()
    loadavg_per_sensor = []
    Dir.glob("/tmp/loadavg_storage_server[0-9]").sort().each_with_index do |f, i|
      l =  `tail -n 1 #{f}`.split()
      loadavg_per_sensor[i] = {:date => l[0], :mn1 => l[1].to_f, :mn5 => l[2].to_f, :mn15 => l[3].to_f}
    end
    loadavg_per_sensor[0][:mn1]
  end

  def update_error()
    return
  end

  def log()
	file = File.open(@logfile, "a+")
        file << "#{Time.now.to_i}, #{@nb_jobs}, #{self.get_waiting_jobs()}, #{self.get_running_jobs()}, #{self.get_fileserver_load}, #{self.get_cluster_load}\n"
    file.close
  end

  def get_running_jobs()
	cluster_jobs = @cluster.get_jobs()
    nb_running_jobs = cluster_jobs.select{|j| j["state"] == "Running" or j["state"] == "Finishing" or j["state"] == "Launching"}.length
    # if nb_running_jobs > 0
    #   @has_running_campaigns = true
    # end
    nb_running_jobs
  end

  def get_waiting_jobs()
	cluster_jobs = @cluster.get_jobs()
    nb_waiting_jobs = cluster_jobs.select{|j| j["state"] == "Waiting"}.length
    # if nb_waiting_jobs > 0
    #   @has_running_campaigns = true
    # end
    nb_waiting_jobs
  end

  def get_cluster_load()
	@cluster.get_global_stress_factor
  end

  def get_nb_jobs()
	@nb_jobs
  end
end

def p_controller(error, k)
  k * error
end


def get_rates_for_campaigns(campaigns, campaign_heaviness, rate, percentage)
  # Will contain the mapping campaign_id -> rate
  rates = {}

  if campaigns.length == 1
    rates[campaigns[0]] = percentage.to_i * rate
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
