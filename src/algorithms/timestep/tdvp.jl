"onesite tdvp"
@with_kw struct Tdvp <: Algorithm
    tol::Float64 = Defaults.tol
    tolgauge::Float64 = Defaults.tolgauge
    maxiter::Int = Defaults.maxiter
end

"""
    function timestep(psi, operator, dt, alg,envs = environments(psi,operator))

time evolves psi by timestep dt using algorithm alg
"""
function timestep(state::InfiniteMPS, H::Hamiltonian, timestep::Number,alg::Tdvp,envs::Cache=environments(state,H))

    temp_ACs = similar(state.AC);
    temp_CRs = similar(state.CR);

    @sync for (loc,(ac,c)) in enumerate(zip(state.AC,state.CR))
        @Threads.spawn begin
            (temp_ACs[loc],convhist) = exponentiate(@closure(x->ac_prime(x,loc,state,envs)) ,-1im*timestep,ac,Lanczos(tol=alg.tol))
            convhist.converged==0 && @info "time evolving ac($loc) failed $(convhist.normres)"
        end

        @Threads.spawn begin
            (temp_CRs[loc],convhist) = exponentiate(@closure(x->c_prime(x,loc,state,envs)) ,-1im*timestep,c,Lanczos(tol=alg.tol))
            convhist.converged==0 && @info "time evolving a($loc) failed $(convhist.normres)"
        end
    end

    for loc in 1:length(state)

        #find Al that best fits these new Acenter and centers
        QAc,_ = leftorth!(temp_ACs[loc],alg=TensorKit.QRpos())
        Qc,_ = leftorth!(temp_CRs[loc],alg=TensorKit.QRpos())
        @tensor temp_ACs[loc][-1 -2;-3]=QAc[-1,-2,1]*conj(Qc[-3,1])
    end

    nstate = InfiniteMPS(temp_ACs,state.CR[end]; tol = alg.tolgauge, maxiter = alg.maxiter)
    recalculate!(envs,nstate)
    nstate,envs
end

function timestep!(state::Union{FiniteMPS,MPSComoving}, H::Operator, timestep::Number,alg::Tdvp,envs=environments(state,H))
    #left to right
    for i in 1:(length(state)-1)
        (state.AC[i],convhist) = exponentiate(@closure(x->ac_prime(x,i,state,envs)),-1im*timestep/2,state.AC[i],Lanczos(tol=alg.tolgauge))
        (state.CR[i],convhist) = exponentiate(@closure(x->c_prime(x,i,state,envs)),1im*timestep/2,state.CR[i],Lanczos(tol=alg.tolgauge))

    end

    (state.AC[end],convhist) = exponentiate(@closure(x->ac_prime(x,length(state),state,envs)),-1im*timestep/2,state.AC[end],Lanczos(tol=alg.tolgauge))

    #right to left
    for i in length(state):-1:2
        (state.AC[i],convhist) = exponentiate(@closure(x->ac_prime(x,i,state,envs)),-1im*timestep/2,state.AC[i],Lanczos(tol=alg.tolgauge))
        (state.CR[i-1],convhist) = exponentiate(@closure(x->c_prime(x,i-1,state,envs)),1im*timestep/2,state.CR[i-1],Lanczos(tol=alg.tolgauge))
    end

    (state.AC[1],convhist) = exponentiate(@closure(x->ac_prime(x,1,state,envs)),-1im*timestep/2,state.AC[1],Lanczos(tol=alg.tolgauge))

    return state,envs
end

"twosite tdvp (works for finite mps's)"
@with_kw struct Tdvp2 <: Algorithm
    tol::Float64 = Defaults.tol
    tolgauge::Float64 = Defaults.tolgauge
    maxiter::Int = Defaults.maxiter
    trscheme = truncerr(1e-3)
end

#twosite tdvp for finite mps
function timestep!(state::Union{FiniteMPS,MPSComoving}, H::Operator, timestep::Number,alg::Tdvp2,envs=environments(state,H);rightorthed=false)
    #left to right
    for i in 1:(length(state)-1)
        ac2 = _permute_front(state.AC[i])*_permute_tail(state.AR[i+1])

        (nac2,convhist) = exponentiate(@closure(x->ac2_prime(x,i,state,envs)),-1im*timestep/2,ac2,Lanczos())
        (nal,nc,nar) = tsvd(nac2,trunc=alg.trscheme, alg=TensorKit.SVD())

        state.AC[i] = (nal,complex(nc))
        state.AC[i+1] = (complex(nc),_permute_front(nar))

        if(i!=(length(state)-1))
            (state.AC[i+1],convhist) = exponentiate(@closure(x->ac_prime(x,i+1,state,envs)),1im*timestep/2,state.AC[i+1],Lanczos())
        end

    end

    #right to left

    for i in length(state):-1:2
        ac2 = _permute_front(state.AL[i-1])*_permute_tail(state.AC[i])

        (nac2,convhist) = exponentiate(@closure(x->ac2_prime(x,i-1,state,envs)),-1im*timestep/2,ac2,Lanczos())
        (nal,nc,nar) = tsvd(nac2,trunc=alg.trscheme,alg=TensorKit.SVD())

        state.AC[i-1] = (nal,complex(nc))
        state.AC[i] = (complex(nc),_permute_front(nar));

        if(i!=2)
            (state.AC[i-1],convhist) = exponentiate(@closure(x->ac_prime(x,i-1,state,envs)),1im*timestep/2,state.AC[i-1],Lanczos())
        end
    end

    return state,envs
end

#copying version
timestep(state::Union{FiniteMPS,MPSComoving},H,timestep,alg::Union{Tdvp,Tdvp2},envs=environments(state,H)) = timestep!(copy(state),H,timestep,alg,envs)
