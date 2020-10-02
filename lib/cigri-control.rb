require 'cigri-clusterlib'

class Controller
  # We try to give a generic API for the controller
  # Here parameters contains most likely a list of all the parameters to use
  # in the case of a PI controller is will contain two values: the coef Kp and Ki
  # It is possible to add others attributes:
  #   - the cumulated error
  #   - some constant matrices
  def initialize(logfile, cluster)
    @nb_jobs = 0
	@reference = 10 # TODO To set accordingly
	@error = 0
	@logfile = logfile # TODO: May need to create the file if does not exist
	@cluster = cluster
  end

  def update_controlled_value()
	# TODO to set accordingly
	@nb_jobs = @nb_jobs + 1 * @error
  end

  def update_error(value)
	@error = @reference - value
  end

  def log()
	file = File.open(@logfile, "a+")
    file << "#{Time.now.to_i}, #{@nb_jobs}\n"
    file.close
  end

  def get_running_jobs()
	cluster_jobs = @cluster.get_jobs()
	cluster_jobs.select{|j| j["state"] == "Running" or j["state"] == "Finishing" or j["state"] == "Launching"}
  end

  def get_waiting_jobs()
	cluster_jobs = @cluster.get_jobs()
	cluster_jobs.select{|j| j["state"] == "Waiting"}
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

end
