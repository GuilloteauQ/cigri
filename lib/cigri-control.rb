require 'cigri-clusterlib'
require 'json'
require 'bigdecimal/math'

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
    @reference = config_data["reference"].nil? ? 3 : config_data["reference"].to_f
	@error = 0
    @cumulated_error = 0
    @kp = config_data["kp"].nil? ? 0 : config_data["kp"].to_f
    @ki = config_data["ki"].nil? ? 0 : config_data["ki"].to_f
	@logfile = logfile # TODO: May need to create the file if does not exist
	@cluster = cluster

        @a = Math.exp(-5.0/60.0) ** (30.0 / 5.0)
        @b = 0.5
        @ks = config_data["ks"].to_f
        @Mp = config_data["Mp"].to_f
        @Sn = 0.0
        @previous_load = 0.0
        @forgetting_factor = config_data["forgetting_factor"].to_f
  end

  def get_gains()
    r = Math.exp(-4.0 / @ks)
    theta = BigMath.PI(9) * Math.log(r) / Math.log(@Mp)
    @kp = (@a - r * r) / @b
    @ki = (r * r - 2 * r * Math.cos(theta) + 1) / @b
  end

  def update_estimation_b(current_load)
    if @nb_jobs.floor > 0
      @b = @forgetting_factor * @b * @Sn - @nb_jobs.floor * (current_load - @a * @previous_load)
      @Sn = @forgetting_factor * @Sn + (@nb_jobs.floor * @nb_jobs.floor)
      @b = @b / @Sn
    end
    @previous_load = current_load
  end

  def update_controlled_value()
	@nb_jobs = bound_jobs(@kp * @error + @ki * @cumulated_error)
  end

  def update_error(value)
    @error = @reference - value
    @cumulated_error = @cumulated_error + @error
  end

  def log()
	file = File.open(@logfile, "a+")
        # file << "#{Time.now.to_i}, #{@nb_jobs}, #{self.get_waiting_jobs()}, #{self.get_running_jobs()}, #{self.get_fileserver_load()}, #{@reference}\n"
        file << "#{Time.now.to_i}, #{@nb_jobs}, #{self.get_waiting_jobs()}, #{self.read_busy_resources_sensors}, #{self.get_fileserver_load()}, #{@reference}, #{@b}, #{@kp}, #{@ki}\n"
    file.close
  end

  def get_running_jobs()
	cluster_jobs = @cluster.get_jobs()
    cluster_jobs.select{|j| j["state"] == "Running" or j["state"] == "Finishing" or j["state"] == "Launching"}.length
  end

  def read_busy_resources_sensors()
    busy_resources_cluster = []
    Dir.glob("/tmp/busy_resources_cluster[0-9]").sort().each_with_index do |f, i|
      l =  `tail -n 1 #{f}`.split()
       busy_resources_cluster[i] = {:date => l[0], :busy => l[1].to_f}
    end
    return busy_resources_cluster[0][:busy]
  end


  def get_waiting_jobs()
	cluster_jobs = @cluster.get_jobs()
    cluster_jobs.select{|j| j["state"] == "Waiting"}.length
  end

  def get_cluster_load()
	@cluster.get_global_stress_factor
  end

  def get_fileserver_load()
      loadavg_per_sensor = []
      Dir.glob("/tmp/loadavg_storage_server[0-9]").sort().each_with_index do |f, i|
	l =  `tail -n 1 #{f}`.split()
	loadavg_per_sensor[i] = {:date => l[0], :mn1 => l[1].to_f, :mn5 => l[2].to_f, :mn15 => l[3].to_f}
      end
      loadavg_per_sensor[0][:mn1]
  end

  def get_error()
	@error
  end

  def get_nb_jobs()
	@nb_jobs
  end

end

def bound_jobs(x)
  if x < 0 then
    0
  else
    x
  end
end
