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
    # config_data = JSON.parse(File.read(config_file))
    @nb_jobs = 0 #config_data["nb_jobs"].nil? ? 0 : config_data["nb_jobs"].to_i
    @reference = 3
    @threshold = 1
    @error = 0

    @logfile = logfile # TODO: May need to create the file if does not exist
    @cluster = cluster

    @slices = [0, 5, 10, 15, 20]
    # @perf_slices = [0, 0, 0, 0, 0]
    @perf_slices = Array.new(@slices.length, 0)

    @is_champion_running = false
    @champion = -1
    @done_scanning = false
    @need_to_scan = true
    @iteration = 0
  end

  def get_fileserver_load()
    loadavg_per_sensor = []
    Dir.glob("/tmp/loadavg_storage_server[0-9]").sort().each_with_index do |f, i|
      l =  `tail -n 1 #{f}`.split()
      loadavg_per_sensor[i] = {:date => l[0], :mn1 => l[1].to_f, :mn5 => l[2].to_f, :mn15 => l[3].to_f}
    end
    loadavg_per_sensor[0][:mn1]
  end


  def log()
    file = File.open(@logfile, "a+")
    file << "#{Time.now.to_i}, #{@nb_jobs}, #{self.get_waiting_jobs()}, #{self.get_running_jobs()}, #{self.get_fileserver_load}, #{@champion}\n"
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

  def get_perf()
    rmax = 10
    running_jobs = self.get_running_jobs()
    fileserver_load = self.get_fileserver_load()
    distance_load = @reference - fileserver_load
    f_max = 8
    f_M = (@reference > (@reference - f_max).abs) ? @refrence : (@reference - f_max).abs
    return 0.3 * (rmax - running_jobs).abs / rmax + 0.7 * (@reference - fileserver_load).abs / f_M
  end

  def get_nb_jobs()
    # Look if we need to scan
    if @done_scanning && !@need_to_scan && (@reference - self.get_fileserver_load()).abs > @threshold then
      @need_to_scan = true
      @done_scanning = false
      @is_champion_running = false
    end

    if @is_champion_running && !@need_to_scan then
      return @slices[@champion]
    end

    if @need_to_scan && @done_scanning then
      # We look at all the perfs form all the slices
      # and chose the champion
      @perf_slices[@iteration - 1] = self.get_perf()
      index = 0
      max = @perf_slices[index]
      for i in 1..(@slices.length - 1) do
        if max < @perf_slices[i] then # only look the load part
          index = i
          max = @perf_slices[i]
        end
      end
      @iteration = 0
      @champion = index
      @is_champion_running = true
      @need_to_scan = false # TODO:  vraiment ou pas ?
      return @slices[@champion]
    end

    if @need_to_scan && ! @done_scanning then
      if @iteration != 0 then
        @perf_slices[@iteration - 1] = self.get_perf()
      end
      @iteration = @iteration + 1
      if @iteration == @slices.length then
        @done_scanning = true
      end
      return @slices[@iteration - 1]
    end
  end
end
