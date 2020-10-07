require 'cigri-clusterlib'
require 'json'
require 'matrix'

class Controller
  # We try to give a generic API for the controller
  # Here parameters contains most likely a list of all the parameters to use
  # in the case of a PI controller is will contain two values: the coef Kp and Ki
  # It is possible to add others attributes:
  #   - the cumulated error
  #   - some constant matrices
  #
  #
  # x_est[0, 0] = waiting
  # x_est[1, 0] = running
  # x_est[2, 0] = processing rate
  # x_est[3, 0] = available nodes
  # x_est[4, 0] = fileserver load
  # x_est[5, 0] = kin
  def initialize(logfile, cluster, config_file, dt)
    config_data = JSON.parse(File.read(config_file))
    @nb_jobs = config_data["nb_jobs"].nil? ? 0 : config_data["nb_jobs"].to_i
    @error = 0
    @logfile = logfile # TODO: May need to create the file if does not exist
    # file = File.new(@logfile, File::CREAT|File::TRUNC|File::RDWR, 0777)
    @cluster = cluster
    print(config_data["x_est"])
    @x_est = Matrix[config_data["x_est"]].transpose
    print(@x_est)

    @q_ref = config_data["q_ref"].nil? ? 0 : config_data["q_ref"].to_f
    @r_ref = config_data["r_ref"].nil? ? 0 : config_data["r_ref"].to_f
    @f_ref = config_data["f_ref"].nil? ? 0 : config_data["f_ref"].to_f

    @rmax_estimated = 0

    @P = Matrix[*config_data["P"]]
    @H = Matrix[*config_data["H"]]
    @Q = Matrix[*config_data["Q"]]
    @R = config_data["R"].nil? ? 0 : config_data["R"].to_f
    @dt = dt

    @u = 0

    @rv = Array.new; @rv.push 0
    @i = 0
  end

  def get_rmax_estimate()
    # TODO: Taken from the original code: where the F is this +10 coming from ?
    @rv.push(self.get_running_jobs())

    # Keep the history up to 10 values
    if @rv.length > 5
      @rv.shift
    end
    @rmax_estimated = @rv.max + 10
    @i += 1
  end

  def set_nb_of_actually_submitted_jobs()
    @u = @nb_jobs
  end


  def update_kalman_filter()
    q_sampled = self.get_waiting_jobs()
    r_sampled = self.get_running_jobs()
    f = self.get_cluster_load()

    print(@H)
    print(@x_est)
    ym = Matrix[[q_sampled],[r_sampled],[f]] - @H*@x_est
print(@H*@P*(@H.transpose))
    k_matrix = @P*(@H.transpose)*(( Matrix.build((@H*@P*(@H.transpose)).row_count) {@R} + @H*@P*(@H.transpose) ).inverse)
    @x_est = @x_est + (k_matrix*ym)
    @P = (Matrix.identity((k_matrix*@H).row_count) - k_matrix*@H)*@P
  end

  def update_covariance_matrix()
    # TODO: 2.05 and 0.015 should be in the JSON file
    asd = @x_est[3,0]**2.05
    asd = asd.real
	x = @x_est

	a_matrix = Matrix[[1, 0, 0, -@dt, 0, 0],
               [0, 1-@dt*x[2,0], -@dt*x[1,0], @dt, 0, 0],
               [0, 0, 1, 0, 0, 0],
               [0, 0, 0, 1, 0, 0],
               [0, 0, 0, 0, 1-0.015*@dt, asd],
               [0, 0, 0, 0, 0, 1]]

	@P = (a_matrix*@P*(a_matrix.transpose)) + @Q

	# Predict future value
	x = *@x_est
	x[0][0],x[1][0],x[4][0] = cigri_model(x[0][0],x[1][0],x[4][0],x[2][0],x[5][0],@rmax_estimated, @u, @dt)
	x[3][0] = get_nb_available_nodes(x[0][0],x[1][0], @rmax_estimated)
	@x_est = Matrix[*x]
  end

  def update_controlled_value()

    self.get_rmax_estimate()

    self.update_kalman_filter()

    q_sampled = self.get_waiting_jobs()
    r_sampled = self.get_running_jobs()
    f = self.get_cluster_load()

	@nb_jobs = costfit(q_sampled,r_sampled,f,@x_est[2,0],@x_est[5,0],@rmax_estimated,@q_ref,@r_ref,@f_ref,@dt,false) # TODO: overload = false in the original code, but this would be better to change it to (fileserver_load > STRESS_FACTOR) something like that...
    @u = 0
  end

  def log()
	file = File.open(@logfile, "a+")
    file << "#{Time.now.to_i}, #{self.get_waiting_jobs()}, #{self.get_running_jobs()}, #{self.get_cluster_load()}, #{@u}\n"
    file.close
  end

  def get_running_jobs()
	cluster_jobs = @cluster.get_jobs()
    cluster_jobs.select{|j| j["state"] == "Running" or j["state"] == "Finishing" or j["state"] == "Launching"}.length
  end

  def get_waiting_jobs()
	cluster_jobs = @cluster.get_jobs()
    cluster_jobs.select{|j| j["state"] == "Waiting"}.length
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

def get_nb_available_nodes(waiting, running, rmax)
  available = rmax - running
  (waiting < available) ? waiting : ((available < 0) ? 0 : available)
end

def set_positive_or_zero(x)
  (x < 0) ? 0 : x
end

def cigri_model(waiting, running, fileserver_load, processing_rate, kin, rmax, u, dt)
    # Non-negative discrete actuation
    u = set_positive_or_zero(u)

    nodes_available = get_nb_available_nodes(waiting, running, rmax)

    # Dynamics of the system
    waiting_model = waiting - nodes_available + u
    running_model = running + nodes_available - processing_rate * running * dt
    fileserver_load_model = (kin*(nodes_available**2.05) + (1 - 0.015*dt)*fileserver_load).real

    # Non-negative jobs
    waiting_model = set_positive_or_zero(waiting_model)
	running_model = set_positive_or_zero(running_model)
    fileserver_load_model = set_positive_or_zero(fileserver_load_model)

    running_model = (running_model > rmax) ? rmax : running_model

    return [waiting_model, running_model, fileserver_load_model]
end

def costfit(waiting, running, fileserver_load, processing_rate ,kin, rmax, waiting_reference, running_reference, fileserver_load_reference, dt, overload)
    waiting_estimation_final = 0
    running_estimation_final = 0
    fileserver_load_estimation_final = 0
    reached_maximum = false
    u = 0

    while (running_estimation_final < running_reference) and not(reached_maximum) and waiting_estimation_final <= waiting_reference and fileserver_load_estimation_final <= fileserver_load_reference do
        u += 1

        waiting_estimation = [waiting]
        running_estimation = [running]
        fileserver_load_estimation = [fileserver_load]

        for i in 1..2
            waiting_estimation[i], running_estimation[i],fileserver_load_estimation[i] = cigri_model(waiting_estimation[-1],running_estimation[-1],fileserver_load_estimation[-1], processing_rate,kin,rmax,u,dt)
        end

        # Do I have an absolute maximum?
        reached_maximum = (running_estimation[-1] == running_estimation_final)

        # Compute the one-step-ahead prediction
        waiting_estimation_final = waiting_estimation[-1]
        running_estimation_final = running_estimation[-1]
        filesever_load_estimation_final = fileserver_load_estimation[-1]
    end

    u = u - 1
    return u

end
