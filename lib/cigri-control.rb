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
    @threshold = 3
    @error = 0

    @logfile = logfile # TODO: May need to create the file if does not exist
    @cluster = cluster

    @slices = [10, 20, 30, 40, 50]
    # @perf_slices = [0, 0, 0, 0, 0]
    @perf_slices = Array.new(@slices.length, 0)

    @is_champion_running = false
    @champion = -1
    @done_scanning = false
    @need_to_scan = true
    @iteration = -1

    @load_before_submission = -1
    @current_max_load = -1


    @prologue_starting = false
    @prologue_done = false
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
    file << "#{Time.now.to_i}, #{@nb_jobs}, #{self.get_waiting_jobs()}, #{self.get_running_jobs()}, #{self.get_fileserver_load()}, #{@iteration}, #{@champion}\n"
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

  def get_perf(max_load, max_running_jobs)
    rmax = 10
    distance_load = @reference - max_load
    f_max = 8
    f_M = (@reference > (@reference - f_max).abs) ? @refrence : (@reference - f_max).abs
    return 0.3 * (rmax - max_running_jobs).abs / rmax + 0.7 * (@reference - max_load).abs / f_M
  end

  def get_nb_jobs_champion()
    @nb_jobs = @slices[@champion]
    return @nb_jobs
  end

  def update_max_load()
    current_load = self.get_fileserver_load()
    @current_max_load = (current_load > @current_max_load) ? current_load : @current_max_load;
  end

  def reset_max_load()
    @current_max_load = -1
  end

  def update_max_running()
    current_running = self.get_running_jobs()
    @current_max_running = (current_running > @current_max_running) ? current_running : @current_max_running;
  end

  def reset_max_running()
    @current_max_running = -1
  end

  def can_submit_new_value()
    self.update_max_running()
    self.update_max_load()
    current_load = self.get_fileserver_load()

    current_jobs = Cigri::Jobset.new
    current_jobs.get_submitted(@cluster.id)
    current_jobs.get_running(@cluster.id)
    current_jobs.to_jobs
    nb_jobs_still_running = current_jobs.jobs.length

    if current_load - @load_before_submission < 0.3 && nb_jobs_still_running == 0 then
      @perf_slices[@iteration] = self.get_perf(@current_max_load, @current_max_running)
      return true
    end
    return false
  end

  def scanning_phase()
    if @iteration == -1 || self.can_submit_new_value() then
      @iteration = @iteration + 1
      @load_before_submission = self.get_fileserver_load()
      self.reset_max_running()
      self.reset_max_load()
      print "Submitting #{@slices[@iteration]} jobs\n"
      @nb_jobs = (@iteration < @slices.length) ? @slices[@iteration] : 0
    else
      print "Waiting for back to normal: Load: #{@load_before_submission}\n"
      @nb_jobs = 0
    end
    return @nb_jobs
  end

  def champion_selection()
    # We look at all the perfs form all the slices
    # and chose the champion
    index = 0
    max = @perf_slices[index]
    for i in 1..(@slices.length - 1) do
      if max > @perf_slices[i] then # only look the load part
        index = i
        max = @perf_slices[i]
      end
    end
    @champion = index
  end

  def get_nb_jobs()
    current_jobs = Cigri::Jobset.new
    current_jobs.get_submitted(@cluster.id)
    current_jobs.get_running(@cluster.id)
    current_jobs.to_jobs
    print "jobs: #{current_jobs.jobs.length}\n"

    jobs=Cigri::Jobset.new(:where => "jobs.state='to_launch' and jobs.cluster_id=#{@cluster.id}")# .to_jobs
    print "jobs_lenght: #{jobs.jobs.length}\n"
    jobs=jobs.to_jobs
    @prologue_starting = @prologue_starting || jobs.select{ |j| j.props[:tag] = "prologue"}.length == 1
    @prologue_done = @prologue_done || (@prologue_starting && jobs.select{ |j| j.props[:tag] = "prologue"}.length == 0)
    print "prologue_starting = #{@prologue_starting}, prologue_done = #{@prologue_done}\n"
    #if @cluster.running_campaigns.length > 0 then
    if @prologue_done then
    # print "jobs: #{jobs.jobs}\n"
    print "Has launching jobs: #{@cluster.has_launching_jobs?}\n"
    # if @cluster.has_launching_jobs? then
      # Look if we need to scan
      if @iteration == -1 && !@need_to_scan && (@reference - self.get_fileserver_load()).abs > @threshold then
        @need_to_scan = true
        @is_champion_running = false
        @champion = -1
      end

      if @is_champion_running && !@need_to_scan then
        print ">>> Champion Running\n"
        return self.get_nb_jobs_champion()
      end

      if @iteration < @slices.length && @need_to_scan then
        print ">>> Scanning (#{@iteration}/#{@slices.length})\n"
        return self.scanning_phase()
      end

      if @need_to_scan && @iteration >= @slices.length then
        print ">>> Selecting the champion\n"
        self.champion_selection()
        @iteration = -1
        @is_champion_running = true
        @need_to_scan = false
        print ">>> New champion : #{@champion}\n"
        return self.get_nb_jobs_champion()
      end
    else
      @nb_jobs = 0
      return @nb_jobs
    end
  end
end
