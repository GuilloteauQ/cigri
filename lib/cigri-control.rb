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
    @nb_jobs = config_data["nb_jobs"].nil? ? 0 : config_data["nb_jobs"].to_i
    @percentage = config_data["percentage"].nil? ? 50 : config_data["percentage"].to_i
    @reference = config_data["reference"].nil? ? 10 : config_data["reference"].to_i
	@error = 0
	@logfile = logfile # TODO: May need to create the file if does not exist
	@cluster = cluster
    @kp_jobs = config_data["kp_jobs"].nil? ? 1 : config_data["kp_jobs"].to_f
    @kp_percentage = config_data["kp_percentage"].nil? ? 1 : config_data["kp_percentage"].to_f
    @reference_stress_factor = config_data["ref_stress_factor"].nil? ? 1 : config_data["ref_stress_factor"].to_f
    @has_running_campaigns = false
    @threshold = config_data["threshold"].nil? ? 1 : config_data["threshold"].to_f
  end

  def update_has_running_campaigns()
    @has_running_campaigns = (@has_running_campaigns or self.get_running_jobs() + self.get_waiting_jobs() > 0)
  end

  def update_controlled_value()
    print(">> updating controlled values (previous values: (#{@nb_jobs}, #{@percentage}))\n")
    if @has_running_campaigns
      print("error: #{@error}\n")
      if (@error).abs() >= @threshold
        @nb_jobs = bound_nb_jobs(@nb_jobs + p_controller(@error, @kp_jobs))
      elsif @nb_jobs > 0
        # If we change the percentage when there is no job, this means
        # that we are regulating the load of an empty cluster...
        # So we make sure this does not happen
        @percentage = bound_percentage(@percentage + p_controller(@error, @kp_percentage))
      end
    end
    print("<< updated controlled values (new values: (#{@nb_jobs}, #{@percentage}))\n")
  end

  def update_error()
    @error = @reference_stress_factor - self.get_cluster_load()
  end

  def log()
	file = File.open(@logfile, "a+")
    file << "#{Time.now.to_i}, #{@nb_jobs}, #{@percentage}, #{self.get_waiting_jobs()}, #{self.get_running_jobs()}, #{self.get_cluster_load}, #{@has_running_campaigns}\n"
    file.close
  end

  def get_running_jobs()
	cluster_jobs = @cluster.get_jobs()
    nb_running_jobs = cluster_jobs.select{|j| j["state"] == "Running" or j["state"] == "Finishing" or j["state"] == "Launching"}.length
    if nb_running_jobs > 0
      @has_running_campaigns = true
    end
    nb_running_jobs
  end

  def get_waiting_jobs()
	cluster_jobs = @cluster.get_jobs()
    nb_waiting_jobs = cluster_jobs.select{|j| j["state"] == "Waiting"}.length
    if nb_waiting_jobs > 0
      @has_running_campaigns = true
    end
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
