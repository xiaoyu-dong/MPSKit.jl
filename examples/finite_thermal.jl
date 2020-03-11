using MPSKit,TensorKit,Test,LinearAlgebra

let
    #the operator used to evolve is the anticommutator
    th = nonsym_ising_ham()

    ham = anticommutator(th)

    inftemp = infinite_temperature(th)

    ts = FiniteMPS(repeat(inftemp,10))
    ca = params(ts,ham);

    sx = TensorMap([0 1;1 0],ℂ^2,ℂ^2);

    betastep=0.1;endbeta=2;betas=collect(0:betastep:endbeta);
    sxdat=Float64[];

    for beta in betas
        (ts,ca) = managebonds(ts,ham,SimpleManager(10),ca);

        rightorth!(ts)# by normalizing, we are fixing tr(exp(-beta*H)*exp(-beta*H))=1

        push!(sxdat,sum(real(expectation_value(ts,sx)))/length(ts)) # calculate the average magnetization at exp(-2*beta*H)

        (ts,ca)=timestep(ts,ham,-betastep*0.25im,Tdvp(),ca) # find exp(-beta*H)
    end

    @test sxdat[end]<sxdat[1]
end