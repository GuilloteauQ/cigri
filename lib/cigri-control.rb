#!/usr/bin/ruby -w

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

def write_data_for_heatmap(filename, loop_time, action_job_ids, waiting_job_ids, running_job_ids)
  file = File.open(filename, "a+")
  # Writing Action jobs
  action_job_ids.each do |id|
    if not waiting_job_ids.include? id
      file <<  "#{loop_time.to_f}, #{id}, A\n"
    else
      file <<  "#{loop_time.to_f}, #{id}, N\n"
    end
  end

  # Writing Waiting jobs
  waiting_job_ids.each do |id|
    if not action_job_ids.include? id
      file <<  "#{loop_time.to_f}, #{id}, W\n"
    end
  end

  # Writing Running jobs
  running_job_ids.each do |id|
    file <<  "#{loop_time.to_f}, #{id}, R\n"
  end
  file.close
end
