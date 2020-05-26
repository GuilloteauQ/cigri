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

def cigri_model(q,r,f,p,kin,rmax,u,dt, memory_b)
    # Non-negative discrete actuation
    u = u*(u>0 ? 1 : 0)
    u = u.to_i

    btmp = b(q,r,rmax)
    memory_b.push(btmp)

    # Dynamics
    delay = (1/(p*dt) + 1).to_i
    p delay
    finished_jobs = 0
    if delay <= memory_b.length - 1
      finished_jobs = memory_b[(memory_b.length - 1) - delay]
    end
    qout = q - btmp + u
    rout = r + btmp - finished_jobs
    fout = kin*(btmp**2.05) + (1-0.015*dt)*f
    fout = fout.real
   
    # Non-negative jobs
    qout = qout*(qout>0 ? 1 : 0)
	rout = rout*(rout>0 ? 1 : 0)
    fout = fout*(fout>0 ? 1 : 0)
    
    if rout > rmax
        rout = rmax
    end
    
    return [qout,rout,fout]
end

def costfit(q,r,f,p,kin,rmax,q_ref,r_ref,f_ref,dt,overload, memory_b)
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
            q_est[i],r_est[i],f_est[i] = cigri_model(q_est[-1],r_est[-1],f_est[-1],p,kin,rmax,u,dt, memory_b)
        end
        
        # Do I have an absolute maximum?
        reached_maximum = (r_est[-1] == r_est_final)

        # As we are just predicting, we have to remove the value necessary
        # for the prediction.
        # As we are dealing with an horizon of 2, we remove the last two elements
        # but if we reach a maximum, we only remove horizon - 1
        # as the first value of the horizon is correct
        if !reached_maximum
          memory_b.pop(2)
        else
          memory_b.pop(1)
        end


        # Compute the one-step-ahead prediction
        q_est_final = q_est[-1]
        r_est_final = r_est[-1]
        f_est_final = f_est[-1]
        
    end

    u = u - 1
    
    return u

end
