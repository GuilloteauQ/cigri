require 'cigri-clusterlib'
require 'json'

class Controller
  # We try to give a generic API for the controller
  # Here parameters contains most likely a list of all the parameters to use
  # in the case of a PI controller is will contain two values: the coef Kp and Ki
  # It is possible to add others attributes:
  #   - the cumulated error
  #   - some constant matrices
  def initialize(logfile, cluster, config_file, dt)
    # config_data = JSON.parse(File.read(config_file))
    @nb_jobs = 0 #config_data["nb_jobs"].nil? ? 0 : config_data["nb_jobs"].to_i
    @reference = 3
    @threshold = 1
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

    @time_at_start_submission = Time.now.to_i
    @load_before_submission = -1
    @current_max_load = -1
    @alpha = Math.exp(-5/60)
    @dt = dt / 5
    print "dt: #{@dt}\n"

    @prologue_starting = false
    @prologue_done = false
    @wait = true
  end

  def get_fileserver_load()
    loadavg_per_sensor = []
    Dir.glob("/tmp/loadavg_storage_server[0-9]").sort().each_with_index do |f, i|
      l =  `tail -n 1 #{f}`.split()
      loadavg_per_sensor[i] = {:date => l[0], :mn1 => l[1].to_f, :mn5 => l[2].to_f, :mn15 => l[3].to_f}
    end
    loadavg_per_sensor[0][:mn1]
  end

  def read_loadavg_per_sensor_for_timeslice(start_time, end_time, sensor_id)
    filename = "/tmp/loadavg_storage_server#{sensor_id}"
    # cmd_result = `awk '{ if (!($1 < #{start_time}) && !($1 > #{end_time})) print $1 " " $2 }' #{filename}`
    cmd_result = `cut -f 1-2 -d ' ' #{filename}`
    data = Array.new
    for c in cmd_result.split("\n") do
      arr = c.split(" ")
      time = arr[0].to_i
      load_value = arr[1].to_i
      if time >= start_time && time <= end_time then
        data.push({:time => arr[0].to_i, :load => arr[1].to_f})
      end
    end
    print ("data: #{data}\n")
    return data
  end

  def get_time_start_of_writing_phase(submission_time, sensor_id)
    data = self.read_loadavg_per_sensor_for_timeslice(submission_time, Time.now.to_i, sensor_id)

    maximum = data.max_by {|e| e[:load]}

    n = data.length

    print "Data: #{data}\n"

    diffs = Array.new

    if n == 0 then
      return nil
    end

    if n <= 1 then
      return data[0]
    end

    for i in 1..(n - 1) do
      e = data[i]
      if e[:time] >= maximum[:time] then
        break
      end
      e[:load] = e[:load] - data[i - 1][:load]
      diffs.push(e)
    end
    print "Diffs: #{diffs}\n"
    return diffs.max_by {|e| e[:load] }
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

  def N_estimator(fmax, f0, tr)
    return (fmax - f0 * @alpha**tr) / ( 1 - @alpha**tr)
  end

  def compute_limit_load(estimated_N, tr)
    return estimated_N * (1 - @alpha**tr) / (1 - @alpha ** @dt)
  end

  def get_perf(data, max_running_jobs)
    max_load = data.max_by { |e| e[:load]}
    f_max = max_load[:load]
    t_max = max_load[:time]
    start_writing_phase = self.get_time_start_of_writing_phase(@time_at_start_submission, 0)

    if start_writing_phase.nil? then
      return 1
    end

    rising_time = (t_max - start_writing_phase[:time]) / 5 # div by 5 because the load is updated every 5 secs
    print "Rising time: #{rising_time}\n"
    estimated_N = self.N_estimator(f_max, @load_before_submission, rising_time)
    print "Est. N : #{estimated_N}\n"
    limit_load_for_sub_size = self.compute_limit_load(estimated_N, rising_time) # + @load_before_submission
    print "limit load: #{limit_load_for_sub_size}\n"

    rmax = 100
    # distance_load = @reference - max_load
    distance_load = @reference - limit_load_for_sub_size
    max_f_config = 8
    f_M = (@reference > (@reference - max_f_config).abs) ? @reference : (@reference - max_f_config).abs
    print "f_M: #{f_M}\n"
    alpha = 0
    return  alpha * (rmax - max_running_jobs).abs / rmax + (1 - alpha) * (@reference - limit_load_for_sub_size).abs / f_M
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
      load_evolution_during_submission = self.read_loadavg_per_sensor_for_timeslice(@time_at_start_submission, Time.now.to_i, 0)
      # @current_max_load = load_evolution_during_submission.max_by { |e| e[:load] }[:load]
      # @perf_slices[@iteration] = self.get_perf(@current_max_load, @current_max_running)
      @perf_slices[@iteration] = self.get_perf(load_evolution_during_submission, @current_max_running)
      return true
    end
    print "Cannot submit again yet\n"
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
      @time_at_start_submission = Time.now.to_i
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
    print "perfs: #{@perf_slices}\n"

    jobs=Cigri::Jobset.new(:where => "jobs.state='to_launch' and jobs.cluster_id=#{@cluster.id}")# .to_jobs
    print "jobs_lenght: #{jobs.jobs.length}\n"
    jobs=jobs.to_jobs
    @prologue_starting = @prologue_starting || jobs.select{ |j| j.props[:tag] = "prologue"}.length >= 1
    @prologue_done = @prologue_done || (@prologue_starting && jobs.select{ |j| j.props[:tag] = "prologue"}.length == 0)
    print "prologue_starting = #{@prologue_starting}, prologue_done = #{@prologue_done}\n"
    #if @cluster.running_campaigns.length > 0 then
    if @prologue_done then
    # print "jobs: #{jobs.jobs}\n"
    print "Has launching jobs: #{@cluster.has_launching_jobs?}\n"
    # if @cluster.has_launching_jobs? then
      # Look if we need to scan
      if @iteration > 5000 && @is_champion_running && !@need_to_scan && (@reference - self.get_fileserver_load()).abs > @threshold then
        @need_to_scan = true
        @is_champion_running = false
        @champion = -1
        @iteration = -1
      end

      if @is_champion_running && !@need_to_scan then
        print ">>> Champion Running\n"
        # @wait = !@wait
        # if @wait then
        #   return 0
        # else
        #   @iteration = @iteration + 1
        #   return self.get_nb_jobs_champion()
        # end
        @iteration = @iteration + 1
        return self.get_nb_jobs_champion()
      end

      if @iteration < @slices.length && @need_to_scan then
        print ">>> Scanning (#{@iteration}/#{@slices.length})\n"
        nb = self.scanning_phase()
        return nb
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
