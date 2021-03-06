@with_kw struct Vomps{F} <: Algorithm
    tol_galerkin::Float64 = Defaults.tol
    tol_gauge::Float64 = Defaults.tolgauge
    maxiter::Int = Defaults.maxiter
    orthmaxiter::Int = Defaults.maxiter
    finalize::F = Defaults._finalize
    verbose::Bool = Defaults.verbose
end

function approximate(state::InfiniteMPS, toapprox::Tuple{<:InfiniteMPO,<:InfiniteMPS}, alg::Vomps, envs = environments(state,toapprox))
    #PeriodicMPO's always act on MPSMultiline's. I therefore convert the imps to multilines, approximate and convert back
    (multi,envs) = approximate(convert(MPSMultiline,state),(convert(MPOMultiline,envs.opp),convert(MPSMultiline,envs.above)),alg,envs)
    state = convert(InfiniteMPS,multi)
    return (state,envs)
end


function approximate(state::MPSMultiline, toapprox::Tuple{<:MPOMultiline,<:MPSMultiline}, alg::Vomps, envs = environments(state,toapprox))
    (mpo,above) = toapprox;

    galerkin  = 1+alg.tol_galerkin
    iter       = 1

    temp_ACs = map(x->x,state.AC);
    temp_Cs = map(x->x,state.CR);

    while true

        @sync for col in 1:size(state,2)
            @Threads.spawn temp_ACs[:,col] = circshift([ac_proj(row,col,state,envs) for row in 1:size(state,1)],1)
            @Threads.spawn temp_Cs[:,col]  = circshift([c_proj(row,col,state,envs) for row in 1:size(state,1)],1)
        end

        for row in 1:size(state,1),col in 1:size(state,2)
            QAc,_ = leftorth!(temp_ACs[row,col], alg=TensorKit.QRpos())
            Qc,_  = leftorth!(temp_Cs[row,col], alg=TensorKit.QRpos())
            temp_ACs[row,col] = QAc*adjoint(Qc)
        end

        state = MPSMultiline(temp_ACs,state.CR[:,end]; tol = alg.tol_gauge, maxiter = alg.orthmaxiter);
        recalculate!(envs,state);

        galerkin   = calc_galerkin(state, envs)
        alg.verbose && @info "vomps @iteration $(iter) galerkin = $(galerkin)"

        (state,envs) = alg.finalize(iter,state,toapprox,envs);

        if (galerkin <= alg.tol_galerkin) || iter>=alg.maxiter
            iter>=alg.maxiter && @warn "vomps didn't converge $(galerkin)"
            return state, envs, galerkin
        end

        iter += 1
    end
end
