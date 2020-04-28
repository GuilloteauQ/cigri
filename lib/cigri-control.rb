#!/usr/bin/ruby -w

class JobsAndPercentageCtrl
  attr_accessor :nb_jobs, :percentage, :kp_jobs, :kp_percentage

  def initialize(nb_jobs, percentage, kp_jobs, kp_percentage)
    @nb_jobs = nb_jobs
    @percentage = percentage
    @kp_jobs = kp_jobs
    @kp_percentage = kp_percentage
  end

  def update(error)
    if (error).abs() >= 1
      @nb_jobs = bound_nb_jobs(@nb_jobs + p_controller(error, @kp_jobs))
    elsif nb_jobs > 0
      # If we change the percentage when there is no job, this means
      # that we are regulating the load of an empty cluster...
      # So we make sure this does not happen
      @percentage = bound_percentage(@percentage + p_controller(error, @kp_percentage))
    end
  end

  def get_nb_jobs
    @nb_jobs
  end

  def get_percentage
    @percentage
  end
end

# def get_nb_allow_job_percentage(error, nb_allow_jobs, percentage, kp_nb_jobs, kp_percentage)
#   # We do not want to change the number of jobs sent or the percentage
#   # only based on the load of the cluster when no campaign is running
#   if (error).abs() >= 1
#     nb_allow_jobs = bound_nb_jobs(nb_allow_jobs + p_controller(error, kp_nb_jobs))
#   elsif nb_allow_jobs > 0
#     # If we change the percentage when there is no job, this means
#     # that we are regulating the load of an empty cluster...
#     # So we make sure this does not happen
#     percentage = bound_percentage(percentage + p_controller(error, kp_percentage))
#   end
#   return (nb_allow_jobs, percentage)
# end

def ctrl(ref, queue_load, kp, ki, memoire)
    epsilon = ref - queue_load
    somme = memoire + epsilon
    pk = kp * epsilon
    ik = ki * 6.8716 * somme
    result = pk + ik
    return result, somme
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

def p_controller_2(current_percentage, error)
  kp = 2
  return current_percentage + kp * error
end

def p_controller(error, kp)
  return error * kp
end

def pi_controller(current_percentage, error, cumulated_error)
  kp = 2
  ki = 0
  return current_percentage + kp * error + ki * cumulated_error
end

def compute_error(reference, cluster)
  return reference - cluster.get_global_stress_factor
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

def export2file(type,data,cluster,file,temps)
  file = File.open(file, "a+")
  file << "#{type};#{data};#{temps.to_f};#{cluster}\n"
  file.close
  return nil
end

def b(q,r,rmax)
    out = rmax - r
    if q < out
        out = q
    end
    if out < 0
        out = 0
    end
    return out
end

def cigri_model(q,r,f,p,kin,rmax,u,dt)
    # Non-negative discrete actuation
    u = u*(u>0 ? 1 : 0)
    u = u.to_i

    btmp = b(q,r,rmax)

    # Dynamics
    qout = q - btmp + u
    rout = r + btmp - p*r*dt
    fout = kin*(btmp**2.05) + (1-0.015*dt)*f
    fout = fout.real
   
    # Non-negative jobs
    qut = qout*(qout>0 ? 1 : 0)
	rout = rout*(rout>0 ? 1 : 0)
    fout = fout*(fout>0 ? 1 : 0)
    
    if rout > rmax
        rout = rmax
    end
    
    return [qout,rout,fout]
end

def costfit(q,r,f,p,kin,rmax,q_ref,r_ref,f_ref,dt,overload)
    q_est_final = 0
    r_est_final = 0
    f_est_final = 0
    reached_maximum = false
    u = 0

    #while ((r_est_final < r_ref) and not(reached_maximum) and q_est_final <= q_ref) or ((q_est_final < q_ref) and not(overload)) do
    while (r_est_final < r_ref) and not(reached_maximum) and q_est_final <= q_ref and f_est_final <= f_ref do
        u += 1
    
        q_est = [q]
        r_est = [r]
        f_est = [f]
        
        for i in 1..2
            q_est[i],r_est[i],f_est[i] = cigri_model(q_est[-1],r_est[-1],f_est[-1],p,kin,rmax,u,dt)
        end
        
        # Do I have an absolute maximum?
        reached_maximum = (r_est[-1] == r_est_final)

        # Compute the one-step-ahead prediction
        q_est_final = q_est[-1]
        r_est_final = r_est[-1]
        f_est_final = f_est[-1]
        
    end

    u = u - 1
    
    return u

end
